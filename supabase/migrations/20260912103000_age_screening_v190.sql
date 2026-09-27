-- OSM-PHC Cloud v1.9.0
-- Phase E-F: age-based screening session, child growth/development and elderly 9 domains.
-- Child growth stores raw measurements; interpretation requires an approved reference dataset.
-- DSPM target ages follow current Department of Health references: 9,18,30,42,60 months.

begin;

create table if not exists public.screening_sessions (
  id uuid primary key default extensions.gen_random_uuid(),
  source_pcucode text not null,
  source_pid bigint not null,
  house_pcucode text not null,
  hcode text not null,
  screening_date date not null default current_date,
  age_years integer not null check(age_years between 0 and 120),
  age_months integer not null check(age_months between 0 and 1452),
  route text not null check(route in ('child_0_5','school_6_14','youth_15_34','ncd_35_59','elderly_60_plus')),
  ncd_screening_id uuid references public.health_ncd_screenings(id) on delete set null,
  ncd_status text not null default 'not_required' check(ncd_status in ('not_required','required','complete')),
  elderly9_status text not null default 'not_required' check(elderly9_status in ('not_required','blocked_by_ncd','in_progress','complete')),
  completed_domains text[] not null default '{}'::text[],
  started_by uuid not null references auth.users(id),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key(source_pcucode,source_pid) references public.health_persons(source_pcucode,source_pid),
  foreign key(house_pcucode,hcode) references public.houses(source_pcucode,hcode),
  unique(source_pcucode,source_pid,screening_date,started_by)
);

create index if not exists screening_sessions_person_v190_idx on public.screening_sessions(source_pcucode,source_pid,screening_date desc);

create index if not exists screening_sessions_route_v190_idx on public.screening_sessions(route,screening_date desc);

alter table public.screening_sessions enable row level security;

revoke all on public.screening_sessions from public,anon,authenticated;

grant select on public.screening_sessions to authenticated;

drop policy if exists screening_sessions_select_v190 on public.screening_sessions;

create policy screening_sessions_select_v190 on public.screening_sessions for select to authenticated
using(private.health_can_access_person(source_pcucode,source_pid));

create table if not exists public.health_growth_screenings (
  id uuid primary key default extensions.gen_random_uuid(),
  session_id uuid not null references public.screening_sessions(id) on delete cascade,
  source_pcucode text not null,
  source_pid bigint not null,
  screened_at timestamptz not null default now(),
  age_months integer not null,
  weight_kg numeric(6,2) not null check(weight_kg between 0.1 and 300),
  height_cm numeric(6,2) not null check(height_cm between 30 and 250),
  interpretation_code text not null default 'reference_pending',
  interpretation_label text not null default 'เธเธฑเธเธ—เธถเธเธเนเธฒเนเธฅเนเธง เธฃเธญเนเธเธฅเธเธฅเธ•เธฒเธกเน€เธเธ“เธ‘เนเธญเนเธฒเธเธญเธดเธเธ—เธตเนเธซเธเนเธงเธขเธเธฒเธเธเธณเธซเธเธ”',
  reference_version text not null default 'raw-only-v1.9.0',
  screened_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  foreign key(source_pcucode,source_pid) references public.health_persons(source_pcucode,source_pid)
);

create index if not exists growth_person_timeline_v190_idx on public.health_growth_screenings(source_pcucode,source_pid,screened_at desc);

alter table public.health_growth_screenings enable row level security;

revoke all on public.health_growth_screenings from public,anon,authenticated;

grant select on public.health_growth_screenings to authenticated;

drop policy if exists growth_select_v190 on public.health_growth_screenings;

create policy growth_select_v190 on public.health_growth_screenings for select to authenticated
using(private.health_can_access_person(source_pcucode,source_pid));

create table if not exists public.dspm_reference_periods (
  target_months integer primary key check(target_months between 0 and 72),
  label text not null,
  source_name text not null,
  source_url text not null default '',
  active boolean not null default true,
  updated_at timestamptz not null default now()
);

