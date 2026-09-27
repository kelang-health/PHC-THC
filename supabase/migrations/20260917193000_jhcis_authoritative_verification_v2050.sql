-- OSM-PHC Cloud v2.0.50 โ€” JHCIS Authoritative Verification
-- JHCIS is authoritative for normal house/person operations.
-- Cloud field additions remain pending until an admin updates JHCIS manually and a later sync confirms them.
-- No function in this migration writes back to JHCIS.
begin;

alter table public.houses
  add column if not exists verification_status text not null default 'review_required',
  add column if not exists jhcis_verified_at timestamptz,
  add column if not exists jhcis_verified_hcode text,
  add column if not exists verification_note text not null default '';

alter table public.houses drop constraint if exists houses_verification_status_v2050;

alter table public.houses add constraint houses_verification_status_v2050 check (
  verification_status in ('verified_jhcis','pending_jhcis_create','pending_jhcis_update','review_required','superseded','rejected')
);

-- Conservative backfill: nothing becomes operational merely because it already existed in Cloud.
-- The first v2050 Local->Cloud JHCIS sync promotes actual JHCIS rows to verified_jhcis.
update public.houses
set verification_status=case
      when superseded_by is not null then 'superseded'
      when entry_source='field' then 'pending_jhcis_create'
      else 'review_required'
    end,
    verification_note=case
      when superseded_by is not null then 'เนเธ—เธเธ—เธตเนเธ”เนเธงเธขเธเนเธฒเธ canonical'
      when entry_source='field' then 'เธฃเธญเน€เธเนเธฒเธซเธเนเธฒเธ—เธตเนเธ•เธฃเธงเธเนเธฅเธฐเธเธฑเธเธ—เธถเธเนเธ JHCIS'
      else 'เธฃเธญ JHCIS authoritative sync เธขเธทเธเธขเธฑเธ'
    end;

create index if not exists houses_verified_scope_v2050
  on public.houses(community,volunteer_pid,source_pcucode,hcode)
  where superseded_by is null and verification_status='verified_jhcis';

create index if not exists houses_pending_review_v2050
  on public.houses(verification_status,updated_at desc)
  where superseded_by is null and verification_status<>'verified_jhcis';

alter table public.household_member_requests
  add column if not exists jhcis_verification_status text not null default 'pending_jhcis_create',
  add column if not exists jhcis_verification_note text not null default '',
  add column if not exists jhcis_checked_at timestamptz;

alter table public.household_member_requests drop constraint if exists member_jhcis_verification_status_v2050;

alter table public.household_member_requests add constraint member_jhcis_verification_status_v2050 check (
  jhcis_verification_status in ('verified_jhcis','pending_jhcis_create','pending_jhcis_update','review_required','superseded','rejected')
);

update public.household_member_requests
set jhcis_verification_status=case when linked_person_id is not null then 'verified_jhcis' else 'pending_jhcis_create' end,
    jhcis_verification_note=case when linked_person_id is not null then 'เน€เธเธทเนเธญเธก PID JHCIS เนเธฅเนเธง' else 'เธฃเธญเธ•เธฃเธงเธ JHCIS' end;

create index if not exists member_requests_jhcis_status_v2050
  on public.household_member_requests(jhcis_verification_status,created_at desc);

-- User/staff normal house scope is JHCIS-verified only. Their own pending field record remains readable
-- only so it can be shown in a separate pending panel. Admin can review every non-superseded row.
drop policy if exists houses_select on public.houses;

create policy houses_select on public.houses for select to authenticated
using (
  superseded_by is null and (
    private.current_role()='admin'
    or (
      verification_status='verified_jhcis' and (
        (private.current_role()='staff' and coalesce(btrim(private.current_moo()),'')<>'' and btrim(moo)=btrim(private.current_moo()))
        or (private.current_role()='user' and volunteer_pid=private.current_volunteer_pid())
      )
    )
    or (
      verification_status<>'verified_jhcis'
      and private.current_role() in ('user','staff')
      and (created_by_user_id=auth.uid() or created_by_volunteer_pid=private.current_volunteer_pid())
    )
  )
);

-- Quota is based on submissions by the VHV, not authoritative assignment.
create or replace function public.house_add_quota()
returns jsonb language plpgsql security definer set search_path=public,private,extensions as $$
declare v_profile public.profiles%rowtype; v_used integer:=0;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_profile from public.profiles where user_id=auth.uid() and active=true;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;
  if v_profile.role='admin' then return jsonb_build_object('limit',null,'used',0,'remaining',null,'role',v_profile.role); end if;
  if v_profile.role not in ('staff','user') or v_profile.volunteer_pid is null then raise exception 'HOUSE_ADD_NOT_ALLOWED'; end if;
  select count(*) into v_used from public.houses
   where entry_source='field' and created_by_volunteer_pid=v_profile.volunteer_pid and superseded_by is null and verification_status<>'rejected';
  return jsonb_build_object('limit',30,'used',v_used,'remaining',greatest(30-v_used,0),'role',v_profile.role,'volunteer_pid',v_profile.volunteer_pid);
end; $$;

revoke all on function public.house_add_quota() from public,anon;

grant execute on function public.house_add_quota() to authenticated;

create or replace function public.add_house_field(
  p_house_no text,p_house_id_11 text,p_latitude double precision,p_longitude double precision,
  p_source text default 'gps',p_community text default null
) returns jsonb language plpgsql security definer set search_path=public,private,extensions as $$
declare
  v_uid uuid:=auth.uid(); v_profile public.profiles%rowtype; v_community public.communities%rowtype;
  v_point extensions.geometry; v_house_no text:=btrim(coalesce(p_house_no,'')); v_house_no_key text;
  v_house_id text:=btrim(coalesce(p_house_id_11,'')); v_source text:=lower(btrim(coalesce(p_source,'gps')));
  v_community_name text; v_count integer:=0; v_inside_tambon boolean:=false; v_inside_community boolean:=false;
  v_new_id uuid:=extensions.gen_random_uuid(); v_hcode text;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_profile from public.profiles where user_id=v_uid and active=true;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;
  if v_profile.role not in ('admin','staff','user') then raise exception 'HOUSE_ADD_NOT_ALLOWED'; end if;
  if v_house_no='' or length(v_house_no)>50 then raise exception 'INVALID_HOUSE_NO'; end if;
  v_house_no_key:=lower(regexp_replace(v_house_no,'\s+','','g'));
  if v_house_id !~ '^[0-9]{11}$' then raise exception 'HOUSE_ID_11_REQUIRED'; end if;
  if p_latitude is null or p_longitude is null or p_latitude<5 or p_latitude>21 or p_longitude<97 or p_longitude>106 then raise exception 'INVALID_COORDINATES'; end if;
  if v_source not in ('gps','map') then raise exception 'INVALID_COORDINATE_SOURCE'; end if;
  v_community_name:=case when v_profile.role='admin' then btrim(coalesce(p_community,'')) else btrim(coalesce(v_profile.community,'')) end;
  if v_community_name='' then raise exception 'COMMUNITY_REQUIRED'; end if;
  select * into v_community from public.communities where active=true and btrim(name)=v_community_name limit 1;
  if not found then raise exception 'COMMUNITY_NOT_FOUND'; end if;
  if v_profile.role='staff' and btrim(v_community.name)<>btrim(v_profile.community) then raise exception 'HOUSE_OUT_OF_SCOPE'; end if;
  v_point:=extensions.st_setsrid(extensions.st_makepoint(p_longitude,p_latitude),4326);
  select exists(select 1 from public.tambon_boundaries t where t.tambon_code='520105' and t.geom is not null and extensions.st_covers(extensions.st_makevalid(t.geom),v_point)) into v_inside_tambon;
  if not v_inside_tambon then raise exception 'OUTSIDE_TAMBON'; end if;
  select coalesce(extensions.st_covers(extensions.st_makevalid(v_community.geom),v_point),false) into v_inside_community;
  if not v_inside_community then raise exception 'OUTSIDE_COMMUNITY'; end if;
  perform pg_advisory_xact_lock(pg_catalog.hashtextextended('house11:'||v_house_id,0));
  if exists(select 1 from public.houses where house_id_11=v_house_id and superseded_by is null and verification_status<>'rejected') then raise exception 'DUPLICATE_HOUSE_ID_11'; end if;
  perform pg_advisory_xact_lock(pg_catalog.hashtextextended('houseno:'||v_community.moo||':'||v_house_no_key,0));
  if exists(select 1 from public.houses h where h.superseded_by is null and h.verification_status<>'rejected' and btrim(h.moo)=btrim(v_community.moo) and lower(regexp_replace(btrim(h.house_no),'\s+','','g'))=v_house_no_key) then raise exception 'DUPLICATE_HOUSE_NO_MOO'; end if;
  if v_profile.role in ('staff','user') then
    if v_profile.volunteer_pid is null then raise exception 'VOLUNTEER_NOT_LINKED'; end if;
    perform pg_advisory_xact_lock(pg_catalog.hashtextextended('vhvquota:'||v_profile.volunteer_pid::text,0));
    select count(*) into v_count from public.houses where entry_source='field' and created_by_volunteer_pid=v_profile.volunteer_pid and superseded_by is null and verification_status<>'rejected';
    if v_count>=30 then raise exception 'VHV_HOUSE_LIMIT'; end if;
  end if;
  v_hcode:='field-'||replace(v_new_id::text,'-','');
  insert into public.houses(
    id,source_pcucode,hcode,house_no,moo,community,latitude,longitude,geom,coordinate_source,coordinate_status,
    coordinate_distance_m,inside_tambon,inside_community,volunteer_pid,record_status,review_required,review_reason,
    house_id_11,entry_source,created_by_user_id,created_by_volunteer_pid,field_created_at,updated_at,
    verification_status,verification_note
  ) values (
    v_new_id,'06116',v_hcode,v_house_no,v_community.moo,v_community.name,p_latitude,p_longitude,v_point,v_source,
    case when v_profile.role='admin' then 'resolved_by_tambon' else 'resolved_by_community' end,
    null,true,true,null,'เธฃเธญเธ•เธฃเธงเธ JHCIS',true,'เธเนเธฒเธเน€เธเธดเนเธกเธเธฒเธ Cloud เธฃเธญเน€เธเนเธฒเธซเธเนเธฒเธ—เธตเนเธ•เธฃเธงเธ/เธเธฑเธเธ—เธถเธ JHCIS',
    v_house_id,'field',v_uid,v_profile.volunteer_pid,now(),now(),'pending_jhcis_create','เธฃเธญเน€เธเนเธฒเธซเธเนเธฒเธ—เธตเนเธ•เธฃเธงเธเนเธฅเธฐเธเธฑเธเธ—เธถเธเนเธ JHCIS'
  );
  insert into public.house_registration_audit(house_id,user_id,role,volunteer_pid,action,before_data,after_data)
  select v_new_id,v_uid,v_profile.role,v_profile.volunteer_pid,'add',null,to_jsonb(h) from public.houses h where h.id=v_new_id;
  if v_profile.role in ('staff','user') then v_count:=v_count+1; end if;
  return jsonb_build_object('success',true,'house_id',v_new_id,'house_no',v_house_no,'house_id_11',v_house_id,'moo',v_community.moo,
    'community',v_community.name,'verification_status','pending_jhcis_create','status_label','เธฃเธญเธ•เธฃเธงเธ JHCIS',
    'quota_limit',case when v_profile.role='admin' then null else 30 end,'quota_used',case when v_profile.role='admin' then null else v_count end,
    'quota_remaining',case when v_profile.role='admin' then null else greatest(30-v_count,0) end);
