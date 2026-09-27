-- Cloud v2.0.23 Performance Architecture
-- Pre-compute age-based screening routes for field work, keep open-screen reads cheap,
-- and create screening_sessions only when a workflow actually needs a session.
-- JHCIS remains read-only.
begin;

create table if not exists public.health_screening_plan_v2023 (
  source_pcucode text not null,
  source_pid bigint not null,
  plan_date date not null,
  birth_date date,
  age_years integer not null check(age_years between 0 and 120),
  age_months integer not null check(age_months between 0 and 1452),
  route text not null check(route in ('child_0_5','school_6_14','youth_15_34','ncd_35_59','elderly_60_plus')),
  route_label text not null,
  dspm_target_months integer,
  updated_at timestamptz not null default now(),
  primary key(source_pcucode,source_pid),
  foreign key(source_pcucode,source_pid)
    references public.health_persons(source_pcucode,source_pid)
    on update cascade on delete cascade
);

create index if not exists health_screening_plan_route_v2023_idx
  on public.health_screening_plan_v2023(route,plan_date,source_pcucode,source_pid);

create index if not exists health_screening_plan_date_v2023_idx
  on public.health_screening_plan_v2023(plan_date,updated_at desc);

alter table public.health_screening_plan_v2023 enable row level security;

revoke all on public.health_screening_plan_v2023 from public,anon,authenticated;

grant select on public.health_screening_plan_v2023 to authenticated;

grant all on public.health_screening_plan_v2023 to service_role;

drop policy if exists health_screening_plan_select_v2023 on public.health_screening_plan_v2023;

create policy health_screening_plan_select_v2023
on public.health_screening_plan_v2023 for select to authenticated
using(private.health_can_access_person(source_pcucode,source_pid));

-- Covers both pre-go-live test rows and production rows for same-day checks.
create index if not exists health_ncd_person_day_mode_v2023_idx
  on public.health_ncd_screenings(source_pcucode,source_pid,screened_on,record_mode,recorded_at desc);

create or replace function public.refresh_health_screening_plan_v2023(p_as_of date default current_date)
returns jsonb
language plpgsql security definer
set search_path=''
as $$
declare
  v_day date:=coalesce(p_as_of,current_date);
  v_count bigint:=0;
begin
  if auth.role()<>'service_role' and (auth.uid() is null or private.current_role()<>'admin') then
    raise exception 'ADMIN_OR_SERVICE_REQUIRED';
  end if;
  if v_day<date '2020-01-01' or v_day>current_date+interval '370 days' then
    raise exception 'INVALID_PLAN_DATE';
  end if;

  insert into public.health_screening_plan_v2023(
    source_pcucode,source_pid,plan_date,birth_date,age_years,age_months,
    route,route_label,dspm_target_months,updated_at
  )
  select p.source_pcucode,p.source_pid,v_day,p.birth_date,
    extract(year from age(v_day,p.birth_date))::integer,
    (extract(year from age(v_day,p.birth_date))::integer*12)+extract(month from age(v_day,p.birth_date))::integer,
    private.screening_route_v190((extract(year from age(v_day,p.birth_date))::integer*12)+extract(month from age(v_day,p.birth_date))::integer),
    case private.screening_route_v190((extract(year from age(v_day,p.birth_date))::integer*12)+extract(month from age(v_day,p.birth_date))::integer)
      when 'child_0_5' then 'เธเนเธณเธซเธเธฑเธ/เธชเนเธงเธเธชเธนเธ + เธเธฑเธ’เธเธฒเธเธฒเธฃเน€เธเธทเนเธญเธเธ•เนเธ'
      when 'school_6_14' then 'เธเนเธณเธซเธเธฑเธ/เธชเนเธงเธเธชเธนเธ'
      when 'youth_15_34' then 'เธเธฑเธ”เธเธฃเธญเธเน€เธชเธฃเธดเธกเธ•เธฒเธกเธเนเธงเธเธ—เธตเน Admin เน€เธเธดเธ”'
      when 'ncd_35_59' then 'NCD Screening'
      else 'NCD Screening เธเนเธญเธ เนเธฅเนเธงเธ—เธณเธเธนเนเธชเธนเธเธญเธฒเธขเธธ 9 เธ”เนเธฒเธ'
    end,
    case when ((extract(year from age(v_day,p.birth_date))::integer*12)+extract(month from age(v_day,p.birth_date))::integer)<72
      then private.closest_dspm_target_v190((extract(year from age(v_day,p.birth_date))::integer*12)+extract(month from age(v_day,p.birth_date))::integer)
      else null end,
    now()
  from public.health_persons p
  where p.active=true and p.birth_date is not null and p.birth_date<=v_day
    and extract(year from age(v_day,p.birth_date)) between 0 and 120
  on conflict(source_pcucode,source_pid) do update set
    plan_date=excluded.plan_date,birth_date=excluded.birth_date,
    age_years=excluded.age_years,age_months=excluded.age_months,
    route=excluded.route,route_label=excluded.route_label,
    dspm_target_months=excluded.dspm_target_months,updated_at=now();
  get diagnostics v_count=row_count;

  delete from public.health_screening_plan_v2023 x
  where not exists(
    select 1 from public.health_persons p
    where p.source_pcucode=x.source_pcucode and p.source_pid=x.source_pid
      and p.active=true and p.birth_date is not null
  );

  return jsonb_build_object('ok',true,'plan_date',v_day,'prepared_rows',v_count,'version','2.0.23');