insert into public.dspm_reference_periods(target_months,label,source_name,source_url) values
(9,'9 เน€เธ”เธทเธญเธ','เธเธฃเธกเธญเธเธฒเธกเธฑเธข DSPM','https://dspm.anamai.moph.go.th/'),
(18,'18 เน€เธ”เธทเธญเธ','เธเธฃเธกเธญเธเธฒเธกเธฑเธข DSPM','https://dspm.anamai.moph.go.th/'),
(30,'30 เน€เธ”เธทเธญเธ','เธเธฃเธกเธญเธเธฒเธกเธฑเธข DSPM','https://dspm.anamai.moph.go.th/'),
(42,'42 เน€เธ”เธทเธญเธ','เธเธฃเธกเธญเธเธฒเธกเธฑเธข DSPM','https://dspm.anamai.moph.go.th/'),
(60,'60 เน€เธ”เธทเธญเธ','เธเธฃเธกเธญเธเธฒเธกเธฑเธข DSPM','https://dspm.anamai.moph.go.th/')
on conflict(target_months) do update set label=excluded.label,source_name=excluded.source_name,source_url=excluded.source_url,active=true,updated_at=now();

alter table public.dspm_reference_periods enable row level security;

revoke all on public.dspm_reference_periods from public,anon,authenticated;

grant select on public.dspm_reference_periods to authenticated;

drop policy if exists dspm_reference_select_v190 on public.dspm_reference_periods;

create policy dspm_reference_select_v190 on public.dspm_reference_periods for select to authenticated using(active=true);

create table if not exists public.child_development_screenings (
  id uuid primary key default extensions.gen_random_uuid(),
  session_id uuid not null references public.screening_sessions(id) on delete cascade,
  source_pcucode text not null,
  source_pid bigint not null,
  screened_at timestamptz not null default now(),
  actual_age_months integer not null,
  reference_target_months integer not null references public.dspm_reference_periods(target_months),
  domains jsonb not null default '{}'::jsonb,
  overall_status text not null check(overall_status in ('preliminary_normal','needs_further_assessment','incomplete')),
  note text not null default '',
  screened_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  foreign key(source_pcucode,source_pid) references public.health_persons(source_pcucode,source_pid)
);

create index if not exists child_dev_person_v190_idx on public.child_development_screenings(source_pcucode,source_pid,screened_at desc);

alter table public.child_development_screenings enable row level security;

revoke all on public.child_development_screenings from public,anon,authenticated;

grant select on public.child_development_screenings to authenticated;

drop policy if exists child_dev_select_v190 on public.child_development_screenings;

create policy child_dev_select_v190 on public.child_development_screenings for select to authenticated
using(private.health_can_access_person(source_pcucode,source_pid));

create table if not exists public.elderly9_domain_results (
  id uuid primary key default extensions.gen_random_uuid(),
  session_id uuid not null references public.screening_sessions(id) on delete cascade,
  source_pcucode text not null,
  source_pid bigint not null,
  domain_code text not null check(domain_code in ('vision','urinary','hearing','adl','cognition','depression','mobility','oral','nutrition')),
  status text not null default 'not_assessed' check(status in ('not_assessed','normal','observation')),
  checklist jsonb not null default '[]'::jsonb,
  note text not null default '',
  assessed_by uuid not null references auth.users(id),
  assessed_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key(source_pcucode,source_pid) references public.health_persons(source_pcucode,source_pid),
  unique(session_id,domain_code)
);

create index if not exists elderly9_person_v190_idx on public.elderly9_domain_results(source_pcucode,source_pid,assessed_at desc);

alter table public.elderly9_domain_results enable row level security;

revoke all on public.elderly9_domain_results from public,anon,authenticated;

grant select on public.elderly9_domain_results to authenticated;

drop policy if exists elderly9_select_v190 on public.elderly9_domain_results;

create policy elderly9_select_v190 on public.elderly9_domain_results for select to authenticated
using(private.health_can_access_person(source_pcucode,source_pid));

create table if not exists public.screening_followups (
  id uuid primary key default extensions.gen_random_uuid(),
  session_id uuid not null references public.screening_sessions(id) on delete cascade,
  source_pcucode text not null,
  source_pid bigint not null,
  followup_type text not null,
  domain_code text,
  priority text not null default 'orange' check(priority in ('yellow','orange','red')),
  status text not null default 'open' check(status in ('open','in_progress','done','cancelled')),
  summary text not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  unique(session_id,followup_type,domain_code),
  foreign key(source_pcucode,source_pid) references public.health_persons(source_pcucode,source_pid)
);

create index if not exists screening_followup_open_v190_idx on public.screening_followups(status,priority,created_at desc);

alter table public.screening_followups enable row level security;

