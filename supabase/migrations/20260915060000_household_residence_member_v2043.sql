-- OSM-PHC Cloud v2.0.43
-- Household population workflow: distinguish field residence from house registration,
-- keep registered members visible, and allow minimal new-member requests without creating duplicates.
-- JHCIS remains read-only.

begin;

-- ---------------------------------------------------------------------------
-- 1) Residence / registration are separate concepts.
-- ---------------------------------------------------------------------------
alter table public.health_person_residence_status
  add column if not exists registration_status text not null default 'registered_here';

alter table public.health_person_residence_status
  drop constraint if exists health_person_residence_status_field_status_check;

update public.health_person_residence_status
set field_status='living_elsewhere'
where field_status='absent';

alter table public.health_person_residence_status
  add constraint health_person_residence_status_field_status_check
  check (field_status in ('unverified','present','contact_unreachable','living_elsewhere','uncertain'));

alter table public.health_person_residence_status
  drop constraint if exists health_person_residence_status_registration_status_check;

alter table public.health_person_residence_status
  add constraint health_person_residence_status_registration_status_check
  check (registration_status in ('registered_here','transfer_reported','transferred_confirmed'));

alter table public.health_person_residence_events
  drop constraint if exists health_person_residence_events_action_check;

alter table public.health_person_residence_events
  add constraint health_person_residence_events_action_check
  check (action in (
    'report_present','report_absent','report_contact_unreachable','report_living_elsewhere','report_transfer_reported','report_uncertain',
    'confirm_include','confirm_exclude'
  ));

create or replace function public.report_person_residence_v1841(
  p_source_pcucode text,
  p_source_pid bigint,
  p_status text,
  p_note text default ''
) returns jsonb
language plpgsql security definer
set search_path=public,private,extensions
as $$
declare
  v_uid uuid:=auth.uid();
  v_profile public.profiles%rowtype;
  v_person public.health_persons%rowtype;
  v_old public.health_person_residence_status%rowtype;
  v_input text:=lower(btrim(coalesce(p_status,'')));
  v_field text;
  v_registration text;
  v_review text;
  v_action text;
  v_target boolean:=true;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_profile from public.profiles where user_id=v_uid and active=true;
  if not found or v_profile.role not in ('user','staff','admin') then raise exception 'PROFILE_NOT_ACTIVE'; end if;
  if v_input not in ('present','contact_unreachable','living_elsewhere','transfer_reported','uncertain') then
    raise exception 'INVALID_RESIDENCE_STATUS';
  end if;

  select * into v_person from public.health_persons
  where source_pcucode=p_source_pcucode and source_pid=p_source_pid and active=true;
  if not found then raise exception 'PERSON_NOT_FOUND'; end if;
  if not private.health_can_access_house(v_person.house_pcucode,v_person.hcode) then raise exception 'PERSON_OUT_OF_SCOPE'; end if;

  select * into v_old from public.health_person_residence_status
  where source_pcucode=v_person.source_pcucode and source_pid=v_person.source_pid;
  if found then v_target:=v_old.service_target_active; end if;

  v_field:=case when v_input='transfer_reported' then 'living_elsewhere' else v_input end;
  v_registration:=case
    when v_input='present' then 'registered_here'
    when v_input='living_elsewhere' then 'registered_here'
    when v_input='transfer_reported' then 'transfer_reported'
    else coalesce(v_old.registration_status,'registered_here') end;
  -- Present/contact-unreachable do not remove a person from care and do not burden the review queue.
  -- Potential relocation/transfer remains pending until Admin decides.
  v_review:=case when v_input in ('living_elsewhere','transfer_reported','uncertain') then 'pending' else 'none' end;
  v_action:=case v_input
    when 'present' then 'report_present'
    when 'contact_unreachable' then 'report_contact_unreachable'
    when 'living_elsewhere' then 'report_living_elsewhere'
    when 'transfer_reported' then 'report_transfer_reported'
    else 'report_uncertain' end;

  insert into public.health_person_residence_status(
    source_pcucode,source_pid,house_pcucode,hcode,source_typelive,
    field_status,registration_status,review_state,service_target_active,
    report_note,reported_by,reported_at,decision_note,decided_by,decided_at,updated_at
  ) values (
    v_person.source_pcucode,v_person.source_pid,v_person.house_pcucode,v_person.hcode,v_person.jhcis_typelive,
    v_field,v_registration,v_review,v_target,
    left(btrim(coalesce(p_note,'')),500),v_uid,now(),'',null,null,now()
  )
  on conflict (source_pcucode,source_pid) do update set
    house_pcucode=excluded.house_pcucode,hcode=excluded.hcode,source_typelive=excluded.source_typelive,
    field_status=excluded.field_status,registration_status=excluded.registration_status,
    review_state=excluded.review_state,report_note=excluded.report_note,reported_by=excluded.reported_by,
    reported_at=excluded.reported_at,decision_note='',decided_by=null,decided_at=null,updated_at=now();

  insert into public.health_person_residence_events(
    source_pcucode,source_pid,house_pcucode,hcode,action,field_status,
    service_target_active,note,actor_id,actor_role
  ) values (
    v_person.source_pcucode,v_person.source_pid,v_person.house_pcucode,v_person.hcode,v_action,v_field,
    v_target,left(btrim(coalesce(p_note,'')),500),v_uid,v_profile.role
  );

  return jsonb_build_object('ok',true,'field_status',v_field,'registration_status',v_registration,
    'review_state',v_review,'service_target_active',v_target);