end;
$$;

revoke all on function public.refresh_health_screening_plan_v2023(date) from public,anon;

grant execute on function public.refresh_health_screening_plan_v2023(date) to authenticated,service_role;

-- Initial pre-computation at migration time. Subsequent health sync calls refresh RPC.
insert into public.health_screening_plan_v2023(
  source_pcucode,source_pid,plan_date,birth_date,age_years,age_months,
  route,route_label,dspm_target_months,updated_at
)
select p.source_pcucode,p.source_pid,current_date,p.birth_date,
  extract(year from age(current_date,p.birth_date))::integer,
  (extract(year from age(current_date,p.birth_date))::integer*12)+extract(month from age(current_date,p.birth_date))::integer,
  private.screening_route_v190((extract(year from age(current_date,p.birth_date))::integer*12)+extract(month from age(current_date,p.birth_date))::integer),
  case private.screening_route_v190((extract(year from age(current_date,p.birth_date))::integer*12)+extract(month from age(current_date,p.birth_date))::integer)
    when 'child_0_5' then 'เธเนเธณเธซเธเธฑเธ/เธชเนเธงเธเธชเธนเธ + เธเธฑเธ’เธเธฒเธเธฒเธฃเน€เธเธทเนเธญเธเธ•เนเธ'
    when 'school_6_14' then 'เธเนเธณเธซเธเธฑเธ/เธชเนเธงเธเธชเธนเธ'
    when 'youth_15_34' then 'เธเธฑเธ”เธเธฃเธญเธเน€เธชเธฃเธดเธกเธ•เธฒเธกเธเนเธงเธเธ—เธตเน Admin เน€เธเธดเธ”'
    when 'ncd_35_59' then 'NCD Screening'
    else 'NCD Screening เธเนเธญเธ เนเธฅเนเธงเธ—เธณเธเธนเนเธชเธนเธเธญเธฒเธขเธธ 9 เธ”เนเธฒเธ'
  end,
  case when ((extract(year from age(current_date,p.birth_date))::integer*12)+extract(month from age(current_date,p.birth_date))::integer)<72
    then private.closest_dspm_target_v190((extract(year from age(current_date,p.birth_date))::integer*12)+extract(month from age(current_date,p.birth_date))::integer)
    else null end,
  now()
from public.health_persons p
where p.active=true and p.birth_date is not null and p.birth_date<=current_date
  and extract(year from age(current_date,p.birth_date)) between 0 and 120
on conflict(source_pcucode,source_pid) do update set
  plan_date=excluded.plan_date,birth_date=excluded.birth_date,
  age_years=excluded.age_years,age_months=excluded.age_months,
  route=excluded.route,route_label=excluded.route_label,
  dspm_target_months=excluded.dspm_target_months,updated_at=now();

-- Read-only plan endpoint: no session INSERT/UPDATE merely for opening a person's route.
create or replace function public.screening_plan_for_person_v2023(
  p_source_pcucode text,p_source_pid bigint,p_screening_date date default current_date
) returns jsonb
language plpgsql stable security definer
set search_path=''
as $$
declare
  p public.health_persons%rowtype;
  pl public.health_screening_plan_v2023%rowtype;
  s public.screening_sessions%rowtype;
  n public.health_ncd_screenings%rowtype;
  v_day date:=coalesce(p_screening_date,current_date);
  v_years integer;v_months integer;v_route text;v_label text;v_target integer;v_source text:='precomputed';
  v_mode text;