revoke all on public.screening_followups from public,anon,authenticated;

grant select on public.screening_followups to authenticated;

drop policy if exists screening_followups_select_v190 on public.screening_followups;

create policy screening_followups_select_v190 on public.screening_followups for select to authenticated
using(private.health_can_access_person(source_pcucode,source_pid) or private.current_role()='admin');

create or replace function private.screening_route_v190(p_age_months integer)
returns text language sql immutable set search_path=''
as $$ select case when p_age_months<72 then 'child_0_5' when p_age_months<180 then 'school_6_14' when p_age_months<420 then 'youth_15_34' when p_age_months<720 then 'ncd_35_59' else 'elderly_60_plus' end $$;

revoke all on function private.screening_route_v190(integer) from public,anon,authenticated;

create or replace function private.closest_dspm_target_v190(p_age_months integer)
returns integer language sql stable security definer set search_path=''
as $$
  select d.target_months from public.dspm_reference_periods d where d.active=true
  order by abs(d.target_months-p_age_months),d.target_months limit 1
$$;

revoke all on function private.closest_dspm_target_v190(integer) from public,anon,authenticated;

create or replace function public.start_age_screening_v190(p_source_pcucode text,p_source_pid bigint,p_screening_date date default current_date)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
  p public.health_persons%rowtype;
  v_date date:=coalesce(p_screening_date,current_date);
  v_months integer;
  v_years integer;
  v_route text;
  s public.screening_sessions%rowtype;
  n public.health_ncd_screenings%rowtype;
  v_target integer;
begin
  if auth.uid() is null or private.current_role() not in ('user','staff','admin') then raise exception 'AUTH_REQUIRED'; end if;
  if v_date>current_date+1 then raise exception 'SCREENING_DATE_IN_FUTURE'; end if;
  select * into p from public.health_persons where source_pcucode=p_source_pcucode and source_pid=p_source_pid and active=true;
  if not found then raise exception 'PERSON_NOT_FOUND'; end if;
  if not private.health_can_access_person(p.source_pcucode,p.source_pid) then raise exception 'PERSON_OUT_OF_SCOPE'; end if;
  if p.birth_date is null or p.birth_date>v_date then raise exception 'BIRTH_DATE_REQUIRED'; end if;
  v_months:=(extract(year from age(v_date,p.birth_date))::integer*12)+extract(month from age(v_date,p.birth_date))::integer;
  v_years:=extract(year from age(v_date,p.birth_date))::integer;
  v_route:=private.screening_route_v190(v_months);

  select * into n from public.health_ncd_screenings x
  where x.source_pcucode=p.source_pcucode and x.source_pid=p.source_pid and x.screened_on=v_date and coalesce(x.record_mode,'production')='production'
  order by x.recorded_at desc limit 1;

  insert into public.screening_sessions(source_pcucode,source_pid,house_pcucode,hcode,screening_date,age_years,age_months,route,ncd_screening_id,ncd_status,elderly9_status,started_by)
  values(p.source_pcucode,p.source_pid,p.house_pcucode,p.hcode,v_date,v_years,v_months,v_route,
    case when v_route in ('ncd_35_59','elderly_60_plus') then n.id else null end,
    case when v_route in ('ncd_35_59','elderly_60_plus') then case when n.id is null then 'required' else 'complete' end else 'not_required' end,
    case when v_route='elderly_60_plus' then case when n.id is null then 'blocked_by_ncd' else 'in_progress' end else 'not_required' end,
    auth.uid())
  on conflict(source_pcucode,source_pid,screening_date,started_by) do update set
    age_years=excluded.age_years,age_months=excluded.age_months,route=excluded.route,
    ncd_screening_id=coalesce(excluded.ncd_screening_id,public.screening_sessions.ncd_screening_id),
    ncd_status=case when coalesce(excluded.ncd_screening_id,public.screening_sessions.ncd_screening_id) is null and excluded.route in ('ncd_35_59','elderly_60_plus') then 'required'
                    when excluded.route in ('ncd_35_59','elderly_60_plus') then 'complete' else 'not_required' end,
    elderly9_status=case when excluded.route='elderly_60_plus' and coalesce(excluded.ncd_screening_id,public.screening_sessions.ncd_screening_id) is null then 'blocked_by_ncd'
                         when excluded.route='elderly_60_plus' and public.screening_sessions.elderly9_status<>'complete' then 'in_progress'
                         when excluded.route<>'elderly_60_plus' then 'not_required' else public.screening_sessions.elderly9_status end,
    updated_at=now()
  returning * into s;
  v_target:=case when v_route='child_0_5' then private.closest_dspm_target_v190(v_months) else null end;
  return jsonb_build_object('session_id',s.id,'source_pcucode',p.source_pcucode,'source_pid',p.source_pid,'display_name',p.display_name,
    'age_years',v_years,'age_months',v_months,'route',v_route,'ncd_status',s.ncd_status,'ncd_screening_id',s.ncd_screening_id,
    'elderly9_status',s.elderly9_status,'completed_domains',s.completed_domains,'dspm_target_months',v_target,
    'route_label',case v_route when 'child_0_5' then 'เธเนเธณเธซเธเธฑเธ/เธชเนเธงเธเธชเธนเธ + เธเธฑเธ’เธเธฒเธเธฒเธฃเน€เธเธทเนเธญเธเธ•เนเธ' when 'school_6_14' then 'เธเนเธณเธซเธเธฑเธ/เธชเนเธงเธเธชเธนเธ'
      when 'youth_15_34' then 'เธขเธฑเธเนเธกเนเธกเธตเนเธเธเธเธฑเธ”เธเธฃเธญเธเธซเธฅเธฑเธเนเธเน€เธเธชเธเธตเน' when 'ncd_35_59' then 'NCD Screening' else 'NCD Screening เธเนเธญเธ เนเธฅเนเธงเธ—เธณเธเธนเนเธชเธนเธเธญเธฒเธขเธธ 9 เธ”เนเธฒเธ' end);
