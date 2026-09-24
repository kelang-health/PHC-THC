-- v2122: editable field intake only. Never updates JHCIS or verified Cloud registry.
create or replace function public.field_editable_house_requests_v2122()
returns table(id uuid,house_no text,house_id_11 text,moo text,community text,
 latitude double precision,longitude double precision,verification_status text,
 updated_at timestamptz)
language sql stable security definer set search_path = ''
as $$
 select h.id,h.house_no,h.house_id_11,h.moo,h.community,h.latitude,h.longitude,
 h.verification_status,h.updated_at from public.houses h
 join public.profiles p on p.user_id=auth.uid() and p.active=true
 where h.entry_source='field' and h.superseded_by is null
 and h.jhcis_verified_at is null
 and h.verification_status in ('pending_jhcis_create','pending_jhcis_update','review_required')
 and (p.role='admin'
  or (p.role='staff' and nullif(btrim(p.community),'') is not null
      and btrim(h.community)=btrim(p.community))
  or (p.role='user' and h.created_by_user_id=auth.uid()
      and p.volunteer_pid is not null
      and h.created_by_volunteer_pid=p.volunteer_pid))
 order by coalesce(h.field_created_at,h.updated_at) desc limit 200
$$;

create or replace function public.field_editable_member_requests_v2122(p_house_id uuid)
returns table(id uuid,updated_at timestamptz,full_name text,birth_date date)
language sql stable security definer set search_path = ''
as $$
 select r.id,r.updated_at,r.full_name,r.birth_date
 from public.household_member_requests r
 join public.houses h on h.id=r.house_id
 join public.profiles p on p.user_id=auth.uid() and p.active=true
 where r.house_id=p_house_id and r.status in ('pending','needs_correction')
 and r.linked_person_id is null and h.superseded_by is null
 and coalesce(r.jhcis_verification_status,'') not in
   ('verified_jhcis','linked','rejected','cancelled')
 and (
   p.role='admin'
   or (p.role='staff' and nullif(btrim(p.community),'') is not null
       and btrim(h.community)=btrim(p.community))
   or (p.role='user' and r.submitted_by=auth.uid()
       and p.volunteer_pid is not null
       and (h.volunteer_pid=p.volunteer_pid
           or (h.created_by_user_id=auth.uid()
               and h.created_by_volunteer_pid=p.volunteer_pid)))
 )
 order by r.created_at desc limit 100
$$;

