-- Cloud v1.8.41: JHCIS type 1/3 context + field residence verification.
-- JHCIS remains read-only. Field observations and admin decisions live only in Cloud.

alter table public.health_persons
  add column if not exists jhcis_typelive smallint;

comment on column public.health_persons.jhcis_typelive is
  'Read-only JHCIS person.typelive projection used for service-target review; no write-back.';

create table if not exists public.health_person_residence_status (
  source_pcucode text not null,
  source_pid bigint not null,
  house_pcucode text not null,
  hcode text not null,
  source_typelive smallint,
  field_status text not null default 'unverified'
    check (field_status in ('unverified','present','absent','uncertain')),
  review_state text not null default 'none'
    check (review_state in ('none','pending','confirmed')),
  service_target_active boolean not null default true,
  report_note text not null default '',
  reported_by uuid,
  reported_at timestamptz,
  decision_note text not null default '',
  decided_by uuid,
  decided_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (source_pcucode, source_pid),
  foreign key (source_pcucode, source_pid)
    references public.health_persons(source_pcucode, source_pid)
    on update cascade on delete restrict
);

create index if not exists health_person_residence_house_idx
  on public.health_person_residence_status(house_pcucode,hcode);
create index if not exists health_person_residence_queue_idx
  on public.health_person_residence_status(review_state,service_target_active,reported_at desc);

create table if not exists public.health_person_residence_events (
  id bigint generated always as identity primary key,
  source_pcucode text not null,
  source_pid bigint not null,
  house_pcucode text not null,
  hcode text not null,
  action text not null check (action in ('report_present','report_absent','report_uncertain','confirm_include','confirm_exclude')),
  field_status text not null,
  service_target_active boolean not null,
  note text not null default '',
  actor_id uuid not null,
  actor_role text not null,
  created_at timestamptz not null default now(),
  foreign key (source_pcucode, source_pid)
    references public.health_persons(source_pcucode, source_pid)
    on update cascade on delete restrict
);

create index if not exists health_person_residence_events_person_idx
  on public.health_person_residence_events(source_pcucode,source_pid,created_at desc);

alter table public.health_person_residence_status enable row level security;
alter table public.health_person_residence_events enable row level security;

drop policy if exists health_person_residence_status_select on public.health_person_residence_status;
create policy health_person_residence_status_select
on public.health_person_residence_status
for select to authenticated
using (
  (select auth.uid()) is not null
  and private.health_can_access_house(house_pcucode,hcode)
);

revoke all on table public.health_person_residence_status from anon, authenticated;
revoke all on table public.health_person_residence_events from anon, authenticated;
grant select on table public.health_person_residence_status to authenticated;
grant all on table public.health_person_residence_status to service_role;
grant all on table public.health_person_residence_events to service_role;
grant usage,select on sequence public.health_person_residence_events_id_seq to service_role;

alter view public.health_person_worklist set (security_invoker=true);
revoke all on table public.health_person_worklist from anon;
revoke insert,update,delete,truncate,references,trigger on table public.health_person_worklist from authenticated;
grant select on table public.health_person_worklist to authenticated;

create or replace view public.health_person_worklist_active_v1841
with (security_invoker=true) as
select w.*,
       p.jhcis_typelive,
       coalesce(s.field_status,'unverified')::text as residence_status,
       coalesce(s.review_state,'none')::text as residence_review_state,
       coalesce(s.service_target_active,true)::boolean as service_target_active
from public.health_person_worklist w
join public.health_persons p
  on p.source_pcucode=w.source_pcucode and p.source_pid=w.source_pid
left join public.health_person_residence_status s
  on s.source_pcucode=w.source_pcucode and s.source_pid=w.source_pid
where coalesce(s.service_target_active,true)=true;

revoke all on table public.health_person_worklist_active_v1841 from anon;
revoke insert,update,delete,truncate,references,trigger on table public.health_person_worklist_active_v1841 from authenticated;
grant select on table public.health_person_worklist_active_v1841 to authenticated;

create or replace view public.health_work_summary
with (security_invoker=true) as
select count(*) as people,
       count(*) filter (where age_years>=35) as age35plus,
       count(*) filter (where ncd_target) as ncd_targets,
       count(*) filter (where ncd_target and screened_current_fy) as ncd_screened_current_fy,
       count(*) filter (where ncd_target and not screened_current_fy) as ncd_due,
       count(*) filter (where known_ncd) as known_ncd,
       count(*) filter (where life_stage='เน€เธ”เนเธเธเธเธกเธงเธฑเธข') as early_child,
       count(*) filter (where life_stage='เน€เธ”เนเธเธงเธฑเธขเน€เธฃเธตเธขเธ') as school_age,
       count(*) filter (where life_stage='เธงเธฑเธขเธฃเธธเนเธเนเธฅเธฐเน€เธขเธฒเธงเธเธ') as youth,
       count(*) filter (where life_stage='เธงเธฑเธขเธ—เธณเธเธฒเธ') as working_age,
       count(*) filter (where life_stage='เธเธนเนเธชเธนเธเธญเธฒเธขเธธ') as older_people