end;
$$;

revoke all on function public.start_age_screening_v190(text,bigint,date) from public,anon;

grant execute on function public.start_age_screening_v190(text,bigint,date) to authenticated;

create or replace function public.save_growth_screening_v190(p_session_id uuid,p_weight_kg numeric,p_height_cm numeric)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare s public.screening_sessions%rowtype; v_id uuid;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into s from public.screening_sessions where id=p_session_id for update;
  if not found or not private.health_can_access_person(s.source_pcucode,s.source_pid) then raise exception 'SESSION_OUT_OF_SCOPE'; end if;
  if s.route not in ('child_0_5','school_6_14') then raise exception 'GROWTH_NOT_APPLICABLE'; end if;
  if p_weight_kg is null or p_weight_kg<0.1 or p_weight_kg>300 then raise exception 'INVALID_WEIGHT'; end if;
  if p_height_cm is null or p_height_cm<30 or p_height_cm>250 then raise exception 'INVALID_HEIGHT'; end if;
  insert into public.health_growth_screenings(session_id,source_pcucode,source_pid,age_months,weight_kg,height_cm,screened_by)
  values(s.id,s.source_pcucode,s.source_pid,s.age_months,p_weight_kg,p_height_cm,auth.uid()) returning id into v_id;
  update public.screening_sessions set updated_at=now() where id=s.id;
  return jsonb_build_object('ok',true,'id',v_id,'status','recorded','interpretation','เธเธฑเธเธ—เธถเธเธเนเธฒเธ”เธดเธเนเธฅเนเธง เธขเธฑเธเนเธกเนเธชเธฃเธธเธเธ เธฒเธงเธฐเนเธ เธเธเธฒเธเธฒเธฃเธเธเธเธงเนเธฒเธเธฐเธ•เธดเธ”เธ•เธฑเนเธเธ•เธฒเธฃเธฒเธเน€เธเธ“เธ‘เนเธญเนเธฒเธเธญเธดเธเธ—เธตเนเธญเธเธธเธกเธฑเธ•เธด');
end;
$$;

revoke all on function public.save_growth_screening_v190(uuid,numeric,numeric) from public,anon;

grant execute on function public.save_growth_screening_v190(uuid,numeric,numeric) to authenticated;

create or replace function public.growth_timeline_v190(p_source_pcucode text,p_source_pid bigint)
returns table(id uuid,screened_at timestamptz,age_months integer,weight_kg numeric,height_cm numeric,interpretation_code text,interpretation_label text)
language plpgsql stable security definer set search_path=''
as $$
begin
  if auth.uid() is null or not private.health_can_access_person(p_source_pcucode,p_source_pid) then raise exception 'PERSON_OUT_OF_SCOPE'; end if;
  return query select g.id,g.screened_at,g.age_months,g.weight_kg,g.height_cm,g.interpretation_code,g.interpretation_label
  from public.health_growth_screenings g where g.source_pcucode=p_source_pcucode and g.source_pid=p_source_pid order by g.screened_at desc limit 50;