begin
  if auth.uid() is null or private.current_role() not in ('user','staff','admin') then raise exception 'AUTH_REQUIRED'; end if;
  if v_day>current_date+1 then raise exception 'SCREENING_DATE_IN_FUTURE'; end if;
  select * into p from public.health_persons
  where source_pcucode=btrim(p_source_pcucode) and source_pid=p_source_pid and active=true;
  if not found then raise exception 'PERSON_NOT_FOUND'; end if;
  if not private.health_can_access_person(p.source_pcucode,p.source_pid) then raise exception 'PERSON_OUT_OF_SCOPE'; end if;
  if p.birth_date is null or p.birth_date>v_day then raise exception 'BIRTH_DATE_REQUIRED'; end if;

  select * into pl from public.health_screening_plan_v2023
  where source_pcucode=p.source_pcucode and source_pid=p.source_pid and plan_date=v_day;
  if found then
    v_years:=pl.age_years;v_months:=pl.age_months;v_route:=pl.route;v_label:=pl.route_label;v_target:=pl.dspm_target_months;
  else
    v_source:='live_fallback';
    v_years:=extract(year from age(v_day,p.birth_date))::integer;
    v_months:=(v_years*12)+extract(month from age(v_day,p.birth_date))::integer;
    v_route:=private.screening_route_v190(v_months);
    v_target:=case when v_route='child_0_5' then private.closest_dspm_target_v190(v_months) else null end;
    v_label:=case v_route when 'child_0_5' then 'เธเนเธณเธซเธเธฑเธ/เธชเนเธงเธเธชเธนเธ + เธเธฑเธ’เธเธฒเธเธฒเธฃเน€เธเธทเนเธญเธเธ•เนเธ' when 'school_6_14' then 'เธเนเธณเธซเธเธฑเธ/เธชเนเธงเธเธชเธนเธ'
      when 'youth_15_34' then 'เธเธฑเธ”เธเธฃเธญเธเน€เธชเธฃเธดเธกเธ•เธฒเธกเธเนเธงเธเธ—เธตเน Admin เน€เธเธดเธ”' when 'ncd_35_59' then 'NCD Screening' else 'NCD Screening เธเนเธญเธ เนเธฅเนเธงเธ—เธณเธเธนเนเธชเธนเธเธญเธฒเธขเธธ 9 เธ”เนเธฒเธ' end;
  end if;

  v_mode:=private.screening_record_mode_v208(v_day);
  if v_route in ('ncd_35_59','elderly_60_plus') then
    select * into n from public.health_ncd_screenings x
    where x.source_pcucode=p.source_pcucode and x.source_pid=p.source_pid
      and x.screened_on=v_day and coalesce(x.record_mode,'production')=v_mode
    order by x.recorded_at desc limit 1;
  end if;
  select * into s from public.screening_sessions x
  where x.source_pcucode=p.source_pcucode and x.source_pid=p.source_pid
    and x.screening_date=v_day and x.started_by=auth.uid()
  limit 1;

  return jsonb_build_object(
    'session_id',case when s.id is null then null else s.id end,
    'source_pcucode',p.source_pcucode,'source_pid',p.source_pid,'display_name',p.display_name,
    'age_years',v_years,'age_months',v_months,'route',v_route,'route_label',v_label,
    'dspm_target_months',v_target,'plan_date',v_day,'plan_source',v_source,
    'record_mode',v_mode,'go_live_date','2026-10-01',
    'ncd_screening_id',case when n.id is null then s.ncd_screening_id else n.id end,
    'ncd_status',case when v_route not in ('ncd_35_59','elderly_60_plus') then 'not_required' when n.id is not null or s.ncd_status='complete' then 'complete' else 'required' end,
    'elderly9_status',case when v_route<>'elderly_60_plus' then 'not_required' when n.id is null and coalesce(s.ncd_status,'required')<>'complete' then 'blocked_by_ncd' else coalesce(nullif(s.elderly9_status,'not_required'),'in_progress') end,
    'completed_domains',coalesce(s.completed_domains,'{}'::text[])
  );
end;
$$;

revoke all on function public.screening_plan_for_person_v2023(text,bigint,date) from public,anon;

grant execute on function public.screening_plan_for_person_v2023(text,bigint,date) to authenticated;

-- Optimized session creator. It uses the precomputed plan and does not UPDATE an existing
-- session unless NCD completion actually changed.
create or replace function public.start_age_screening_v190(
  p_source_pcucode text,p_source_pid bigint,p_screening_date date default current_date
) returns jsonb
language plpgsql security definer
set search_path=''
as $$
declare
  v_plan jsonb;
  p public.health_persons%rowtype;
  s public.screening_sessions%rowtype;
  n_id uuid;
  v_day date:=coalesce(p_screening_date,current_date);
  v_route text;v_ncd_status text;v_elderly text;