from public.health_person_worklist_active_v1841;

revoke all on table public.health_work_summary from anon;
revoke insert,update,delete,truncate,references,trigger on table public.health_work_summary from authenticated;
grant select on table public.health_work_summary to authenticated;

create or replace view public.health_2q_summary
with (security_invoker=true) as
select count(*) as latest_ncd_screenings,
       count(*) filter (where latest.mental_2q_status='assessed') as mental_2q_assessed,
       count(*) filter (where latest.mental_2q_status='not_assessed') as mental_2q_not_assessed,
       count(*) filter (where latest.mental_2q_status='incomplete') as mental_2q_incomplete,
       count(*) filter (where latest.mental_2q_status='assessed' and latest.mental_2q_result is true) as mental_2q_positive,
       count(*) filter (where latest.mental_2q_status='assessed' and latest.mental_2q_result is false) as mental_2q_negative
from (
  select distinct on (s.source_pcucode,s.source_pid)
         s.source_pcucode,s.source_pid,s.mental_2q_status,s.mental_2q_result
  from public.health_ncd_screenings s
  order by s.source_pcucode,s.source_pid,s.screened_on desc,s.recorded_at desc
) latest
join public.health_person_worklist_active_v1841 w
  on w.source_pcucode=latest.source_pcucode and w.source_pid=latest.source_pid;

revoke all on table public.health_2q_summary from anon;
revoke insert,update,delete,truncate,references,trigger on table public.health_2q_summary from authenticated;
grant select on table public.health_2q_summary to authenticated;

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
  v_status text:=lower(btrim(coalesce(p_status,'')));
  v_action text;
  v_target boolean;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_profile from public.profiles where user_id=v_uid and active=true;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;
  if v_status not in ('present','absent','uncertain') then raise exception 'INVALID_RESIDENCE_STATUS'; end if;
  select * into v_person from public.health_persons
  where source_pcucode=p_source_pcucode and source_pid=p_source_pid and active=true;
  if not found then raise exception 'PERSON_NOT_FOUND'; end if;
  if not private.health_can_access_house(v_person.house_pcucode,v_person.hcode) then
    raise exception 'PERSON_OUT_OF_SCOPE';
  end if;

  insert into public.health_person_residence_status(
    source_pcucode,source_pid,house_pcucode,hcode,source_typelive,
    field_status,review_state,report_note,reported_by,reported_at,updated_at
  ) values (
    v_person.source_pcucode,v_person.source_pid,v_person.house_pcucode,v_person.hcode,v_person.jhcis_typelive,
    v_status,'pending',left(btrim(coalesce(p_note,'')),500),v_uid,now(),now()
  )
  on conflict (source_pcucode,source_pid) do update set
    house_pcucode=excluded.house_pcucode,
    hcode=excluded.hcode,
    source_typelive=excluded.source_typelive,
    field_status=excluded.field_status,
    review_state='pending',
    report_note=excluded.report_note,
    reported_by=excluded.reported_by,
    reported_at=excluded.reported_at,
    decision_note='',decided_by=null,decided_at=null,updated_at=now();

  select service_target_active into v_target
  from public.health_person_residence_status
  where source_pcucode=v_person.source_pcucode and source_pid=v_person.source_pid;
  v_action:=case v_status when 'present' then 'report_present' when 'absent' then 'report_absent' else 'report_uncertain' end;
  insert into public.health_person_residence_events(
    source_pcucode,source_pid,house_pcucode,hcode,action,field_status,
    service_target_active,note,actor_id,actor_role
  ) values (
    v_person.source_pcucode,v_person.source_pid,v_person.house_pcucode,v_person.hcode,v_action,v_status,
    v_target,left(btrim(coalesce(p_note,'')),500),v_uid,v_profile.role
  );
  return jsonb_build_object('ok',true,'field_status',v_status,'review_state','pending','service_target_active',v_target);
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
  v_decision text:=lower(btrim(coalesce(p_decision,'')));
  v_active boolean;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_profile from public.profiles where user_id=v_uid and active=true;
  if not found or v_profile.role<>'admin' then raise exception 'ADMIN_REQUIRED'; end if;
  if v_decision not in ('include','exclude') then raise exception 'INVALID_DECISION'; end if;
  select * into v_state from public.health_person_residence_status
  where source_pcucode=p_source_pcucode and source_pid=p_source_pid for update;
  if not found then raise exception 'RESIDENCE_REPORT_NOT_FOUND'; end if;
  v_active:=v_decision='include';
  update public.health_person_residence_status set
    review_state='confirmed',service_target_active=v_active,
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
  return jsonb_build_object('ok',true,'review_state','confirmed','service_target_active',v_active);