end; $$;

revoke all on function public.add_house_field(text,text,double precision,double precision,text,text) from public,anon;

grant execute on function public.add_house_field(text,text,double precision,double precision,text,text) to authenticated;

create or replace function public.my_pending_house_requests_v2050()
returns table(id uuid,hcode text,house_no text,house_id_11 text,moo text,community text,verification_status text,verification_note text,review_required boolean,review_reason text,created_at timestamptz)
language sql stable security definer set search_path='' as $$
  select h.id,h.hcode,h.house_no,h.house_id_11,h.moo,h.community,h.verification_status,h.verification_note,h.review_required,h.review_reason,coalesce(h.field_created_at,h.updated_at) as created_at
  from public.houses h
  where h.superseded_by is null and h.verification_status<>'verified_jhcis'
    and h.verification_status<>'rejected'
    and (private.current_role()='admin' or (private.current_role() in ('user','staff') and (h.created_by_user_id=auth.uid() or h.created_by_volunteer_pid=private.current_volunteer_pid())))
  order by coalesce(h.field_created_at,h.updated_at) desc
$$;

revoke all on function public.my_pending_house_requests_v2050() from public,anon;

grant execute on function public.my_pending_house_requests_v2050() to authenticated;

-- Member requests may be filed against a pending house by its submitter, but that house grants no health/worklist scope.
create or replace function private.can_submit_member_request_v2050(p_house_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(
   select 1 from public.houses h where h.id=p_house_id and h.superseded_by is null and (
     (h.verification_status='verified_jhcis' and private.health_can_access_house(h.source_pcucode,h.hcode))
     or private.current_role()='admin'
     or (h.verification_status<>'verified_jhcis' and private.current_role() in ('user','staff') and (h.created_by_user_id=auth.uid() or h.created_by_volunteer_pid=private.current_volunteer_pid()))
   )
 )
$$;

revoke all on function private.can_submit_member_request_v2050(uuid) from public,anon,authenticated;

create or replace function public.submit_household_member_request_v2043(
  p_house_id uuid,p_citizen_id text,p_first_name text,p_last_name text,p_birth_date date
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_cid text:=regexp_replace(coalesce(p_citizen_id,''),'\s','','g');
  v_first text:=regexp_replace(btrim(coalesce(p_first_name,'')),'\s+',' ','g');
  v_last text:=regexp_replace(btrim(coalesce(p_last_name,'')),'\s+',' ','g');
  v_name text; v_hash text; v_id uuid; v_house public.houses%rowtype; v_existing bigint; v_person_exists boolean:=false;
begin
  if auth.uid() is null or private.current_role() not in ('user','staff','admin') then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_house from public.houses where id=p_house_id;
  if not found then raise exception 'HOUSE_NOT_FOUND'; end if;
  if not private.can_submit_member_request_v2050(p_house_id) then raise exception 'HOUSE_OUT_OF_SCOPE'; end if;
  if not private.thai_cid_valid_v190(v_cid) then raise exception 'INVALID_THAI_CITIZEN_ID'; end if;
  if char_length(v_first)<1 then raise exception 'FIRST_NAME_REQUIRED'; end if;
  if char_length(v_last)<1 then raise exception 'LAST_NAME_REQUIRED'; end if;
  if char_length(v_first)>80 or char_length(v_last)>100 then raise exception 'NAME_TOO_LONG'; end if;
  if p_birth_date is null or p_birth_date>current_date or p_birth_date<current_date-interval '120 years' then raise exception 'INVALID_BIRTH_DATE'; end if;
  v_name:=v_first||' '||v_last; v_hash:=private.cid_hash_v190(v_cid);
  select count(*) into v_existing from public.household_member_requests r where r.citizen_id_hash=v_hash and r.status in ('pending','needs_correction');
  if v_existing>0 then raise exception 'DUPLICATE_MEMBER_REQUEST'; end if;
  v_person_exists:=exists(select 1 from public.health_persons p where p.citizen_id_hash=v_hash and p.active=true);
  insert into public.household_member_requests(house_id,submitted_by,citizen_id_cipher,citizen_id_hash,citizen_id_last4,full_name,birth_date,jhcis_verification_status,jhcis_verification_note)
  values(p_house_id,auth.uid(),private.encrypt_text_v190(v_cid),v_hash,right(v_cid,4),v_name,p_birth_date,
    case when v_person_exists then 'pending_jhcis_update' else 'pending_jhcis_create' end,
    case when v_person_exists then 'เธเธเธเนเธญเธกเธนเธฅเน€เธ”เธดเธกเนเธ Cloud/JHCIS projection เธฃเธญเธ•เธฃเธงเธ PID/Type' else 'เธฃเธญเธ•เธฃเธงเธเน€เธฅเธ 13 เธซเธฅเธฑเธเธเธฑเธ JHCIS' end)
  returning id into v_id;
  perform private.emit_admin_notification_v190('member_request.created','warning','OSM-PHC: เธกเธตเธเธณเธเธญเน€เธเธดเนเธกเธชเธกเธฒเธเธดเธเนเธซเธกเน',
    case when v_person_exists then 'เธเธเธเนเธญเธกเธนเธฅเธเธธเธเธเธฅเน€เธ”เธดเธกเธ—เธตเนเธญเธฒเธเธ•เธฃเธเธเธฑเธ เธเธฃเธธเธ“เธฒเธ•เธฃเธงเธเธชเธญเธ JHCIS เนเธฅเธฐเน€เธเธทเนเธญเธก PID' else 'เธกเธตเธเธณเธเธญเน€เธเธดเนเธกเธชเธกเธฒเธเธดเธเนเธซเธกเน เธเธฃเธธเธ“เธฒเธ•เธฃเธงเธเธชเธญเธ JHCIS' end,
    '?panel=admin-member-requests',jsonb_build_object('request_id',v_id,'community',v_house.community,'existing_person_found',v_person_exists),true);
  insert into public.health_audit_log(operator_id,action,entity,entity_id,source_pcucode,hcode,severity,details)
  values(auth.uid(),'CREATE','household_member_request',v_id::text,v_house.source_pcucode,v_house.hcode,'pending',jsonb_build_object('house_id',p_house_id,'cid_last4',right(v_cid,4),'jhcis_verification_status',case when v_person_exists then 'pending_jhcis_update' else 'pending_jhcis_create' end));
  return jsonb_build_object('ok',true,'id',v_id,'status','pending','jhcis_verification_status',case when v_person_exists then 'pending_jhcis_update' else 'pending_jhcis_create' end,'masked_citizen_id','โ€ขโ€ขโ€ขโ€ขโ€ขโ€ขโ€ขโ€ขโ€ข'||right(v_cid,4),'existing_person_found',v_person_exists);
end; $$;

revoke all on function public.submit_household_member_request_v2043(uuid,text,text,text,date) from public,anon;

grant execute on function public.submit_household_member_request_v2043(uuid,text,text,text,date) to authenticated;

-- Authoritative reconciliation: existing v2048 logic handles canonical/legacy identity; this layer promotes only incoming JHCIS rows.
create or replace function public.service_reconcile_jhcis_houses_v2050(p_rows jsonb)
returns jsonb language plpgsql security definer set search_path=public,private,extensions as $$
declare v_base jsonb; v_item jsonb; v_pcucode text; v_hcode text; v_pid bigint; v_id uuid; v_verified integer:=0;
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  if p_rows is null or jsonb_typeof(p_rows)<>'array' then raise exception 'ROWS_ARRAY_REQUIRED'; end if;
  v_base:=public.service_reconcile_jhcis_houses_v2048(p_rows);
  for v_item in select value from jsonb_array_elements(p_rows) loop
    v_pcucode:=btrim(coalesce(v_item->>'source_pcucode','')); v_hcode:=btrim(coalesce(v_item->>'hcode',''));
    if v_pcucode='' or v_hcode='' then continue; end if;
    v_pid:=nullif(v_item->>'volunteer_pid','')::bigint;
    select h.id into v_id from public.houses h where h.source_pcucode=v_pcucode and h.hcode=v_hcode and h.superseded_by is null order by h.updated_at desc limit 1;
    if v_id is null then continue; end if;
    update public.houses set
      volunteer_pid=v_pid,
      verification_status='verified_jhcis',
      jhcis_verified_at=now(),
      jhcis_verified_hcode=v_hcode,
      verification_note='เธขเธทเธเธขเธฑเธเธเธฒเธ jhcisdb.house; เธเธนเนเธฃเธฑเธเธเธดเธ”เธเธญเธเธเธฒเธ house.pidvola',
      updated_at=now()
    where id=v_id;
    v_verified:=v_verified+1;
  end loop;
  update public.houses set verification_status='superseded',verification_note='เนเธ—เธเธ—เธตเนเธ”เนเธงเธข JHCIS canonical'
    where superseded_by is not null and verification_status<>'superseded';
  return coalesce(v_base,'{}'::jsonb)||jsonb_build_object('verified_jhcis',v_verified,'assignment_source','jhcisdb.house.pidvola','verification_policy','JHCIS authoritative','jhcis_write_back',false);
end; $$;

revoke all on function public.service_reconcile_jhcis_houses_v2050(jsonb) from public,anon,authenticated;

grant execute on function public.service_reconcile_jhcis_houses_v2050(jsonb) to service_role;

-- Persist Local read-only reconciliation results so Cloud/Admin/VHV see one shared state.
create or replace function public.service_set_jhcis_verification_v2050(p_houses jsonb default '[]'::jsonb,p_members jsonb default '[]'::jsonb)
returns jsonb language plpgsql security definer set search_path=public,private,extensions as $$
declare x jsonb; v_status text; hc integer:=0; mc integer:=0;
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  if jsonb_typeof(coalesce(p_houses,'[]'::jsonb))<>'array' or jsonb_typeof(coalesce(p_members,'[]'::jsonb))<>'array' then raise exception 'ARRAY_REQUIRED'; end if;
  for x in select value from jsonb_array_elements(coalesce(p_houses,'[]'::jsonb)) loop
    v_status:=coalesce(x->>'verification_status','review_required');
    if v_status not in ('verified_jhcis','pending_jhcis_create','pending_jhcis_update','review_required','superseded','rejected') then v_status:='review_required'; end if;
    update public.houses set verification_status=v_status,verification_note=left(coalesce(x->>'note',''),500),updated_at=now()
      where id=(x->>'house_id')::uuid and superseded_by is null and verification_status<>'verified_jhcis';
    if found then hc:=hc+1; end if;
  end loop;
  for x in select value from jsonb_array_elements(coalesce(p_members,'[]'::jsonb)) loop
    v_status:=coalesce(x->>'verification_status','review_required');
    if v_status not in ('verified_jhcis','pending_jhcis_create','pending_jhcis_update','review_required','superseded','rejected') then v_status:='review_required'; end if;
    update public.household_member_requests set jhcis_verification_status=v_status,jhcis_verification_note=left(coalesce(x->>'note',''),500),jhcis_checked_at=now(),updated_at=now()
      where id=(x->>'request_id')::uuid and jhcis_verification_status<>'verified_jhcis';
    if found then mc:=mc+1; end if;
  end loop;
  return jsonb_build_object('houses_updated',hc,'members_updated',mc,'jhcis_write_back',false);
end; $$;

revoke all on function public.service_set_jhcis_verification_v2050(jsonb,jsonb) from public,anon,authenticated;

grant execute on function public.service_set_jhcis_verification_v2050(jsonb,jsonb) to service_role;

-- Link wrapper sets the normalized verification state after the existing strict v2045 checks pass.
create or replace function public.service_link_member_request_v2050(p_request_id uuid,p_source_pcucode text,p_source_pid bigint)
returns jsonb language plpgsql security definer set search_path=public,private,extensions as $$
declare r jsonb;
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  r:=public.service_link_member_request_v2045(p_request_id,p_source_pcucode,p_source_pid);
  update public.household_member_requests set jhcis_verification_status='verified_jhcis',jhcis_verification_note='เธขเธทเธเธขเธฑเธเนเธฅเธฐเน€เธเธทเนเธญเธก PID เธเธฒเธ JHCIS',jhcis_checked_at=now(),updated_at=now() where id=p_request_id;
  return coalesce(r,'{}'::jsonb)||jsonb_build_object('jhcis_verification_status','verified_jhcis');
end; $$;

revoke all on function public.service_link_member_request_v2050(uuid,text,bigint) from public,anon,authenticated;

grant execute on function public.service_link_member_request_v2050(uuid,text,bigint) to service_role;

create or replace function private.health_can_access_house(p_pcucode text,p_hcode text)
returns boolean language sql stable security definer set search_path=''
as $$
  select exists(
    select 1 from public.houses h
    where h.source_pcucode=p_pcucode and h.hcode=p_hcode and h.superseded_by is null and h.verification_status='verified_jhcis'
      and (
        private.current_role()='admin'
        or (private.current_role()='staff' and private.community_key(private.current_community())<>'' and private.community_key(h.community)=private.community_key(private.current_community()))
        or (private.current_role()='user' and h.volunteer_pid=private.current_volunteer_pid())
      )
  )
$$;

revoke all on function private.health_can_access_house(text,text) from public,anon,authenticated;

grant execute on function private.health_can_access_house(text,text) to authenticated;

create or replace function public.spatial_scope_dashboard()
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_own_moo text;
  v_total bigint := 0;
  v_assigned bigint := 0;
  v_pinned bigint := 0;
  v_field bigint := 0;
  v_review bigint := 0;
  v_out_tambon bigint := 0;
  v_out_community bigint := 0;
  v_missing bigint := 0;
  v_missing_id11 bigint := 0;
  v_pct numeric := 0;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_profile from public.profiles where user_id=v_uid and active=true;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;
  if v_profile.role in ('staff','user') then
    select c.moo into v_own_moo from public.communities c
    where c.active=true and btrim(c.name)=btrim(coalesce(v_profile.community,'')) limit 1;
  end if;
  select
    count(h.id),
    count(h.id) filter (where h.volunteer_pid is not null),
    count(h.id) filter (where h.latitude is not null and h.longitude is not null),
    count(h.id) filter (where h.coordinate_status like 'resolved_%'),
    count(h.id) filter (where h.review_required=true),
    count(h.id) filter (where h.inside_tambon=false),
    count(h.id) filter (where h.inside_community=false and h.inside_tambon is distinct from false),
    count(h.id) filter (where h.latitude is null or h.longitude is null),
    count(h.id) filter (where h.house_id_11 is null or h.house_id_11 !~ '^[0-9]{11}$')
  into v_total,v_assigned,v_pinned,v_field,v_review,v_out_tambon,v_out_community,v_missing,v_missing_id11
  from public.houses h
  join public.communities c on c.active=true and btrim(c.name)=btrim(h.community)
  where h.superseded_by is null and h.verification_status='verified_jhcis'
    and (v_profile.role='admin'
     or (v_profile.role='staff' and c.moo=v_own_moo)
     or (v_profile.role='user' and btrim(c.name)=btrim(coalesce(v_profile.community,''))));
  if v_total>0 then v_pct := round((v_field::numeric*100.0)/v_total,1); end if;
  return jsonb_build_object(
    'role',v_profile.role,'community',v_profile.community,'moo',v_own_moo,
    'total_houses',v_total,'assigned_houses',v_assigned,'pinned_houses',v_pinned,
    'field_confirmed',v_field,'review_houses',v_review,
    'outside_tambon',v_out_tambon,'outside_community',v_out_community,
    'outside_any',v_out_tambon+v_out_community,
    'missing_coordinates',v_missing,'missing_house_id_11',v_missing_id11,
    'field_progress_pct',v_pct
  );
end;
$$;

create or replace function public.spatial_community_cards()
returns table(community text, moo text, houses bigint, assigned_houses bigint, pinned_houses bigint, field_confirmed bigint, review_houses bigint, outside_tambon bigint, outside_community bigint, missing_coordinates bigint, volunteers bigint, access_mode text, is_assigned boolean)
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_own_moo text;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_profile from public.profiles where user_id=v_uid and active=true;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;
  if v_profile.role in ('staff','user') then
    select c.moo into v_own_moo from public.communities c
    where c.active=true and btrim(c.name)=btrim(coalesce(v_profile.community,'')) limit 1;
  end if;
  return query
  select c.name::text,c.moo::text,
    count(h.id)::bigint,
    count(h.id) filter (where h.volunteer_pid is not null)::bigint,
    count(h.id) filter (where h.latitude is not null and h.longitude is not null)::bigint,
    count(h.id) filter (where h.coordinate_status like 'resolved_%')::bigint,
    count(h.id) filter (where h.review_required=true)::bigint,
    count(h.id) filter (where h.inside_tambon=false)::bigint,
    count(h.id) filter (where h.inside_community=false and h.inside_tambon is distinct from false)::bigint,
    count(h.id) filter (where h.latitude is null or h.longitude is null)::bigint,
    count(distinct h.volunteer_pid) filter (where h.volunteer_pid is not null)::bigint,
    case when v_profile.role='admin' then 'manage'
         when v_profile.role='staff' and btrim(c.name)=btrim(coalesce(v_profile.community,'')) then 'manage'
         else 'view' end::text,
    (btrim(c.name)=btrim(coalesce(v_profile.community,'')))::boolean
  from public.communities c
  left join public.houses h on btrim(h.community)=btrim(c.name) and h.superseded_by is null and h.verification_status='verified_jhcis'
  where c.active=true and (
    v_profile.role='admin'
    or (v_profile.role='staff' and c.moo=v_own_moo)
    or (v_profile.role='user' and btrim(c.name)=btrim(coalesce(v_profile.community,'')))
  )
  group by c.name,c.moo
  order by nullif(c.moo,'')::int nulls last,c.name;
end;
$$;

create or replace function public.spatial_role_dashboard_v1854()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with ctx as (
    select
      private.current_role() as role,
      private.current_community() as community,
      private.current_volunteer_pid() as volunteer_pid
  ), scoped as (
    select h.*
    from public.houses h, ctx
    where h.superseded_by is null and h.verification_status='verified_jhcis'
      and (ctx.role = 'admin'
      or (
        ctx.role = 'staff'
        and private.community_key(h.community) = private.community_key(ctx.community)
      )
      or (
        ctx.role = 'user'
        and h.volunteer_pid = ctx.volunteer_pid
      ))
  )
  select jsonb_build_object(
    'role', coalesce((select role from ctx), ''),
    'scope_community', coalesce((select community from ctx), ''),
    'total_houses', count(*),
    'pinned_houses', count(*) filter (where latitude is not null and longitude is not null),
    'missing_coordinates', count(*) filter (where latitude is null or longitude is null),
    'review_houses', count(*) filter (where review_required = true),
    'field_confirmed', count(*) filter (where coordinate_status like 'resolved_%'),
    'outside_tambon', count(*) filter (where inside_tambon = false),
    'outside_community', count(*) filter (where inside_community = false)
  )
  from scoped
$$;

create or replace function public.spatial_community_cards_v1854()
returns table (
  community text,
  moo text,
  volunteers bigint,
  houses bigint,
  pinned_houses bigint,
  review_houses bigint,
  assigned_houses bigint,
  outside_tambon bigint,
  outside_community bigint,
  missing_coordinates bigint,
  is_assigned boolean,
  access_mode text
)
language sql
stable
security definer
set search_path = ''
as $$
  with ctx as (
    select
      private.current_role() as role,
      private.current_community() as own_community,
      private.current_volunteer_pid() as volunteer_pid,
      private.current_moo() as own_moo
  ), allowed as (
    select c.name as community, c.moo
    from public.communities c, ctx
    where c.active = true
      and (
        ctx.role = 'admin'
        or (ctx.role = 'staff' and btrim(c.moo) = btrim(ctx.own_moo))
        or (
          ctx.role = 'user'
          and exists (
            select 1 from public.houses h
            where h.superseded_by is null and h.verification_status='verified_jhcis' and h.volunteer_pid = ctx.volunteer_pid
              and private.community_key(h.community) = private.community_key(c.name)
          )
        )
      )
  )
  select
    a.community,
    a.moo,
    count(distinct h.volunteer_pid) filter (where h.volunteer_pid is not null)::bigint as volunteers,
    count(h.id)::bigint as houses,
    count(h.id) filter (where h.latitude is not null and h.longitude is not null)::bigint as pinned_houses,
    count(h.id) filter (where h.review_required = true)::bigint as review_houses,
    count(h.id) filter (where h.volunteer_pid is not null)::bigint as assigned_houses,
    count(h.id) filter (where h.inside_tambon = false)::bigint as outside_tambon,
    count(h.id) filter (where h.inside_community = false)::bigint as outside_community,
    count(h.id) filter (where h.latitude is null or h.longitude is null)::bigint as missing_coordinates,
    (private.community_key(a.community) = private.community_key((select own_community from ctx))) as is_assigned,
    case
      when (select role from ctx) = 'admin' then 'manage'
      when (select role from ctx) = 'staff'
           and private.community_key(a.community) = private.community_key((select own_community from ctx)) then 'manage'
      else 'view'
    end as access_mode
  from allowed a
  left join public.houses h
    on private.community_key(h.community) = private.community_key(a.community)
    and h.superseded_by is null and h.verification_status='verified_jhcis'
    and (
      (select role from ctx) <> 'user'
      or h.volunteer_pid = (select volunteer_pid from ctx)
    )
  group by a.community, a.moo
  order by
    (private.community_key(a.community) = private.community_key((select own_community from ctx))) desc,
    a.moo,
    a.community
$$;

create or replace function public.spatial_house_quick_search(p_term text)
returns table(
  id uuid,
  house_no text,
  hcode text,
  house_id_11 text,
  moo text,
  community text,
  latitude double precision,
  longitude double precision,
  coordinate_status text,
  review_required boolean,
  inside_tambon boolean,
  inside_community boolean,
  volunteer_pid bigint,
  volunteer_name text,
  can_edit boolean,
  spatial_status text
)
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_own_moo text;
  v_term text := left(btrim(coalesce(p_term,'')),60);
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if char_length(v_term)<1 then return; end if;
  select * into v_profile from public.profiles where user_id=v_uid and active=true;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  if v_profile.role in ('staff','user') then
    select c.moo into v_own_moo
    from public.communities c
    where c.active=true and btrim(c.name)=btrim(coalesce(v_profile.community,''))
    limit 1;
  end if;

  return query
  select
    h.id,h.house_no,h.hcode,h.house_id_11,h.moo,h.community,h.latitude,h.longitude,
    h.coordinate_status,h.review_required,h.inside_tambon,h.inside_community,h.volunteer_pid,
    coalesce(v.display_name,'เธขเธฑเธเนเธกเนเนเธ”เนเธกเธญเธเธซเธกเธฒเธข')::text,
    case
      when v_profile.role='admin' then true
      when v_profile.role='staff' then btrim(h.community)=btrim(coalesce(v_profile.community,''))
      when v_profile.role='user' then h.volunteer_pid is not null and h.volunteer_pid=v_profile.volunteer_pid
      else false
    end::boolean,
    case
      when h.latitude is null or h.longitude is null then 'missing'
      when h.inside_tambon=false then 'outside_tambon'
      when h.inside_community=false then 'outside_community'
      when h.review_required=true then 'review'
      when h.coordinate_status like 'resolved_%' then 'field_confirmed'
      else 'pinned'
    end::text
  from public.houses h
  join public.communities c on c.active=true and btrim(c.name)=btrim(h.community)
  left join public.volunteers v on v.source_pid=h.volunteer_pid and v.active=true
  where h.superseded_by is null and h.verification_status='verified_jhcis'
    and (
      v_profile.role='admin'
      or (v_profile.role='staff' and c.moo=v_own_moo)
      or (v_profile.role='user' and btrim(c.name)=btrim(coalesce(v_profile.community,'')))
    )
    and (
      h.house_no ilike '%'||v_term||'%'
      or coalesce(h.hcode,'') ilike '%'||v_term||'%'
      or coalesce(h.house_id_11,'') ilike '%'||v_term||'%'
    )
  order by
    case when h.house_no=v_term then 0 else 1 end,
    h.moo,
    h.community,
    h.house_no collate "C"
  limit 30;
end;
$$;

create or replace function public.spatial_house_exact_search_v1854(p_house_no text)
returns table (
  id uuid,
  house_no text,
  hcode text,
  moo text,
  community text,
  latitude double precision,
  longitude double precision,
  coordinate_status text,
  review_required boolean,
  inside_tambon boolean,
  inside_community boolean,
  volunteer_name text,
  spatial_status text,
  can_edit boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  with ctx as (
    select
      private.current_role() as role,
      private.current_community() as own_community,
      private.current_volunteer_pid() as volunteer_pid,
      private.current_moo() as own_moo
  )
  select
    h.id,
    h.house_no,
    h.hcode,
    h.moo,
    h.community,
    h.latitude,
    h.longitude,
    h.coordinate_status,
    h.review_required,
    h.inside_tambon,
    h.inside_community,
    coalesce(v.display_name, '') as volunteer_name,
    case
      when h.latitude is null or h.longitude is null then 'missing'
      when h.inside_tambon = false then 'outside_tambon'
      when h.inside_community = false then 'outside_community'
      when h.review_required = true then 'review'
      when h.coordinate_status like 'resolved_%' then 'field_confirmed'
      else 'pinned'
    end as spatial_status,
    case
      when (select role from ctx) = 'admin' then true
      when (select role from ctx) = 'staff'
        then private.community_key(h.community) = private.community_key((select own_community from ctx))
      when (select role from ctx) = 'user'
        then h.volunteer_pid = (select volunteer_pid from ctx)
      else false
    end as can_edit
  from public.houses h
  left join public.volunteers v
    on v.source_pcucode = h.source_pcucode and v.source_pid = h.volunteer_pid
  where h.superseded_by is null and h.verification_status='verified_jhcis'
    and coalesce(btrim(p_house_no), '') <> ''
    and lower(btrim(h.house_no)) = lower(btrim(p_house_no))
    and (
      (select role from ctx) = 'admin'
      or (select role from ctx) = 'user'
      or (
        (select role from ctx) = 'staff'
        and btrim(h.moo) = btrim((select own_moo from ctx))
      )
    )
  order by
    (private.community_key(h.community) = private.community_key((select own_community from ctx))) desc,
    h.moo,
    h.community,
    h.house_no
  limit 25
$$;

create or replace function public.spatial_community_houses_v1854(p_community text)
returns table (
  id uuid,
  house_no text,
  hcode text,
  moo text,
  community text,
  latitude double precision,
  longitude double precision,
  coordinate_status text,
  review_required boolean,
  inside_tambon boolean,
  inside_community boolean,
  volunteer_pid bigint,
  volunteer_name text
)
language sql
stable
security definer
set search_path = ''
as $$
  with ctx as (
    select
      private.current_role() as role,
      private.current_community() as own_community,
      private.current_volunteer_pid() as volunteer_pid,
      private.current_moo() as own_moo
  )
  select
    h.id, h.house_no, h.hcode, h.moo, h.community,
    h.latitude, h.longitude, h.coordinate_status, h.review_required,
    h.inside_tambon, h.inside_community, h.volunteer_pid,
    coalesce(v.display_name, '') as volunteer_name
  from public.houses h
  left join public.volunteers v
    on v.source_pcucode = h.source_pcucode and v.source_pid = h.volunteer_pid
  where h.superseded_by is null and h.verification_status='verified_jhcis'
    and private.community_key(h.community) = private.community_key(p_community)
    and (
      (select role from ctx) = 'admin'
      or (
        (select role from ctx) = 'staff'
        and btrim(h.moo) = btrim((select own_moo from ctx))
      )
      or (
        (select role from ctx) = 'user'
        and h.volunteer_pid = (select volunteer_pid from ctx)
      )
    )
  order by h.house_no
$$;

create or replace function public.user_household_cards_v1855()
returns table (
  id uuid,
  house_no text,
  hcode text,
  moo text,
  community text,
  latitude double precision,
  longitude double precision,
  spatial_status text,
  member_count bigint,
  older_count bigint,
  ncd_due_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_pid bigint;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  v_role := private.current_role();
  v_pid := private.current_volunteer_pid();
  if v_role <> 'user' or v_pid is null then
    raise exception 'USER_SCOPE_REQUIRED';
  end if;

  return query
  select
    h.id,
    h.house_no,
    h.hcode,
    h.moo,
    h.community,
    h.latitude,
    h.longitude,
    case
      when h.latitude is null or h.longitude is null then 'missing'
      when h.inside_tambon = false then 'outside_tambon'
      when h.inside_community = false then 'outside_community'
      when h.review_required = true then 'review'
      when h.coordinate_status like 'resolved_%' then 'field_confirmed'
      else 'pinned'
    end::text as spatial_status,
    coalesce(x.member_count, 0)::bigint,
    coalesce(x.older_count, 0)::bigint,
    coalesce(x.ncd_due_count, 0)::bigint
  from public.houses h
  left join lateral (
    select
      count(*)::bigint as member_count,
      count(*) filter (where w.age_years >= 60)::bigint as older_count,
      count(*) filter (
        where w.ncd_target and not coalesce(w.screened_current_fy, false)
      )::bigint as ncd_due_count
    from public.health_person_worklist_active_v1841 w
    where w.source_pcucode = h.source_pcucode
      and w.hcode = h.hcode
  ) x on true
  where h.superseded_by is null and h.verification_status='verified_jhcis' and h.volunteer_pid = v_pid
  order by
    nullif(regexp_replace(coalesce(h.house_no,''), '[^0-9].*$', ''), '')::integer nulls last,
    h.house_no;
end;
$$;

create or replace function public.my_household_cards_v1860()
returns table (
  id uuid,
  hcode text,
  house_no text,
  moo text,
  community text,
  latitude double precision,
  longitude double precision,
  coordinate_source text,
  coordinate_status text,
  record_status text,
  review_required boolean,
  review_reason text,
  volunteer_pid bigint,
  house_id_11 text,
  entry_source text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_pid bigint;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  v_role := private.current_role();
  v_pid := private.current_volunteer_pid();
  if v_role not in ('user','staff') or v_pid is null then
    raise exception 'VHV_SCOPE_REQUIRED';
  end if;

  return query
  select h.id,h.hcode,h.house_no,h.moo,h.community,h.latitude,h.longitude,
         h.coordinate_source,h.coordinate_status,h.record_status,h.review_required,
         h.review_reason,h.volunteer_pid,h.house_id_11,h.entry_source
  from public.houses h
  where h.superseded_by is null and h.verification_status='verified_jhcis' and h.volunteer_pid=v_pid
  order by
    nullif(regexp_replace(coalesce(h.house_no,''), '[^0-9].*$', ''), '')::integer nulls last,
    h.house_no;
end;
$$;

create or replace function public.care_dashboard_v1861(p_scope text default 'self')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid:=auth.uid();
  v_role text;
  v_community text;
  v_pid bigint;
  v_scope text:=lower(btrim(coalesce(p_scope,'self')));
  v_result jsonb;
  v_hdc jsonb:=null;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select p.role,p.community,p.volunteer_pid
    into v_role,v_community,v_pid
  from public.profiles p
  where p.user_id=v_uid and p.active=true;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  if v_role='admin' then v_scope:='all';
  elsif v_role='user' then v_scope:='self';
  elsif v_role='staff' and v_scope not in ('self','community') then v_scope:='self';
  end if;

  if v_role='admin' then
    select s.value into v_hdc
    from public.app_settings s
    where s.key='care_reference_hdc'
    limit 1;
  end if;

  with scoped_houses as (
    select h.*
    from public.houses h
    where h.superseded_by is null and h.verification_status='verified_jhcis'
      and (v_role='admin'
      or (v_scope='self' and v_pid is not null and h.volunteer_pid=v_pid)
      or (v_role='staff' and v_scope='community'
          and private.community_key(h.community)=private.community_key(v_community)))
  ), scoped_people as (
    select w.*,p.is_student,p.is_disabled,p.service_population_eligible,
           p.adl_group_code,p.adl_assessed_on
    from public.health_person_worklist_active_v1847 w
    join public.health_persons p
      on p.source_pcucode=w.source_pcucode and p.source_pid=w.source_pid
    join scoped_houses h
      on h.source_pcucode=w.house_pcucode and h.hcode=w.hcode
  ), latest_2q as (
    select distinct on (s.source_pcucode,s.source_pid)
           s.source_pcucode,s.source_pid,s.mental_2q_status,s.mental_2q_result
    from public.health_ncd_screenings s
    join scoped_people p
      on p.source_pcucode=s.source_pcucode and p.source_pid=s.source_pid
     and p.service_population_eligible=true
    where coalesce(s.record_mode,'production')='production'
    order by s.source_pcucode,s.source_pid,s.screened_on desc,s.recorded_at desc
  ), hstat as (
    select count(*)::bigint houses,
           count(*) filter(where latitude is not null and longitude is not null)::bigint mapped_houses,
           count(*) filter(where latitude is null or longitude is null)::bigint missing_coordinates,
           count(*) filter(where review_required=true)::bigint review_houses
    from scoped_houses
  ), pstat as (
    select count(*)::bigint household_people,
           count(*) filter(where service_population_eligible)::bigint service_people,
           count(*) filter(where service_population_eligible and ncd_target)::bigint ncd_targets,
           count(*) filter(where service_population_eligible and ncd_target and coalesce(screened_current_fy,false))::bigint ncd_done,
           count(*) filter(where service_population_eligible and ncd_target and not coalesce(screened_current_fy,false))::bigint ncd_due,
           count(*) filter(where service_population_eligible and known_ncd)::bigint known_ncd,
           count(*) filter(where service_population_eligible and life_stage='เน€เธ”เนเธเธเธเธกเธงเธฑเธข')::bigint early_child,
           count(*) filter(where service_population_eligible and life_stage='เน€เธ”เนเธเธงเธฑเธขเน€เธฃเธตเธขเธ')::bigint school_age,
           count(*) filter(where service_population_eligible and life_stage='เธงเธฑเธขเธฃเธธเนเธเนเธฅเธฐเน€เธขเธฒเธงเธเธ')::bigint youth,
           count(*) filter(where service_population_eligible and life_stage='เธงเธฑเธขเธ—เธณเธเธฒเธ')::bigint working_age,
           count(*) filter(where service_population_eligible and life_stage='เธเธนเนเธชเธนเธเธญเธฒเธขเธธ')::bigint older_people,
           count(*) filter(where service_population_eligible and is_student)::bigint students,
           count(*) filter(where service_population_eligible and is_disabled)::bigint disabled_people,
           count(*) filter(where service_population_eligible and adl_group_code<>'')::bigint adl_assessed_people,
           count(*) filter(where service_population_eligible and adl_group_code='1B1280')::bigint social_people,
           count(*) filter(where service_population_eligible and adl_group_code='1B1281')::bigint homebound_people,
           count(*) filter(where service_population_eligible and adl_group_code='1B1282')::bigint bedridden_people,
           count(*) filter(where service_population_eligible and latest_severity in ('alert','urgent'))::bigint urgent_attention
    from scoped_people
  ), qstat as (
    select count(*) filter(where mental_2q_status='assessed')::bigint mental_2q_assessed,
           count(*) filter(where mental_2q_status='not_assessed')::bigint mental_2q_not_assessed,
           count(*) filter(where mental_2q_status='incomplete')::bigint mental_2q_incomplete,
           count(*) filter(where mental_2q_status='assessed' and mental_2q_result=true)::bigint mental_2q_positive
    from latest_2q
  )
  select jsonb_build_object(
    'version','1.8.61',
    'role',v_role,
    'scope',v_scope,
    'scope_label',case
      when v_role='admin' then 'เธ—เธธเธเธเธทเนเธเธ—เธตเนเธ•เธฒเธกเธชเธดเธ—เธเธดเนเธเธนเนเธ”เธนเนเธฅเธฃเธฐเธเธ'
      when v_role='staff' and v_scope='community' then 'เธเธธเธกเธเธ '||coalesce(v_community,'')
      else 'เธเนเธฒเธเนเธฅเธฐเธเธฃเธฐเธเธฒเธเธเธ—เธตเนเธเธฑเธเธฃเธฑเธเธเธดเธ”เธเธญเธ'
    end,
    'community',coalesce(v_community,''),
    'has_personal_scope',(v_pid is not null),
    'houses',coalesce(hstat.houses,0),
    'mapped_houses',coalesce(hstat.mapped_houses,0),
    'missing_coordinates',coalesce(hstat.missing_coordinates,0),
    'review_houses',coalesce(hstat.review_houses,0),
    'household_people',coalesce(pstat.household_people,0),
    'people',coalesce(pstat.service_people,0),
    'service_people',coalesce(pstat.service_people,0),
    'ncd_targets',coalesce(pstat.ncd_targets,0),
    'ncd_done',coalesce(pstat.ncd_done,0),
    'ncd_due',coalesce(pstat.ncd_due,0),
    'known_ncd',coalesce(pstat.known_ncd,0),
    'early_child',coalesce(pstat.early_child,0),
    'school_age',coalesce(pstat.school_age,0),
    'youth',coalesce(pstat.youth,0),
    'working_age',coalesce(pstat.working_age,0),
    'older_people',coalesce(pstat.older_people,0),
    'students',coalesce(pstat.students,0),
    'disabled_people',coalesce(pstat.disabled_people,0),
    'adl_assessed_people',coalesce(pstat.adl_assessed_people,0),
    'social_people',coalesce(pstat.social_people,0),
    'homebound_people',coalesce(pstat.homebound_people,0),
    'bedridden_people',coalesce(pstat.bedridden_people,0),
    'urgent_attention',coalesce(pstat.urgent_attention,0),
    'mental_2q_assessed',coalesce(qstat.mental_2q_assessed,0),
    'mental_2q_not_assessed',coalesce(qstat.mental_2q_not_assessed,0),
    'mental_2q_incomplete',coalesce(qstat.mental_2q_incomplete,0),
    'mental_2q_positive',coalesce(qstat.mental_2q_positive,0),
    'metric_sources',jsonb_build_object(
      'person_level','JHCIS read-only / J-Report operational definition',
      'service_population','typelive 1,3 + nation 99 + alive + non-00 village',
      'ncd','J-Report operational worklist; official HDC DM/HT denominators are separate',
      'adl','latest JHCIS f43specialpp 1B1280/1B1281/1B1282',
      'official_comparator','MoPH Open Data via hdc-app; aggregate only'
    ),
    'hdc_reference',case when v_role='admin' then v_hdc else null end
  ) into v_result
  from hstat cross join pstat cross join qstat;

  return v_result;
end;
$$;

create or replace function public.assignment_summary_v2033(
  p_scope text default 'self',
  p_owner_pid bigint default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();v_role text;v_community text;v_pid bigint;
  v_scope text:=lower(btrim(coalesce(p_scope,'self')));v_owner bigint:=p_owner_pid;v_result jsonb;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select role,community,volunteer_pid into v_role,v_community,v_pid
  from public.profiles where user_id=v_uid and active=true limit 1;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  if v_role='admin' then v_scope:='all';v_owner:=null;
  elsif v_role='user' then v_scope:='self';v_owner:=v_pid;
  elsif v_role='staff' then
    if v_scope='volunteer' then
      if v_owner is null or not exists(
        select 1 from public.profiles p join public.volunteers v on v.source_pid=p.volunteer_pid and v.active=true
        where p.active=true and p.role='user' and p.volunteer_pid=v_owner
          and private.community_key(p.community)=private.community_key(v_community)
      ) then raise exception 'VOLUNTEER_SCOPE_NOT_ALLOWED'; end if;
    elsif v_scope not in ('self','community') then v_scope:='self';v_owner:=v_pid;
    else v_owner:=case when v_scope='self' then v_pid else null end;
    end if;
  else raise exception 'ROLE_NOT_ALLOWED';
  end if;

  with active_vhv as materialized(
    select distinct v.source_pid from public.volunteers v where v.active=true
  ), active_ops as materialized(
    select distinct v.source_pid
    from public.volunteers v join public.profiles p on p.volunteer_pid=v.source_pid
    where v.active=true and p.active=true and p.role in ('user','staff')
  ), scoped_houses as materialized(
    select h.*,
      case when nullif(private.community_key(h.community),'') is null then 'unresolved'
           when h.volunteer_pid is null or av.source_pid is null or ao.source_pid is null then 'staff_fallback'
           else 'assigned' end assignment_status,
      case when nullif(private.community_key(h.community),'') is null then 'missing_community'
           when h.volunteer_pid is null then 'no_volunteer'
           when av.source_pid is null then 'inactive_volunteer'
           when ao.source_pid is null then 'no_active_user'
           else 'assigned' end assignment_reason
    from public.houses h
    left join active_vhv av on av.source_pid=h.volunteer_pid
    left join active_ops ao on ao.source_pid=h.volunteer_pid
    where h.superseded_by is null and h.verification_status='verified_jhcis'
      and (v_role='admin'
       or (v_scope in ('self','volunteer') and v_owner is not null and h.volunteer_pid=v_owner)
       or (v_role='staff' and v_scope='community' and private.community_key(h.community)=private.community_key(v_community)))
  ), people as materialized(
    select p.source_pcucode,p.source_pid,h.assignment_status,h.assignment_reason
    from public.health_persons p join scoped_houses h on h.source_pcucode=p.house_pcucode and h.hcode=p.hcode
    where p.active=true and coalesce(p.service_population_eligible,false)=true
  ), hstat as(
    select count(*)::bigint houses,count(*) filter(where assignment_status='assigned')::bigint assigned_houses,
      count(*) filter(where assignment_status='staff_fallback')::bigint fallback_houses,
      count(*) filter(where assignment_status='unresolved')::bigint unresolved_houses,
      count(*) filter(where assignment_reason='no_volunteer')::bigint no_volunteer_houses,
      count(*) filter(where assignment_reason='inactive_volunteer')::bigint inactive_volunteer_houses,
      count(*) filter(where assignment_reason='no_active_user')::bigint no_active_user_houses from scoped_houses
  ), pstat as(
    select count(*)::bigint people,count(*) filter(where assignment_status='assigned')::bigint assigned_people,
      count(*) filter(where assignment_status='staff_fallback')::bigint fallback_people,
      count(*) filter(where assignment_status='unresolved')::bigint unresolved_people,
      count(*) filter(where assignment_reason='no_volunteer')::bigint no_volunteer_people,
      count(*) filter(where assignment_reason='inactive_volunteer')::bigint inactive_volunteer_people,
      count(*) filter(where assignment_reason='no_active_user')::bigint no_active_user_people from people
  )
  select jsonb_build_object(
    'version','2.0.33','role',v_role,'scope',v_scope,'community',coalesce(v_community,''),'owner_pid',v_owner,
    'houses',h.houses,'assigned_houses',h.assigned_houses,'fallback_houses',h.fallback_houses,'unresolved_houses',h.unresolved_houses,
    'no_volunteer_houses',h.no_volunteer_houses,'inactive_volunteer_houses',h.inactive_volunteer_houses,'no_active_user_houses',h.no_active_user_houses,
    'people',p.people,'assigned_people',p.assigned_people,'fallback_people',p.fallback_people,'unresolved_people',p.unresolved_people,
    'no_volunteer_people',p.no_volunteer_people,'inactive_volunteer_people',p.inactive_volunteer_people,'no_active_user_people',p.no_active_user_people,
    'fallback_policy','staff_community','auto_reassign_volunteer_pid',false,
    'scope_label',case when v_role='admin' then 'เธ—เธธเธเธเธทเนเธเธ—เธตเน'
      when v_scope='community' then 'เธเธธเธกเธเธ '||coalesce(v_community,'')
      when v_scope='volunteer' then 'เธเธฒเธเธเธญเธ เธญเธชเธก. เธ—เธตเนเน€เธฅเธทเธญเธ'
      else 'เธเนเธฒเธเนเธฅเธฐเธเธฃเธฐเธเธฒเธเธเธ—เธตเนเธเธฑเธเธฃเธฑเธเธเธดเธ”เธเธญเธ' end
  ) into v_result from hstat h cross join pstat p;
  return v_result;
end;
$$;

create or replace function private.refresh_report_snapshots_v2031(p_reason text default 'manual')
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_generation uuid:=gen_random_uuid();
  v_started timestamptz:=clock_timestamp();
  v_rows bigint:=0;
  v_added bigint:=0;
  v_reason text:=left(coalesce(nullif(btrim(p_reason),''),'manual'),80);
begin
  if not pg_try_advisory_xact_lock(hashtext('osm_phc_report_snapshot_v2031')) then
    return jsonb_build_object('ok',false,'status','busy','version','2.0.31');
  end if;

  insert into public.report_snapshot_runs_v2031(id,status,reason,started_at)
  values(v_generation,'running',v_reason,v_started);
  update public.report_snapshot_state_v2031
  set status='running',last_reason=v_reason,last_error=''
  where singleton=true;

  begin
    -- Care dashboard: scan each base relation once and fan rows into all/community/volunteer scopes.
    with house_scoped as materialized (
      select s.scope_type,s.scope_key,h.latitude,h.longitude,h.review_required
      from public.houses h
      cross join lateral (values
        ('all'::text,'*'::text),
        ('community'::text,nullif(private.community_key(h.community),'')),
        ('volunteer'::text,h.volunteer_pid::text)
      ) s(scope_type,scope_key)
      where h.superseded_by is null and h.verification_status='verified_jhcis' and s.scope_key is not null
    ), hagg as (
      select scope_type,scope_key,count(*)::bigint houses,
        count(*) filter(where latitude is not null and longitude is not null)::bigint mapped_houses,
        count(*) filter(where latitude is null or longitude is null)::bigint missing_coordinates,
        count(*) filter(where review_required=true)::bigint review_houses
      from house_scoped group by scope_type,scope_key
    ), person_base as materialized (
      select w.source_pcucode,w.source_pid,w.life_stage,w.ncd_target,w.screened_current_fy,w.known_ncd,w.latest_severity,
        p.is_student,p.is_disabled,p.service_population_eligible,p.adl_group_code,
        h.community,h.volunteer_pid
      from public.health_person_worklist_active_v1847 w
      join public.health_persons p on p.source_pcucode=w.source_pcucode and p.source_pid=w.source_pid
      join public.houses h on h.source_pcucode=w.house_pcucode and h.hcode=w.hcode and h.superseded_by is null and h.verification_status='verified_jhcis'
    ), person_scoped as materialized (
      select s.scope_type,s.scope_key,p.*
      from person_base p
      cross join lateral (values
        ('all'::text,'*'::text),
        ('community'::text,nullif(private.community_key(p.community),'')),
        ('volunteer'::text,p.volunteer_pid::text)
      ) s(scope_type,scope_key)
      where s.scope_key is not null
    ), pagg as (
      select scope_type,scope_key,count(*)::bigint household_people,
        count(*) filter(where service_population_eligible)::bigint service_people,
        count(*) filter(where service_population_eligible and ncd_target)::bigint ncd_targets,
        count(*) filter(where service_population_eligible and ncd_target and coalesce(screened_current_fy,false))::bigint ncd_done,
        count(*) filter(where service_population_eligible and ncd_target and not coalesce(screened_current_fy,false))::bigint ncd_due,
        count(*) filter(where service_population_eligible and known_ncd)::bigint known_ncd,
        count(*) filter(where service_population_eligible and life_stage='เน€เธ”เนเธเธเธเธกเธงเธฑเธข')::bigint early_child,
        count(*) filter(where service_population_eligible and life_stage='เน€เธ”เนเธเธงเธฑเธขเน€เธฃเธตเธขเธ')::bigint school_age,
        count(*) filter(where service_population_eligible and life_stage='เธงเธฑเธขเธฃเธธเนเธเนเธฅเธฐเน€เธขเธฒเธงเธเธ')::bigint youth,
        count(*) filter(where service_population_eligible and life_stage='เธงเธฑเธขเธ—เธณเธเธฒเธ')::bigint working_age,
        count(*) filter(where service_population_eligible and life_stage='เธเธนเนเธชเธนเธเธญเธฒเธขเธธ')::bigint older_people,
        count(*) filter(where service_population_eligible and is_student)::bigint students,
        count(*) filter(where service_population_eligible and is_disabled)::bigint disabled_people,
        count(*) filter(where service_population_eligible and life_stage='เธเธนเนเธชเธนเธเธญเธฒเธขเธธ' and adl_group_code<>'')::bigint adl_assessed_people,
        count(*) filter(where service_population_eligible and life_stage='เธเธนเนเธชเธนเธเธญเธฒเธขเธธ' and adl_group_code='1B1280')::bigint social_people,
        count(*) filter(where service_population_eligible and life_stage='เธเธนเนเธชเธนเธเธญเธฒเธขเธธ' and adl_group_code='1B1281')::bigint homebound_people,
        count(*) filter(where service_population_eligible and life_stage='เธเธนเนเธชเธนเธเธญเธฒเธขเธธ' and adl_group_code='1B1282')::bigint bedridden_people,
        count(*) filter(where service_population_eligible and latest_severity in ('alert','urgent'))::bigint urgent_attention
      from person_scoped group by scope_type,scope_key
    ), latest_2q as materialized (
      select distinct on (s.source_pcucode,s.source_pid)
        s.source_pcucode,s.source_pid,s.mental_2q_status,s.mental_2q_result
      from public.health_ncd_screenings s
      join person_base p on p.source_pcucode=s.source_pcucode and p.source_pid=s.source_pid
      where p.service_population_eligible=true and coalesce(s.record_mode,'production')='production'
      order by s.source_pcucode,s.source_pid,s.screened_on desc,s.recorded_at desc
    ), qagg as (
      select ps.scope_type,ps.scope_key,
        count(*) filter(where q.mental_2q_status='assessed')::bigint mental_2q_assessed,
        count(*) filter(where q.mental_2q_status='not_assessed')::bigint mental_2q_not_assessed,
        count(*) filter(where q.mental_2q_status='incomplete')::bigint mental_2q_incomplete,
        count(*) filter(where q.mental_2q_status='assessed' and q.mental_2q_result=true)::bigint mental_2q_positive
      from person_scoped ps join latest_2q q on q.source_pcucode=ps.source_pcucode and q.source_pid=ps.source_pid
      group by ps.scope_type,ps.scope_key
    ), scopes as (
      select scope_type,scope_key from hagg union select scope_type,scope_key from pagg union select scope_type,scope_key from qagg
    )
    insert into public.report_snapshot_cache_v2031(generation,report_key,scope_type,scope_key,payload,generated_at)
    select v_generation,'care',s.scope_type,s.scope_key,jsonb_build_object(
      'houses',coalesce(h.houses,0),'mapped_houses',coalesce(h.mapped_houses,0),
      'missing_coordinates',coalesce(h.missing_coordinates,0),'review_houses',coalesce(h.review_houses,0),
      'household_people',coalesce(p.household_people,0),'people',coalesce(p.service_people,0),'service_people',coalesce(p.service_people,0),
      'ncd_targets',coalesce(p.ncd_targets,0),'ncd_done',coalesce(p.ncd_done,0),'ncd_due',coalesce(p.ncd_due,0),'known_ncd',coalesce(p.known_ncd,0),
      'early_child',coalesce(p.early_child,0),'school_age',coalesce(p.school_age,0),'youth',coalesce(p.youth,0),
      'working_age',coalesce(p.working_age,0),'older_people',coalesce(p.older_people,0),'students',coalesce(p.students,0),
      'disabled_people',coalesce(p.disabled_people,0),'adl_assessed_people',coalesce(p.adl_assessed_people,0),
      'social_people',coalesce(p.social_people,0),'homebound_people',coalesce(p.homebound_people,0),'bedridden_people',coalesce(p.bedridden_people,0),
      'urgent_attention',coalesce(p.urgent_attention,0),'mental_2q_assessed',coalesce(q.mental_2q_assessed,0),
      'mental_2q_not_assessed',coalesce(q.mental_2q_not_assessed,0),'mental_2q_incomplete',coalesce(q.mental_2q_incomplete,0),
      'mental_2q_positive',coalesce(q.mental_2q_positive,0),
      'metric_sources',jsonb_build_object(
        'person_level','JHCIS read-only / J-Report operational definition',
        'service_population','typelive 1,3 + nation 99 + alive + non-00 village',
        'ncd','J-Report operational worklist; official HDC DM/HT denominators are separate',
        'adl','latest JHCIS f43specialpp 1B1280/1B1281/1B1282',
        'official_comparator','MoPH Open Data via hdc-app; aggregate only'
      )
    ),clock_timestamp()
    from scopes s
    left join hagg h using(scope_type,scope_key)
    left join pagg p using(scope_type,scope_key)
    left join qagg q using(scope_type,scope_key);
    get diagnostics v_added=row_count; v_rows:=v_rows+v_added;

    -- Field-work dashboard: materialize once, then aggregate the same rows for each permitted scope.
    with work_scoped as materialized (
      select s.scope_type,s.scope_key,w.*
      from public.field_work_items_v200 w
      cross join lateral (values
        ('all'::text,'*'::text),
        ('community'::text,nullif(private.community_key(w.community),'')),
        ('volunteer'::text,w.volunteer_pid::text)
      ) s(scope_type,scope_key)
      where s.scope_key is not null
    ), base_summary as (
      select scope_type,scope_key,count(*)::bigint total,
        count(*) filter(where status='complete')::bigint complete,
        count(*) filter(where status='partial')::bigint partial,
        count(*) filter(where status='due')::bigint due,
        count(*) filter(where priority='red')::bigint red,
        count(*) filter(where priority='orange')::bigint orange
      from work_scoped group by scope_type,scope_key
    ), task_rows as (
      select scope_type,scope_key,task_type,max(task_label) task_label,count(*)::bigint target,
        count(*) filter(where status='complete')::bigint complete,
        count(*) filter(where status='partial')::bigint partial,
        count(*) filter(where status='due')::bigint due
      from work_scoped group by scope_type,scope_key,task_type
    ), task_json as (
      select scope_type,scope_key,jsonb_agg(jsonb_build_object(
        'task_type',task_type,'task_label',task_label,'target',target,'complete',complete,'partial',partial,'due',due,
        'percent',case when target>0 then round(complete*100.0/target,1) else 0 end
      ) order by task_type) value from task_rows group by scope_type,scope_key
    ), person_keys as (
      select distinct scope_type,scope_key,source_pcucode,source_pid from work_scoped
    ), follow_stat as (
      select p.scope_type,p.scope_key,
        count(*) filter(where f.status in ('open','in_progress'))::bigint open_count,
        count(*) filter(where f.status='done')::bigint done_count,
        count(*) filter(where f.status in ('open','in_progress') and f.priority='red')::bigint red_count,
        count(*) filter(where f.status in ('open','in_progress') and f.priority='orange')::bigint orange_count
      from person_keys p join public.screening_followups f on f.source_pcucode=p.source_pcucode and f.source_pid=p.source_pid
      group by p.scope_type,p.scope_key
    ), volunteer_rows as (
      select s.scope_type,s.scope_key,s.volunteer_pid,max(v.display_name) display_name,max(s.community) community,
        count(*)::bigint target,count(*) filter(where s.status='complete')::bigint complete,
        count(*) filter(where s.status='partial')::bigint partial,count(*) filter(where s.status='due')::bigint due
      from work_scoped s left join public.volunteers v on v.source_pid=s.volunteer_pid
      where s.volunteer_pid is not null group by s.scope_type,s.scope_key,s.volunteer_pid
    ), volunteer_json as (
      select scope_type,scope_key,jsonb_agg(jsonb_build_object(
        'volunteer_pid',volunteer_pid,'display_name',coalesce(display_name,'เนเธกเนเธฃเธฐเธเธธ'),'community',community,
        'target',target,'complete',complete,'partial',partial,'due',due,
        'percent',case when target>0 then round(complete*100.0/target,1) else 0 end
      ) order by (case when target>0 then complete*100.0/target else 0 end),display_name) value
      from volunteer_rows group by scope_type,scope_key
    ), community_rows as (
      select scope_type,scope_key,community,count(*)::bigint target,
        count(*) filter(where status='complete')::bigint complete,count(*) filter(where status='partial')::bigint partial,
        count(*) filter(where status='due')::bigint due,count(distinct volunteer_pid) filter(where volunteer_pid is not null)::bigint volunteers
      from work_scoped group by scope_type,scope_key,community
    ), community_json as (
      select scope_type,scope_key,jsonb_agg(jsonb_build_object(
        'community',community,'target',target,'complete',complete,'partial',partial,'due',due,'volunteers',volunteers,
        'percent',case when target>0 then round(complete*100.0/target,1) else 0 end
      ) order by (case when target>0 then complete*100.0/target else 0 end),community) value
      from community_rows group by scope_type,scope_key
    )
    insert into public.report_snapshot_cache_v2031(generation,report_key,scope_type,scope_key,payload,generated_at)
    select v_generation,'field',b.scope_type,b.scope_key,jsonb_build_object(
      'period_start',private.field_period_start_v200(),'period_mode',private.field_period_mode_v200(),
      'target_tasks',coalesce(b.total,0),'complete_tasks',coalesce(b.complete,0),'partial_tasks',coalesce(b.partial,0),'due_tasks',coalesce(b.due,0),
      'coverage_percent',case when coalesce(b.total,0)>0 then round(b.complete*100.0/b.total,1) else 0 end,
      'red_tasks',coalesce(b.red,0),'orange_tasks',coalesce(b.orange,0),
      'followup_open',coalesce(f.open_count,0),'followup_done',coalesce(f.done_count,0),
      'followup_red',coalesce(f.red_count,0),'followup_orange',coalesce(f.orange_count,0),
      'tasks',coalesce(t.value,'[]'::jsonb),'volunteers',coalesce(v.value,'[]'::jsonb),'communities',coalesce(c.value,'[]'::jsonb),
      'metric_note','เน€เธเธญเธฃเนเน€เธเนเธเธ•เนเธฃเธงเธกเน€เธเนเธ Operational Task Completion; เนเธกเนเนเธเนเนเธ—เธ KPI HDC เธ—เธฒเธเธเธฒเธฃ เนเธฅเธฐเธฃเธฒเธขเธเธฒเธฃเธ•เธดเธ”เธ•เธฒเธกเนเธกเนเธ–เธนเธเธเธณเธกเธฒเธซเธฑเธ Coverage'
    ),clock_timestamp()
    from base_summary b
    left join task_json t using(scope_type,scope_key)
    left join follow_stat f using(scope_type,scope_key)
    left join volunteer_json v using(scope_type,scope_key)
    left join community_json c using(scope_type,scope_key);
    get diagnostics v_added=row_count; v_rows:=v_rows+v_added;

    update public.report_snapshot_runs_v2031 set status='success',finished_at=clock_timestamp(),
      duration_ms=round(extract(epoch from (clock_timestamp()-v_started))*1000),cache_rows=v_rows
    where id=v_generation;
    update public.report_snapshot_state_v2031 set current_generation=v_generation,generated_at=clock_timestamp(),
      status='ready',last_reason=v_reason,last_error='' where singleton=true;

    -- Keep four completed generations so readers always have a valid previous generation.
    delete from public.report_snapshot_runs_v2031 r
    where r.status<>'running' and r.id not in (
      select id from public.report_snapshot_runs_v2031 where status='success' order by finished_at desc nulls last limit 4
    ) and coalesce(r.finished_at,r.started_at)<now()-interval '7 days';

    return jsonb_build_object('ok',true,'status','ready','generation',v_generation,'cache_rows',v_rows,
      'duration_ms',round(extract(epoch from (clock_timestamp()-v_started))*1000),'generated_at',clock_timestamp(),'version','2.0.31');
  exception when others then
    update public.report_snapshot_runs_v2031 set status='failed',finished_at=clock_timestamp(),
      duration_ms=round(extract(epoch from (clock_timestamp()-v_started))*1000),error_message=left(sqlerrm,500)
    where id=v_generation;
    update public.report_snapshot_state_v2031 set status=case when current_generation is null then 'failed' else 'ready' end,
      last_reason=v_reason,last_error=left(sqlerrm,500) where singleton=true;
    return jsonb_build_object('ok',false,'status','failed','error',left(sqlerrm,500),'version','2.0.31');
  end;
end;
$$;

create or replace view public.community_report_summary
with (security_invoker=true) as
select h.community,max(h.moo) as moo,count(*)::bigint as houses,
  count(*) filter(where h.volunteer_pid is not null)::bigint as assigned_houses,
  count(*) filter(where h.review_required)::bigint as review_houses,
  count(*) filter(where h.inside_tambon=false)::bigint as outside_tambon,
  count(*) filter(where h.latitude is null or h.longitude is null)::bigint as missing_coordinates,
  count(distinct h.volunteer_pid) filter(where h.volunteer_pid is not null)::bigint as volunteers_with_work
from public.houses h where h.superseded_by is null and h.verification_status='verified_jhcis' group by h.community;

grant select on public.community_report_summary to authenticated;

create or replace view public.volunteer_workload
with (security_invoker=true) as
select v.source_pid,v.display_name,v.community,v.moo,v.anchor_status,
  count(h.id)::bigint as house_count,
  count(h.id) filter(where h.review_required)::bigint as review_count,
  count(h.id) filter(where h.community=v.community)::bigint as in_community_count,
  count(h.id) filter(where h.community<>v.community)::bigint as cross_community_count
from public.volunteers v
left join public.houses h on h.volunteer_pid=v.source_pid and h.superseded_by is null and h.verification_status='verified_jhcis'
group by v.source_pid,v.display_name,v.community,v.moo,v.anchor_status;

grant select on public.volunteer_workload to authenticated;

insert into public.app_settings(key,value)
values('jhcis_authoritative_verification_v2050',jsonb_build_object(
  'version','2.0.50','source_of_truth','jhcisdb',
  'house_registry','jhcisdb.house','house_assignment','jhcisdb.house.pidvola',
  'normal_cloud_house_state','verified_jhcis',
  'cloud_field_house_initial_state','pending_jhcis_create',
  'person_match','CID13 exact in Local memory across all JHCIS types',
  'type_2_4_policy','pending_jhcis_update; never create duplicate',
  'admin_action','edit/create in JHCIS manually then sync',
  'jhcis_write_back',false,'physical_delete',false
)) on conflict(key) do update set value=excluded.value,updated_at=now();

notify pgrst,'reload schema';

commit;