end;
$$;

revoke all on function public.growth_timeline_v190(text,bigint) from public,anon;

grant execute on function public.growth_timeline_v190(text,bigint) to authenticated;

create or replace function public.save_child_development_v190(p_session_id uuid,p_domains jsonb,p_note text default '')
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
  s public.screening_sessions%rowtype;
  keys text[]:=array['gross_motor','fine_motor_intelligence','receptive_language','expressive_language','personal_social'];
  k text; val text; v_normal integer:=0; v_observation integer:=0; v_assessed integer:=0; v_overall text; v_target integer; v_id uuid;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into s from public.screening_sessions where id=p_session_id for update;
  if not found or not private.health_can_access_person(s.source_pcucode,s.source_pid) then raise exception 'SESSION_OUT_OF_SCOPE'; end if;
  if s.route<>'child_0_5' then raise exception 'DEVELOPMENT_NOT_APPLICABLE'; end if;
  if jsonb_typeof(coalesce(p_domains,'{}'::jsonb))<>'object' then raise exception 'INVALID_DOMAINS'; end if;
  foreach k in array keys loop
    val:=coalesce(p_domains->>k,'not_assessed');
    if val not in ('normal','observation','not_assessed') then raise exception 'INVALID_DOMAIN_STATUS:%',k; end if;
    if val='normal' then v_normal:=v_normal+1;v_assessed:=v_assessed+1; end if;
    if val='observation' then v_observation:=v_observation+1;v_assessed:=v_assessed+1; end if;
  end loop;
  v_overall:=case when v_observation>0 then 'needs_further_assessment' when v_normal=5 then 'preliminary_normal' else 'incomplete' end;
  v_target:=private.closest_dspm_target_v190(s.age_months);
  insert into public.child_development_screenings(session_id,source_pcucode,source_pid,actual_age_months,reference_target_months,domains,overall_status,note,screened_by)
  values(s.id,s.source_pcucode,s.source_pid,s.age_months,v_target,p_domains,v_overall,left(coalesce(p_note,''),500),auth.uid()) returning id into v_id;
  if v_overall='needs_further_assessment' then
    insert into public.screening_followups(session_id,source_pcucode,source_pid,followup_type,domain_code,priority,summary,created_by)
    values(s.id,s.source_pcucode,s.source_pid,'child_development','all','orange','เธเธงเธฃเธเธฃเธฐเน€เธกเธดเธเธเธฑเธ’เธเธฒเธเธฒเธฃเน€เธเธดเนเธกเน€เธ•เธดเธกเธ•เธฒเธกเนเธเธเธกเธฒเธ•เธฃเธเธฒเธ',auth.uid())
    on conflict(session_id,followup_type,domain_code) do update set status='open',summary=excluded.summary;
  end if;
  update public.screening_sessions set updated_at=now(),completed_at=case when v_assessed=5 then now() else completed_at end where id=s.id;
  return jsonb_build_object('ok',true,'id',v_id,'actual_age_months',s.age_months,'reference_target_months',v_target,
    'overall_status',v_overall,'overall_label',case v_overall when 'preliminary_normal' then 'เธเธเธ•เธดเน€เธเธทเนเธญเธเธ•เนเธ' when 'needs_further_assessment' then 'เธเธงเธฃเธเธฃเธฐเน€เธกเธดเธเน€เธเธดเนเธกเน€เธ•เธดเธก' else 'เธเธฃเธฐเน€เธกเธดเธเนเธกเนเธเธฃเธ' end);
end;
$$;

revoke all on function public.save_child_development_v190(uuid,jsonb,text) from public,anon;

grant execute on function public.save_child_development_v190(uuid,jsonb,text) to authenticated;