end;
$$;

create or replace function public.person_residence_review_queue_v1841(
  p_community text default null,
  p_state text default 'pending'
) returns table(
  source_pcucode text,source_pid bigint,display_name text,gender text,age_years integer,
  house_no text,moo text,community text,jhcis_typelive smallint,field_status text,
  review_state text,service_target_active boolean,report_note text,reported_at timestamptz
)
language plpgsql security definer
set search_path=public,private,extensions
as $$
declare
  v_uid uuid:=auth.uid();
  v_role text;
  v_state text:=lower(btrim(coalesce(p_state,'pending')));
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select role into v_role from public.profiles where user_id=v_uid and active=true;
  if v_role<>'admin' then raise exception 'ADMIN_REQUIRED'; end if;
  return query
  select p.source_pcucode,p.source_pid,p.display_name,p.gender,
         case when p.birth_date is null then null else extract(year from age(current_date,p.birth_date))::integer end,
         h.house_no,h.moo,h.community,p.jhcis_typelive,s.field_status,s.review_state,
         s.service_target_active,s.report_note,s.reported_at
  from public.health_person_residence_status s
  join public.health_persons p on p.source_pcucode=s.source_pcucode and p.source_pid=s.source_pid
  join public.houses h on h.source_pcucode=p.house_pcucode and h.hcode=p.hcode
  where (nullif(btrim(coalesce(p_community,'')),'') is null or btrim(h.community)=btrim(p_community))
    and (v_state='all' or s.review_state=v_state)
  order by case when s.review_state='pending' then 0 else 1 end,s.reported_at desc,p.display_name;
end;
$$;

create or replace function public.community_household_cards_v1841(p_community text)
returns table(
  id uuid,house_no text,hcode text,house_id_11 text,moo text,community text,
  latitude double precision,longitude double precision,volunteer_pid bigint,volunteer_name text,
  spatial_status text,can_edit boolean,health_access boolean,member_count bigint,older_count bigint,
  age35plus_count bigint,ncd_target_count bigint,ncd_due_count bigint,known_ncd_count bigint,
  latest_screened_on date,quality_code text,quality_label text
)
language sql security definer
set search_path=public,private,extensions
as $$
  select c.id,c.house_no,c.hcode,c.house_id_11,c.moo,c.community,c.latitude,c.longitude,
         c.volunteer_pid,c.volunteer_name,c.spatial_status,c.can_edit,c.health_access,
         case when c.health_access then coalesce(x.member_count,0) else null end,
         case when c.health_access then coalesce(x.older_count,0) else null end,
         case when c.health_access then coalesce(x.age35plus_count,0) else null end,
         case when c.health_access then coalesce(x.ncd_target_count,0) else null end,
         case when c.health_access then coalesce(x.ncd_due_count,0) else null end,
         case when c.health_access then coalesce(x.known_ncd_count,0) else null end,
         case when c.health_access then x.latest_screened_on else null end,
         case
           when not c.health_access then 'spatial'
           when c.spatial_status='outside_tambon' then 'pink'
           when c.spatial_status in ('missing','outside_community','review') then 'orange'
           when coalesce(x.ncd_due_count,0)>=2 then 'orange'
           when coalesce(x.ncd_due_count,0)=1 or coalesce(x.member_count,0)=0 then 'yellow'
           else 'green'
         end::text,
         case
           when not c.health_access then 'เธ”เธนเธเนเธญเธกเธนเธฅเธเธทเนเธเธ—เธตเน'
           when c.spatial_status='outside_tambon' then 'เธ•เธฃเธงเธเธเธทเนเธเธ—เธตเนเน€เธฃเนเธเธ”เนเธงเธ'
           when c.spatial_status in ('missing','outside_community','review') then 'เธเธงเธฃเธ•เธฃเธงเธเธเนเธญเธกเธนเธฅเธเนเธฒเธ'
           when coalesce(x.ncd_due_count,0)>=2 then 'เธกเธตเธเธฒเธเธชเธธเธเธ เธฒเธเธเธงเธฃเธ•เธดเธ”เธ•เธฒเธก'
           when coalesce(x.ncd_due_count,0)=1 then 'เธกเธตเธเธฒเธเธ•เธดเธ”เธ•เธฒเธก'
           when coalesce(x.member_count,0)=0 then 'เธขเธฑเธเนเธกเนเธเธเธชเธกเธฒเธเธดเธเน€เธเธทเนเธญเธกเธเนเธฒเธ'
           else 'เธเนเธญเธกเธนเธฅเธเธฃเนเธญเธกเนเธเนเธเธฒเธ'
         end::text
  from public.community_household_cards_v1831(p_community) c
  left join public.houses h on h.id=c.id
  left join lateral (
    select count(*)::bigint member_count,
           count(*) filter(where w.age_years>=60)::bigint older_count,
           count(*) filter(where w.age_years>=35)::bigint age35plus_count,
           count(*) filter(where w.ncd_target)::bigint ncd_target_count,
           count(*) filter(where w.ncd_target and not coalesce(w.screened_current_fy,false))::bigint ncd_due_count,
           count(*) filter(where w.known_ncd)::bigint known_ncd_count,
           max(w.latest_screened_on)::date latest_screened_on
    from public.health_person_worklist_active_v1841 w
    where w.source_pcucode=h.source_pcucode and w.hcode=h.hcode
  ) x on true;