create or replace function public.edit_pending_house_request_v2122(
 p_house_id uuid,p_expected_updated_at timestamptz,p_house_no text,
 p_house_id_11 text,p_change_location boolean default false,
 p_latitude double precision default null,p_longitude double precision default null,
 p_coordinate_source text default 'map')
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
 v_profile public.profiles%rowtype;
 v_old public.houses%rowtype;
 v_new public.houses%rowtype;
 v_house_no text:=btrim(coalesce(p_house_no,''));
 v_id11 text:=btrim(coalesce(p_house_id_11,''));
 v_location jsonb;
 v_source text:=lower(btrim(coalesce(p_coordinate_source,'map')));
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into v_profile from public.profiles where user_id=auth.uid() and active=true;
 if not found or v_profile.role not in ('admin','staff','user') then
   raise exception 'PROFILE_NOT_ACTIVE'; end if;
 select * into v_old from public.houses where id=p_house_id for update;
 if not found then raise exception 'HOUSE_NOT_FOUND'; end if;
 if v_old.entry_source is distinct from 'field'
   or v_old.superseded_by is not null or v_old.jhcis_verified_at is not null
   or v_old.verification_status not in
     ('pending_jhcis_create','pending_jhcis_update','review_required')
 then raise exception 'REQUEST_ALREADY_IN_REVIEW_OR_VERIFIED'; end if;
 if not (v_profile.role='admin'
   or (v_profile.role='staff' and nullif(btrim(v_profile.community),'') is not null
       and btrim(v_profile.community)=btrim(v_old.community))
   or (v_profile.role='user' and v_old.created_by_user_id=auth.uid()
       and v_profile.volunteer_pid is not null
       and v_old.created_by_volunteer_pid=v_profile.volunteer_pid))
 then raise exception 'HOUSE_OUT_OF_SCOPE'; end if;
 if p_expected_updated_at is null or
    v_old.updated_at is distinct from p_expected_updated_at
 then raise exception 'REQUEST_CHANGED_RELOAD'; end if;
 if v_house_no='' or char_length(v_house_no)>50 then raise exception 'INVALID_HOUSE_NO'; end if;
 if v_id11 !~ '^[0-9]{11}$' then raise exception 'HOUSE_ID_11_REQUIRED'; end if;
 if p_change_location then
   if v_source not in ('gps','map') then raise exception 'INVALID_COORDINATE_SOURCE'; end if;
   v_location:=public.check_house_location(p_latitude,p_longitude,v_old.community);
   if coalesce((v_location->>'allowed')::boolean,false) is not true then
     raise exception 'OUTSIDE_TAMBON_OR_COMMUNITY'; end if;
 end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('house11:'||v_id11,0));
 if exists(select 1 from public.houses h where h.house_id_11=v_id11 and h.id<>v_old.id
           and h.superseded_by is null) then raise exception 'DUPLICATE_HOUSE_ID_11'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'houseno:'||coalesce(v_old.moo,'')||':'||
    lower(regexp_replace(v_house_no,'[[:space:]]+','','g')),0));
 if exists(select 1 from public.houses h where h.id<>v_old.id
       and h.superseded_by is null and btrim(h.moo)=btrim(v_old.moo)
       and lower(regexp_replace(btrim(h.house_no),'[[:space:]]+','','g'))=
           lower(regexp_replace(v_house_no,'[[:space:]]+','','g')))
 then raise exception 'DUPLICATE_HOUSE_NO_MOO'; end if;
 update public.houses h set house_no=v_house_no,house_id_11=v_id11,
  latitude=case when p_change_location then p_latitude else h.latitude end,
  longitude=case when p_change_location then p_longitude else h.longitude end,
  coordinate_source=case when p_change_location then v_source else h.coordinate_source end,
  coordinate_status=case when p_change_location then 'resolved_by_community' else h.coordinate_status end,
  inside_tambon=case when p_change_location then (v_location->>'inside_tambon')::boolean else h.inside_tambon end,
  inside_community=case when p_change_location then (v_location->>'inside_community')::boolean else h.inside_community end,
  coordinate_distance_m=case when p_change_location then null else h.coordinate_distance_m end,
  updated_at=clock_timestamp(), verification_status='pending_jhcis_create',
  jhcis_verified_at=null,jhcis_verified_hcode=null,
  verification_note='ผู้แจ้งแก้ไขข้อมูล รอตรวจ JHCIS ใหม่',
  review_required=true,review_reason='ข้อมูลภาคสนามแก้ไข รอตรวจ JHCIS ใหม่'
  where h.id=v_old.id returning * into v_new;
 insert into public.house_registration_audit(
   house_id,user_id,role,volunteer_pid,action,before_data,after_data)
 values(v_old.id,auth.uid(),v_profile.role,v_profile.volunteer_pid,
   'field_pending_correction',to_jsonb(v_old),to_jsonb(v_new));
 return jsonb_build_object('ok',true,'id',v_new.id,'updated_at',v_new.updated_at,
    'verification_status',v_new.verification_status);
end $$;