create or replace function public.attach_ncd_to_screening_session_v190(p_session_id uuid,p_ncd_screening_id uuid default null)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare s public.screening_sessions%rowtype; n public.health_ncd_screenings%rowtype;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into s from public.screening_sessions where id=p_session_id for update;
  if not found or not private.health_can_access_person(s.source_pcucode,s.source_pid) then raise exception 'SESSION_OUT_OF_SCOPE'; end if;
  if s.route not in ('ncd_35_59','elderly_60_plus') then raise exception 'NCD_NOT_REQUIRED_FOR_ROUTE'; end if;
  if p_ncd_screening_id is null then
    select * into n from public.health_ncd_screenings x where x.source_pcucode=s.source_pcucode and x.source_pid=s.source_pid and x.screened_on=s.screening_date and coalesce(x.record_mode,'production')='production' order by x.recorded_at desc limit 1;
  else
    select * into n from public.health_ncd_screenings x where x.id=p_ncd_screening_id and x.source_pcucode=s.source_pcucode and x.source_pid=s.source_pid and x.screened_on=s.screening_date;
  end if;
  if not found then raise exception 'NCD_SCREENING_REQUIRED_SAME_DAY'; end if;
  update public.screening_sessions set ncd_screening_id=n.id,ncd_status='complete',elderly9_status=case when route='elderly_60_plus' and elderly9_status='blocked_by_ncd' then 'in_progress' else elderly9_status end,updated_at=now() where id=s.id returning * into s;
  return jsonb_build_object('ok',true,'ncd_status',s.ncd_status,'elderly9_status',s.elderly9_status,'ncd_screening_id',s.ncd_screening_id);
end;
$$;

revoke all on function public.attach_ncd_to_screening_session_v190(uuid,uuid) from public,anon;

grant execute on function public.attach_ncd_to_screening_session_v190(uuid,uuid) to authenticated;

create or replace function public.save_elderly9_domain_v190(p_session_id uuid,p_domain_code text,p_status text,p_checklist jsonb default '[]'::jsonb,p_note text default '')
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
  s public.screening_sessions%rowtype; d text:=lower(btrim(coalesce(p_domain_code,''))); st text:=lower(btrim(coalesce(p_status,'')));
  v_done integer; v_obs integer; v_label text;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into s from public.screening_sessions where id=p_session_id for update;
  if not found or not private.health_can_access_person(s.source_pcucode,s.source_pid) then raise exception 'SESSION_OUT_OF_SCOPE'; end if;
  if s.route<>'elderly_60_plus' or s.age_years<60 then raise exception 'ELDERLY9_NOT_APPLICABLE'; end if;
  if s.ncd_status<>'complete' or s.ncd_screening_id is null then raise exception 'NCD_SCREENING_REQUIRED_FIRST'; end if;
  if d not in ('vision','urinary','hearing','adl','cognition','depression','mobility','oral','nutrition') then raise exception 'INVALID_ELDERLY_DOMAIN'; end if;
  if st not in ('not_assessed','normal','observation') then raise exception 'INVALID_DOMAIN_STATUS'; end if;
  if jsonb_typeof(coalesce(p_checklist,'[]'::jsonb)) not in ('array','object') then raise exception 'INVALID_CHECKLIST'; end if;
  insert into public.elderly9_domain_results(session_id,source_pcucode,source_pid,domain_code,status,checklist,note,assessed_by)
  values(s.id,s.source_pcucode,s.source_pid,d,st,coalesce(p_checklist,'[]'::jsonb),left(coalesce(p_note,''),500),auth.uid())
  on conflict(session_id,domain_code) do update set status=excluded.status,checklist=excluded.checklist,note=excluded.note,assessed_by=auth.uid(),assessed_at=now(),updated_at=now();
  if st='observation' then
    insert into public.screening_followups(session_id,source_pcucode,source_pid,followup_type,domain_code,priority,summary,created_by)
    values(s.id,s.source_pcucode,s.source_pid,'elderly9',d,'orange','เธเธเธเนเธญเธชเธฑเธเน€เธเธ•เธเธฒเธเธเธฒเธฃเธเธฑเธ”เธเธฃเธญเธเธเธนเนเธชเธนเธเธญเธฒเธขเธธ เธเธงเธฃเธเธฃเธฐเน€เธกเธดเธเน€เธเธดเนเธกเน€เธ•เธดเธก',auth.uid())
    on conflict(session_id,followup_type,domain_code) do update set status='open',summary=excluded.summary;
  elsif st='normal' then
    update public.screening_followups set status='done',completed_at=now() where session_id=s.id and followup_type='elderly9' and domain_code=d and status<>'done';
  end if;
  select count(*) filter(where status in ('normal','observation')),count(*) filter(where status='observation') into v_done,v_obs from public.elderly9_domain_results where session_id=s.id;
  update public.screening_sessions set completed_domains=(select coalesce(array_agg(domain_code order by domain_code),'{}'::text[]) from public.elderly9_domain_results where session_id=s.id and status in ('normal','observation')),
    elderly9_status=case when v_done>=9 then 'complete' else 'in_progress' end,completed_at=case when v_done>=9 then now() else completed_at end,updated_at=now() where id=s.id;
  v_label:=case when st='normal' then 'เธเธเธ•เธด' when st='observation' then 'เธเธเธเนเธญเธชเธฑเธเน€เธเธ•' else 'เธขเธฑเธเนเธกเนเนเธ”เนเธเธฃเธฐเน€เธกเธดเธ' end;
  return jsonb_build_object('ok',true,'domain_code',d,'status',st,'status_label',v_label,'completed',v_done,'remaining',greatest(9-v_done,0),'observations',v_obs);