end;
$$;

create or replace function public.review_person_residence_v1841(
  p_source_pcucode text,
  p_source_pid bigint,
  p_decision text,
  p_note text default ''
) returns jsonb
language plpgsql security definer
set search_path=public,private,extensions
as $$
declare
  v_uid uuid:=auth.uid();
  v_profile public.profiles%rowtype;
  v_state public.health_person_residence_status%rowtype;
  v_house public.houses%rowtype;
  v_decision text:=lower(btrim(coalesce(p_decision,'')));
  v_active boolean;
  v_registration text;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_profile from public.profiles where user_id=v_uid and active=true;
  if not found or v_profile.role not in ('admin','staff') then raise exception 'STAFF_OR_ADMIN_REQUIRED'; end if;
  if v_decision not in ('include','exclude') then raise exception 'INVALID_DECISION'; end if;
  select * into v_state from public.health_person_residence_status
  where source_pcucode=p_source_pcucode and source_pid=p_source_pid for update;
  if not found then raise exception 'RESIDENCE_REPORT_NOT_FOUND'; end if;
  select * into v_house from public.houses
  where source_pcucode=v_state.house_pcucode and hcode=v_state.hcode limit 1;
  if not found then raise exception 'HOUSE_NOT_FOUND'; end if;
  if v_profile.role='staff' and (nullif(btrim(coalesce(v_profile.community,'')),'') is null
     or btrim(coalesce(v_house.community,''))<>btrim(v_profile.community)) then
    raise exception 'HOUSE_OUT_OF_SCOPE';
  end if;

  v_active:=v_decision='include';
  v_registration:=case
    when v_decision='exclude' and v_state.registration_status='transfer_reported' then 'transferred_confirmed'
    when v_decision='include' and v_state.registration_status='transfer_reported' then 'registered_here'
    else v_state.registration_status end;

  update public.health_person_residence_status set
    review_state='confirmed',service_target_active=v_active,registration_status=v_registration,
    decision_note=left(btrim(coalesce(p_note,'')),500),decided_by=v_uid,decided_at=now(),updated_at=now()
  where source_pcucode=p_source_pcucode and source_pid=p_source_pid;

  insert into public.health_person_residence_events(
    source_pcucode,source_pid,house_pcucode,hcode,action,field_status,
    service_target_active,note,actor_id,actor_role
  ) values (
    v_state.source_pcucode,v_state.source_pid,v_state.house_pcucode,v_state.hcode,
    case when v_active then 'confirm_include' else 'confirm_exclude' end,
    v_state.field_status,v_active,left(btrim(coalesce(p_note,'')),500),v_uid,v_profile.role
  );
  return jsonb_build_object('ok',true,'review_state','confirmed','service_target_active',v_active,
    'registration_status',v_registration);
end;
$$;