create or replace function public.edit_pending_member_request_v2122(
 p_request_id uuid,p_expected_updated_at timestamptz,p_first_name text,
 p_last_name text,p_birth_date date,p_new_citizen_id text default null)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
 v_profile public.profiles%rowtype;
 v_old public.household_member_requests%rowtype;
 v_house public.houses%rowtype;
 v_first text:=regexp_replace(btrim(coalesce(p_first_name,'')),'[[:space:]]+',' ','g');
 v_last text:=regexp_replace(btrim(coalesce(p_last_name,'')),'[[:space:]]+',' ','g');
 v_cid text;
 v_hash text;
 v_last4 text;
 v_person_exists boolean;
 v_new public.household_member_requests%rowtype;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into v_profile from public.profiles where user_id=auth.uid() and active=true;
 if not found or v_profile.role not in ('admin','staff','user')
 then raise exception 'PROFILE_NOT_ACTIVE'; end if;
 select * into v_old from public.household_member_requests
   where id=p_request_id for update;
 if not found then raise exception 'REQUEST_NOT_FOUND'; end if;
 select * into v_house from public.houses where id=v_old.house_id;
 if not found or v_house.superseded_by is not null
 then raise exception 'HOUSE_NOT_AVAILABLE'; end if;
 if v_old.status not in ('pending','needs_correction')
  or v_old.linked_person_id is not null
  or coalesce(v_old.jhcis_verification_status,'') in
    ('verified_jhcis','linked','rejected','cancelled')
 then raise exception 'REQUEST_ALREADY_IN_REVIEW_OR_VERIFIED'; end if;
 if not (v_profile.role='admin'
  or (v_profile.role='staff' and nullif(btrim(v_profile.community),'') is not null
       and btrim(v_profile.community)=btrim(v_house.community))
  or (v_profile.role='user' and v_old.submitted_by=auth.uid()
       and v_profile.volunteer_pid is not null
       and (v_house.volunteer_pid=v_profile.volunteer_pid
        or (v_house.created_by_user_id=auth.uid()
         and v_house.created_by_volunteer_pid=v_profile.volunteer_pid))))
 then raise exception 'HOUSE_OUT_OF_SCOPE'; end if;
 if p_expected_updated_at is null or
   v_old.updated_at is distinct from p_expected_updated_at
 then raise exception 'REQUEST_CHANGED_RELOAD'; end if;
 if char_length(v_first) not between 1 and 80 or
    char_length(v_last) not between 1 and 100 then raise exception 'INVALID_NAME'; end if;
 if p_birth_date is null or p_birth_date>current_date or
   p_birth_date<current_date-interval '120 years' then raise exception 'INVALID_BIRTH_DATE'; end if;
 v_hash:=v_old.citizen_id_hash;
 v_last4:=v_old.citizen_id_last4;
 if p_new_citizen_id is not null then
   v_cid:=regexp_replace(p_new_citizen_id,'[[:space:]]+','','g');
   if not private.thai_cid_valid_v190(v_cid)
   then raise exception 'INVALID_THAI_CITIZEN_ID'; end if;
   v_hash:=private.cid_hash_v190(v_cid);
   v_last4:=right(v_cid,4);
 end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('membercid:'||v_hash,0));
 if exists(select 1 from public.household_member_requests r
  where r.id<>v_old.id and r.citizen_id_hash=v_hash
  and (r.status in ('pending','needs_correction') or
       (r.status='verified' and r.linked_person_id is null)))
 then raise exception 'DUPLICATE_MEMBER_REQUEST'; end if;
 v_person_exists:=exists(select 1 from public.health_persons p
      where p.citizen_id_hash=v_hash and p.active=true);
 update public.household_member_requests r set
   full_name=v_first||' '||v_last,birth_date=p_birth_date,
   citizen_id_cipher=case when p_new_citizen_id is not null
                       then private.encrypt_text_v190(v_cid) else r.citizen_id_cipher end,
   citizen_id_hash=v_hash,citizen_id_last4=v_last4,
   status='pending',review_note=null,reviewed_by=null,reviewed_at=null,
   jhcis_verification_status=case when v_person_exists
       then 'pending_jhcis_update' else 'pending_jhcis_create' end,
   jhcis_verification_note='ผู้แจ้งแก้ไขคำขอ รอตรวจ JHCIS ใหม่',
   jhcis_checked_at=null,updated_at=clock_timestamp()
   where r.id=v_old.id returning * into v_new;
 insert into public.health_audit_log(operator_id,action,entity,entity_id,
   source_pcucode,hcode,severity,details)
 values(auth.uid(),'UPDATE_PENDING','household_member_request',v_new.id::text,
   v_house.source_pcucode,v_house.hcode,'pending',
   jsonb_build_object('changed_fields',jsonb_build_array('name','birth_date',
      case when p_new_citizen_id is null then 'cid_unchanged' else 'cid_replaced' end),
      'old_last4',v_old.citizen_id_last4,'new_last4',v_new.citizen_id_last4,
      'recheck_jhcis',true));
 return jsonb_build_object('ok',true,'id',v_new.id,'updated_at',v_new.updated_at,
   'status',v_new.status,'jhcis_verification_status',v_new.jhcis_verification_status,
   'masked_citizen_id','•••••••••'||v_new.citizen_id_last4);