$$;

create or replace function public.community_household_detail_v1841(p_house_id uuid)
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
  v_house_pcucode:=v_base->'house'->>'house_pcucode';
  v_hcode:=v_base->'house'->>'hcode';
  if nullif(v_house_pcucode,'') is null then
    select h.source_pcucode into v_house_pcucode from public.houses h where h.id=p_house_id;
  end if;

  select jsonb_build_object(
    'members',count(*),'older_people',count(*) filter(where w.age_years>=60),
    'age35plus',count(*) filter(where w.age_years>=35),'ncd_targets',count(*) filter(where w.ncd_target),
    'ncd_due',count(*) filter(where w.ncd_target and not coalesce(w.screened_current_fy,false)),
    'known_ncd',count(*) filter(where w.known_ncd),'latest_screened_on',max(w.latest_screened_on)
  ) into v_summary
  from public.health_person_worklist_active_v1841 w
  where w.source_pcucode=v_house_pcucode and w.hcode=v_hcode;

  select coalesce(jsonb_agg(jsonb_build_object(
    'source_pcucode',w.source_pcucode,'source_pid',w.source_pid,'display_name',w.display_name,
    'gender',w.gender,'age_years',w.age_years,'life_stage',w.life_stage,'known_ncd',w.known_ncd,
    'ncd_target',w.ncd_target,'screened_current_fy',w.screened_current_fy,
    'latest_screened_on',w.latest_screened_on,'latest_ncd_status',w.latest_ncd_status,
    'latest_severity',w.latest_severity,'jhcis_typelive',w.jhcis_typelive,
    'residence_status',w.residence_status,'residence_review_state',w.residence_review_state,
    'service_target_active',w.service_target_active,
    'task_label',case
      when w.ncd_target and not coalesce(w.screened_current_fy,false) then 'NCD เธขเธฑเธเธกเธตเธเธฒเธเธเธฑเธ”เธเธฃเธญเธเธ•เธฒเธกเธฃเธฒเธขเธเธฒเธฃเธฃเธฐเธเธ'
      when w.known_ncd then 'เธกเธต DM/HT เน€เธ”เธดเธกเนเธเธเนเธญเธกเธนเธฅเธฃเธฐเธเธ'
      else 'เนเธกเนเธกเธตเธเธฒเธ NCD เธเนเธฒเธเธ—เธตเนเธฃเธฐเธเธเธฃเธฐเธเธธ' end,
    'mental_2q_status',q.mental_2q_status,'mental_2q_result',q.mental_2q_result
  ) order by w.age_years desc nulls last,w.display_name),'[]'::jsonb) into v_members
  from public.health_person_worklist_active_v1841 w
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

revoke all on function public.report_person_residence_v1841(text,bigint,text,text) from public,anon;
revoke all on function public.review_person_residence_v1841(text,bigint,text,text) from public,anon;
revoke all on function public.person_residence_review_queue_v1841(text,text) from public,anon;
revoke all on function public.community_household_cards_v1841(text) from public,anon;
revoke all on function public.community_household_detail_v1841(uuid) from public,anon;
grant execute on function public.report_person_residence_v1841(text,bigint,text,text) to authenticated;
grant execute on function public.review_person_residence_v1841(text,bigint,text,text) to authenticated;
grant execute on function public.person_residence_review_queue_v1841(text,text) to authenticated;
grant execute on function public.community_household_cards_v1841(text) to authenticated;
grant execute on function public.community_household_detail_v1841(uuid) to authenticated;

comment on table public.health_person_residence_status is
  'Cloud-only field verification state. Does not alter or write back to JHCIS.';
comment on table public.health_person_residence_events is
  'Append-only audit history for residence reports and admin target decisions.';