create or replace function public.person_residence_review_queue_v2043(
  p_community text default null,
  p_state text default 'pending'
) returns table(
  source_pcucode text,source_pid bigint,display_name text,gender text,age_years integer,
  house_no text,moo text,community text,jhcis_typelive smallint,field_status text,registration_status text,
  review_state text,service_target_active boolean,report_note text,reported_at timestamptz
)
language plpgsql security definer
set search_path=public,private,extensions
as $$
declare
  v_uid uuid:=auth.uid();
  v_profile public.profiles%rowtype;
  v_state text:=lower(btrim(coalesce(p_state,'pending')));
  v_community text;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_profile from public.profiles where user_id=v_uid and active=true;
  if not found or v_profile.role not in ('admin','staff') then raise exception 'STAFF_OR_ADMIN_REQUIRED'; end if;
  v_community:=case when v_profile.role='staff' then nullif(btrim(coalesce(v_profile.community,'')),'')
                    else nullif(btrim(coalesce(p_community,'')),'') end;
  if v_profile.role='staff' and v_community is null then raise exception 'COMMUNITY_REQUIRED'; end if;
  return query
  select p.source_pcucode,p.source_pid,p.display_name,p.gender,
         case when p.birth_date is null then null else extract(year from age(current_date,p.birth_date))::integer end,
         h.house_no,h.moo,h.community,p.jhcis_typelive,s.field_status,s.registration_status,s.review_state,
         s.service_target_active,s.report_note,s.reported_at
  from public.health_person_residence_status s
  join public.health_persons p on p.source_pcucode=s.source_pcucode and p.source_pid=s.source_pid
  join public.houses h on h.source_pcucode=p.house_pcucode and h.hcode=p.hcode
  where (v_community is null or btrim(h.community)=v_community)
    and (v_state='all' or s.review_state=v_state)
  order by case when s.review_state='pending' then 0 else 1 end,s.reported_at desc,p.display_name;
end;
$$;

-- Household detail uses the full registry worklist for member display, not only active service targets.
-- This prevents a registered person disappearing from the household merely because field service targeting changed.
create or replace function public.community_household_detail_v2043(p_house_id uuid)
returns jsonb
language plpgsql security definer
set search_path=public,private,extensions
as $$
declare
  v_base jsonb;
  v_house_pcucode text;
  v_hcode text;
  v_members jsonb:='[]'::jsonb;
  v_summary jsonb:='{}'::jsonb;
begin
  v_base:=public.community_household_detail_v1831(p_house_id);
  if coalesce((v_base->>'health_access')::boolean,false)=false then return v_base; end if;
  select h.source_pcucode,h.hcode into v_house_pcucode,v_hcode
  from public.houses h where h.id=p_house_id;
  if v_house_pcucode is null or v_hcode is null then raise exception 'HOUSE_NOT_FOUND'; end if;

  select jsonb_build_object(
    'members',count(*) filter(where coalesce(rs.service_target_active,true)),
    'registered_members',count(*),
    'older_people',count(*) filter(where w.age_years>=60 and coalesce(rs.service_target_active,true)),
    'age35plus',count(*) filter(where w.age_years>=35 and coalesce(rs.service_target_active,true)),
    'ncd_targets',count(*) filter(where w.ncd_target and coalesce(rs.service_target_active,true)),
    'ncd_due',count(*) filter(where w.ncd_target and not coalesce(w.screened_current_fy,false) and coalesce(rs.service_target_active,true)),
    'known_ncd',count(*) filter(where w.known_ncd and coalesce(rs.service_target_active,true)),
    'latest_screened_on',max(w.latest_screened_on) filter(where coalesce(rs.service_target_active,true))
  ) into v_summary
  from public.health_person_worklist w
  left join public.health_person_residence_status rs
    on rs.source_pcucode=w.source_pcucode and rs.source_pid=w.source_pid
  where w.source_pcucode=v_house_pcucode and w.hcode=v_hcode;

  select coalesce(jsonb_agg(jsonb_build_object(
    'source_pcucode',w.source_pcucode,'source_pid',w.source_pid,'display_name',w.display_name,
    'gender',w.gender,'age_years',w.age_years,'life_stage',w.life_stage,'known_ncd',w.known_ncd,
    'ncd_target',w.ncd_target,'screened_current_fy',w.screened_current_fy,
    'latest_screened_on',w.latest_screened_on,'latest_ncd_status',w.latest_ncd_status,
    'latest_severity',w.latest_severity,'jhcis_typelive',p.jhcis_typelive,
    'residence_status',coalesce(rs.field_status,'unverified'),
    'registration_status',coalesce(rs.registration_status,'registered_here'),
    'residence_review_state',coalesce(rs.review_state,'none'),
    'service_target_active',coalesce(rs.service_target_active,true),
    'task_label',case
      when not coalesce(rs.service_target_active,true) then 'เธขเธฑเธเธญเธขเธนเนเนเธเธ—เธฐเน€เธเธตเธขเธเธเนเธฒเธ เนเธ•เนเนเธกเนเธเธฑเธเน€เธเนเธเน€เธเนเธฒเธซเธกเธฒเธขเธเธฒเธเน€เธเธดเธเธฃเธธเธเธ•เธฒเธกเธเธฅเธ•เธฃเธงเธเธชเธญเธ'
      when w.ncd_target and not coalesce(w.screened_current_fy,false) then 'NCD เธขเธฑเธเธกเธตเธเธฒเธเธเธฑเธ”เธเธฃเธญเธเธ•เธฒเธกเธฃเธฒเธขเธเธฒเธฃเธฃเธฐเธเธ'
      when w.known_ncd then 'เธกเธต DM/HT เน€เธ”เธดเธกเนเธเธเนเธญเธกเธนเธฅเธฃเธฐเธเธ'
      else 'เนเธกเนเธกเธตเธเธฒเธ NCD เธเนเธฒเธเธ—เธตเนเธฃเธฐเธเธเธฃเธฐเธเธธ' end,
    'mental_2q_status',q.mental_2q_status,'mental_2q_result',q.mental_2q_result
  ) order by w.age_years desc nulls last,w.display_name),'[]'::jsonb) into v_members
  from public.health_person_worklist w
  join public.health_persons p on p.source_pcucode=w.source_pcucode and p.source_pid=w.source_pid
  left join public.health_person_residence_status rs
    on rs.source_pcucode=w.source_pcucode and rs.source_pid=w.source_pid
  left join lateral (
    select s.mental_2q_status,s.mental_2q_result
    from public.health_ncd_screenings s
    where s.source_pcucode=w.source_pcucode and s.source_pid=w.source_pid and s.record_mode='production'
    order by s.screened_on desc,s.recorded_at desc limit 1
  ) q on true
  where w.source_pcucode=v_house_pcucode and w.hcode=v_hcode;

  v_base:=jsonb_set(v_base,'{summary}',v_summary,true);
  v_base:=jsonb_set(v_base,'{members}',v_members,true);
  return v_base;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2) Minimal new-member request. Structured name fields are required at RPC level.