end $$;

-- Original owner trigger rejects Staff edits of unassigned houses. Open ONLY
-- pending field-house corrections inside the account's own community/ownership.
create or replace function private.protect_house_owner_v2045()
returns trigger language plpgsql security definer
set search_path = 'public','private','extensions'
as $$
declare
 v_auth_role text:=coalesce(auth.role(),'');
 v_profile public.profiles%rowtype;
 v_ownership_unchanged boolean;
begin
 if v_auth_role='authenticated' then
  select * into v_profile from public.profiles
  where user_id=auth.uid() and active=true limit 1;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;
  if v_profile.role in ('user','staff') then
   v_ownership_unchanged:=
       new.volunteer_pid is not distinct from old.volunteer_pid
       and new.created_by_volunteer_pid is not distinct from old.created_by_volunteer_pid
       and new.created_by_user_id is not distinct from old.created_by_user_id
       and new.entry_source is not distinct from old.entry_source;
   if old.entry_source='field' and old.superseded_by is null
    and old.jhcis_verified_at is null
    and old.verification_status in
      ('pending_jhcis_create','pending_jhcis_update','review_required')
    and v_ownership_unchanged
    and ( (v_profile.role='staff' and
            nullif(btrim(v_profile.community),'') is not null
            and btrim(v_profile.community)=btrim(old.community))
       or (v_profile.role='user' and old.created_by_user_id=auth.uid()
           and v_profile.volunteer_pid is not null
           and old.created_by_volunteer_pid=v_profile.volunteer_pid))
   then return new; end if;
   if v_profile.volunteer_pid is null or old.volunteer_pid is null
     or old.volunteer_pid<>v_profile.volunteer_pid
   then raise exception 'HOUSE_OUT_OF_SCOPE'; end if;
   if not v_ownership_unchanged then raise exception 'HOUSE_OWNER_LOCKED'; end if;
  elsif v_profile.role<>'admin' then raise exception 'HOUSE_OUT_OF_SCOPE'; end if;
 end if;
 return new;
end $$;

revoke all on function public.field_editable_house_requests_v2122() from public,anon;
revoke all on function public.field_editable_member_requests_v2122(uuid) from public,anon;
revoke all on function public.edit_pending_house_request_v2122(uuid,timestamptz,text,text,boolean,double precision,double precision,text) from public,anon;
revoke all on function public.edit_pending_member_request_v2122(uuid,timestamptz,text,text,date,text) from public,anon;
grant execute on function public.field_editable_house_requests_v2122() to authenticated;
grant execute on function public.field_editable_member_requests_v2122(uuid) to authenticated;
grant execute on function public.edit_pending_house_request_v2122(uuid,timestamptz,text,text,boolean,double precision,double precision,text) to authenticated;
grant execute on function public.edit_pending_member_request_v2122(uuid,timestamptz,text,text,date,text) to authenticated;