begin
  v_plan:=public.screening_plan_for_person_v2023(p_source_pcucode,p_source_pid,v_day);
  v_route:=v_plan->>'route';
  v_ncd_status:=v_plan->>'ncd_status';
  v_elderly:=v_plan->>'elderly9_status';
  n_id:=nullif(v_plan->>'ncd_screening_id','')::uuid;

  select * into s from public.screening_sessions x
  where x.source_pcucode=btrim(p_source_pcucode) and x.source_pid=p_source_pid
    and x.screening_date=v_day and x.started_by=auth.uid()
  limit 1;

  if found then
    if v_route in ('ncd_35_59','elderly_60_plus') and n_id is not null and
       (s.ncd_screening_id is distinct from n_id or s.ncd_status<>'complete') then
      update public.screening_sessions set
        ncd_screening_id=n_id,ncd_status='complete',
        elderly9_status=case when route='elderly_60_plus' and elderly9_status in ('blocked_by_ncd','not_required') then 'in_progress' else elderly9_status end,
        updated_at=now()
      where id=s.id returning * into s;
    end if;
  else
    select * into p from public.health_persons
    where source_pcucode=btrim(p_source_pcucode) and source_pid=p_source_pid and active=true;
    insert into public.screening_sessions(
      source_pcucode,source_pid,house_pcucode,hcode,screening_date,age_years,age_months,route,
      ncd_screening_id,ncd_status,elderly9_status,started_by
    ) values(
      p.source_pcucode,p.source_pid,p.house_pcucode,p.hcode,v_day,
      (v_plan->>'age_years')::integer,(v_plan->>'age_months')::integer,v_route,
      case when v_route in ('ncd_35_59','elderly_60_plus') then n_id else null end,
      case when v_route in ('ncd_35_59','elderly_60_plus') then v_ncd_status else 'not_required' end,
      case when v_route='elderly_60_plus' then v_elderly else 'not_required' end,
      auth.uid()
    ) returning * into s;
  end if;

  return v_plan || jsonb_build_object(
    'session_id',s.id,
    'ncd_screening_id',coalesce(n_id,s.ncd_screening_id),
    'ncd_status',s.ncd_status,'elderly9_status',s.elderly9_status,
    'completed_domains',s.completed_domains
  );
end;
$$;

revoke all on function public.start_age_screening_v190(text,bigint,date) from public,anon;

grant execute on function public.start_age_screening_v190(text,bigint,date) to authenticated;

create or replace function public.ensure_screening_session_v2023(
  p_source_pcucode text,p_source_pid bigint,p_screening_date date default current_date
) returns jsonb
language sql security definer
set search_path=''
as $$
  select public.start_age_screening_v190(p_source_pcucode,p_source_pid,p_screening_date)
$$;

revoke all on function public.ensure_screening_session_v2023(text,bigint,date) from public,anon;

grant execute on function public.ensure_screening_session_v2023(text,bigint,date) to authenticated;

-- Add prepared route metadata to the main field worklist. Existing columns stay intact.
create or replace view public.health_person_worklist_active_v1847
with (security_invoker=true) as
select w.*,p.has_cvd,p.cvd_population_eligible,
       pl.plan_date as screening_plan_date,
       pl.age_months as screening_age_months,
       pl.route as screening_route,
       pl.route_label as screening_route_label,
       pl.dspm_target_months as screening_dspm_target_months,
       pl.updated_at as screening_plan_updated_at
from public.health_person_worklist_active_v1841 w
join public.health_persons p
  on p.source_pcucode=w.source_pcucode and p.source_pid=w.source_pid
left join public.health_screening_plan_v2023 pl
  on pl.source_pcucode=w.source_pcucode and pl.source_pid=w.source_pid;

revoke all on table public.health_person_worklist_active_v1847 from anon;

revoke insert,update,delete,truncate,references,trigger on table public.health_person_worklist_active_v1847 from authenticated;

grant select on table public.health_person_worklist_active_v1847 to authenticated;

insert into public.app_settings(key,value)
values('screening_plan_v2023',jsonb_build_object(
  'version','2.0.23','strategy','precomputed_route_plus_lazy_session',
  'refresh','after_health_sync_and_admin_on_demand','fallback','single_person_live_calculation',
  'session_creation','only_when_workflow_needs_session','jhcis_write_back',false,
  'target_population_scale','4000+','concurrent_field_users','200+'
)) on conflict(key) do update set value=excluded.value,updated_at=now();

notify pgrst,'reload schema';

commit;