-- Existing CID in health_persons becomes a review/link request instead of an error.
-- ---------------------------------------------------------------------------
create or replace function public.submit_household_member_request_v2043(
  p_house_id uuid,p_citizen_id text,p_first_name text,p_last_name text,p_birth_date date
) returns jsonb
language plpgsql security definer
set search_path=''
as $$
declare
  v_cid text:=regexp_replace(coalesce(p_citizen_id,''),'\s','','g');
  v_first text:=regexp_replace(btrim(coalesce(p_first_name,'')),'\s+',' ','g');
  v_last text:=regexp_replace(btrim(coalesce(p_last_name,'')),'\s+',' ','g');
  v_name text;
  v_hash text;
  v_id uuid;
  v_house public.houses%rowtype;
  v_existing bigint;
  v_person_exists boolean:=false;
begin
  if auth.uid() is null or private.current_role() not in ('user','staff','admin') then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_house from public.houses where id=p_house_id;
  if not found then raise exception 'HOUSE_NOT_FOUND'; end if;
  if not private.health_can_access_house(v_house.source_pcucode,v_house.hcode) then raise exception 'HOUSE_OUT_OF_SCOPE'; end if;
  if not private.thai_cid_valid_v190(v_cid) then raise exception 'INVALID_THAI_CITIZEN_ID'; end if;
  if char_length(v_first)<1 then raise exception 'FIRST_NAME_REQUIRED'; end if;
  if char_length(v_last)<1 then raise exception 'LAST_NAME_REQUIRED'; end if;
  if char_length(v_first)>80 or char_length(v_last)>100 then raise exception 'NAME_TOO_LONG'; end if;
  if p_birth_date is null or p_birth_date>current_date or p_birth_date<current_date-interval '120 years' then raise exception 'INVALID_BIRTH_DATE'; end if;
  v_name:=v_first||' '||v_last;
  v_hash:=private.cid_hash_v190(v_cid);

  select count(*) into v_existing from public.household_member_requests r
  where r.citizen_id_hash=v_hash and r.status in ('pending','needs_correction');
  if v_existing>0 then raise exception 'DUPLICATE_MEMBER_REQUEST'; end if;

  v_person_exists:=exists(select 1 from public.health_persons p where p.citizen_id_hash=v_hash and p.active=true);

  insert into public.household_member_requests(
    house_id,submitted_by,citizen_id_cipher,citizen_id_hash,citizen_id_last4,full_name,birth_date
  ) values (
    p_house_id,auth.uid(),private.encrypt_text_v190(v_cid),v_hash,right(v_cid,4),v_name,p_birth_date
  ) returning id into v_id;

  perform private.emit_admin_notification_v190(
    'member_request.created','warning','OSM-PHC: เธกเธตเธเธณเธเธญเน€เธเธดเนเธกเธชเธกเธฒเธเธดเธเนเธซเธกเน',
    case when v_person_exists then 'เธเธเธเนเธญเธกเธนเธฅเธเธธเธเธเธฅเน€เธ”เธดเธกเธ—เธตเนเธญเธฒเธเธ•เธฃเธเธเธฑเธ เธเธฃเธธเธ“เธฒเธ•เธฃเธงเธเธชเธญเธเนเธฅเธฐเน€เธเธทเนเธญเธก PID เนเธเธฃเธฐเธเธ'
         else 'เธกเธตเธเธณเธเธญเน€เธเธดเนเธกเธชเธกเธฒเธเธดเธเธเนเธฒเธเนเธซเธกเน 1 เธฃเธฒเธข เธเธฃเธธเธ“เธฒเธ•เธฃเธงเธเธชเธญเธเนเธเธฃเธฐเธเธ' end,
    '?panel=admin-member-requests',
    jsonb_build_object('request_id',v_id,'community',v_house.community,'existing_person_found',v_person_exists),true
  );
  insert into public.health_audit_log(operator_id,action,entity,entity_id,source_pcucode,hcode,severity,details)
  values(auth.uid(),'CREATE','household_member_request',v_id::text,v_house.source_pcucode,v_house.hcode,'pending',
    jsonb_build_object('house_id',p_house_id,'cid_last4',right(v_cid,4),'existing_person_found',v_person_exists));

  return jsonb_build_object('ok',true,'id',v_id,'status','pending',
    'masked_citizen_id','โ€ขโ€ขโ€ขโ€ขโ€ขโ€ขโ€ขโ€ขโ€ข'||right(v_cid,4),'existing_person_found',v_person_exists);