end;
$$;

revoke all on function public.save_elderly9_domain_v190(uuid,text,text,jsonb,text) from public,anon;

grant execute on function public.save_elderly9_domain_v190(uuid,text,text,jsonb,text) to authenticated;

create or replace function public.elderly9_progress_v190(p_session_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare s public.screening_sessions%rowtype; v_results jsonb; v_done integer; v_obs integer;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into s from public.screening_sessions where id=p_session_id;
  if not found or not private.health_can_access_person(s.source_pcucode,s.source_pid) then raise exception 'SESSION_OUT_OF_SCOPE'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('domain_code',x.domain_code,'status',x.status,'checklist',x.checklist,'note',x.note,'assessed_at',x.assessed_at) order by x.domain_code),'[]'::jsonb),
    count(*) filter(where x.status in ('normal','observation')),count(*) filter(where x.status='observation')
    into v_results,v_done,v_obs from public.elderly9_domain_results x where x.session_id=s.id;
  return jsonb_build_object('session_id',s.id,'ncd_status',s.ncd_status,'elderly9_status',s.elderly9_status,'completed',coalesce(v_done,0),'remaining',greatest(9-coalesce(v_done,0),0),'observations',coalesce(v_obs,0),'results',v_results);
end;
$$;

revoke all on function public.elderly9_progress_v190(uuid) from public,anon;

grant execute on function public.elderly9_progress_v190(uuid) to authenticated;

create or replace function public.screening_followup_worklist_v190(p_status text default 'open')
returns table(id uuid,source_pcucode text,source_pid bigint,display_name text,house_no text,community text,followup_type text,domain_code text,priority text,status text,summary text,created_at timestamptz)
language plpgsql stable security definer set search_path=''
as $$
declare v_status text:=lower(btrim(coalesce(p_status,'open')));
begin
  if auth.uid() is null or private.current_role() not in ('staff','admin') then raise exception 'STAFF_OR_ADMIN_REQUIRED'; end if;
  return query select f.id,f.source_pcucode,f.source_pid,p.display_name,h.house_no,h.community,f.followup_type,f.domain_code,f.priority,f.status,f.summary,f.created_at
  from public.screening_followups f join public.health_persons p on p.source_pcucode=f.source_pcucode and p.source_pid=f.source_pid join public.houses h on h.source_pcucode=p.house_pcucode and h.hcode=p.hcode
  where (v_status='all' or f.status=v_status) and private.health_can_access_person(f.source_pcucode,f.source_pid)
  order by case f.priority when 'red' then 0 when 'orange' then 1 else 2 end,f.created_at;
end;
$$;

revoke all on function public.screening_followup_worklist_v190(text) from public,anon;

grant execute on function public.screening_followup_worklist_v190(text) to authenticated;

insert into public.app_settings(key,value)
values('age_screening_v190',jsonb_build_object(
 'version','1.9.0','routing',jsonb_build_object('0-5','growth+development','6-14','growth','15-34','reserved','35-59','ncd','60+','ncd_then_elderly9'),
 'elderly_domains',jsonb_build_array('vision','urinary','hearing','adl','cognition','depression','mobility','oral','nutrition'),
 'elderly_reference','HDC s_aged9 Basic/Community Screen STEP1','dspm_target_months',jsonb_build_array(9,18,30,42,60),
 'growth_interpretation','raw_only_until_approved_reference_tables_loaded','screening_is_diagnosis',false
)) on conflict(key) do update set value=excluded.value,updated_at=now();

commit;