end;
$$;

create or replace function public.household_member_requests_v2043(p_house_id uuid)
returns table(
  id uuid,full_name text,birth_date date,masked_citizen_id text,linked_person_id bigint,
  display_identifier text,status text,review_note text,linked boolean,created_at timestamptz,updated_at timestamptz
)
language plpgsql stable security definer
set search_path=''
as $$
begin
  if auth.uid() is null or not private.can_access_house_id_v190(p_house_id) then raise exception 'HOUSE_OUT_OF_SCOPE'; end if;
  return query select r.id,r.full_name,r.birth_date,'โ€ขโ€ขโ€ขโ€ขโ€ขโ€ขโ€ขโ€ขโ€ข'||r.citizen_id_last4,r.linked_person_id,
    case when r.linked_person_id is not null then 'PID '||r.linked_person_id::text else 'โ€ขโ€ขโ€ขโ€ขโ€ขโ€ขโ€ขโ€ขโ€ข'||r.citizen_id_last4 end,
    r.status,case when r.status='needs_correction' then r.review_note else '' end,
    r.linked_person_id is not null,r.created_at,r.updated_at
  from public.household_member_requests r where r.house_id=p_house_id order by r.created_at desc;
end;
$$;

revoke all on function public.report_person_residence_v1841(text,bigint,text,text) from public,anon;

revoke all on function public.review_person_residence_v1841(text,bigint,text,text) from public,anon;

revoke all on function public.person_residence_review_queue_v2043(text,text) from public,anon;

revoke all on function public.community_household_detail_v2043(uuid) from public,anon;

revoke all on function public.submit_household_member_request_v2043(uuid,text,text,text,date) from public,anon;

revoke all on function public.household_member_requests_v2043(uuid) from public,anon;

grant execute on function public.report_person_residence_v1841(text,bigint,text,text) to authenticated;

grant execute on function public.review_person_residence_v1841(text,bigint,text,text) to authenticated;

grant execute on function public.person_residence_review_queue_v2043(text,text) to authenticated;

grant execute on function public.community_household_detail_v2043(uuid) to authenticated;

grant execute on function public.submit_household_member_request_v2043(uuid,text,text,text,date) to authenticated;

grant execute on function public.household_member_requests_v2043(uuid) to authenticated;

insert into public.app_settings(key,value)
values('household_population_workflow_v2043',jsonb_build_object(
  'version','2.0.43','jhcis_write_back',false,
  'residence_states',jsonb_build_array('present','contact_unreachable','living_elsewhere','uncertain'),
  'registration_states',jsonb_build_array('registered_here','transfer_reported','transferred_confirmed'),
  'member_required_fields',jsonb_build_array('citizen_id_13','first_name','last_name','birth_date'),
  'existing_cid_policy','create pending request; never create duplicate population; admin links source_pcucode+PID',
  'linked_identifier_display','PID instead of CID'))
on conflict(key) do update set value=excluded.value,updated_at=now();

notify pgrst,'reload schema';

commit;
