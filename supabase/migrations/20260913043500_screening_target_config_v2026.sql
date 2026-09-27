-- Cloud v2.0.26: fast precomputed screening targets + admin target controls.
-- Operational population = JHCIS typelive 1/3 AND nation=99.
-- Default field target = age 35+ (routes ncd_35_59 + elderly_60_plus).
-- Younger routes are admin-controlled and are precomputed before field use.
begin;

-- cvd_population_eligible is the existing read-only projection of JHCIS nation=99.
comment on column public.health_persons.service_population_eligible is
  'Operational population flag: active JHCIS person with typelive in (1,3) AND nation=99.';

comment on column public.health_persons.ncd_base_eligible is
  'Base NCD operational population: typelive 1/3 AND nation=99; age and known DM/HT rules are applied separately.';

update public.health_persons p
set service_population_eligible = (
      p.active=true and p.jhcis_typelive in (1,3) and coalesce(p.cvd_population_eligible,false)=true
    ),
    ncd_base_eligible = (
      p.active=true and p.jhcis_typelive in (1,3) and coalesce(p.cvd_population_eligible,false)=true
    )
where p.service_population_eligible is distinct from (
        p.active=true and p.jhcis_typelive in (1,3) and coalesce(p.cvd_population_eligible,false)=true
      )
   or p.ncd_base_eligible is distinct from (
        p.active=true and p.jhcis_typelive in (1,3) and coalesce(p.cvd_population_eligible,false)=true
      );

create index if not exists health_persons_service_population_v2026_idx
  on public.health_persons(service_population_eligible,active,jhcis_typelive,source_pcucode,source_pid);

create table if not exists public.health_screening_target_groups_v2026 (
  route text primary key check(route in ('child_0_5','school_6_14','youth_15_34','ncd_35_59','elderly_60_plus')),
  label text not null,
  age_label text not null,
  enabled boolean not null default false,
  locked boolean not null default false,
  display_order smallint not null default 0,
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);

insert into public.health_screening_target_groups_v2026(route,label,age_label,enabled,locked,display_order)
values
  ('child_0_5','เน€เธ”เนเธเธเธเธกเธงเธฑเธข','0โ€“5 เธเธต',false,false,10),
  ('school_6_14','เน€เธ”เนเธเธงเธฑเธขเน€เธฃเธตเธขเธ','6โ€“14 เธเธต',false,false,20),
  ('youth_15_34','เธงเธฑเธขเธฃเธธเนเธ/เธงเธฑเธขเธ—เธณเธเธฒเธเธ•เธญเธเธ•เนเธ','15โ€“34 เธเธต',false,false,30),
  ('ncd_35_59','NCD Screening','35โ€“59 เธเธต',true,true,40),
  ('elderly_60_plus','เธเธนเนเธชเธนเธเธญเธฒเธขเธธ','60 เธเธตเธเธถเนเธเนเธ',true,true,50)
on conflict(route) do nothing;

alter table public.health_screening_target_groups_v2026 enable row level security;

revoke all on public.health_screening_target_groups_v2026 from public,anon,authenticated;

grant select on public.health_screening_target_groups_v2026 to authenticated;

drop policy if exists health_screening_target_groups_select_v2026 on public.health_screening_target_groups_v2026;

create policy health_screening_target_groups_select_v2026
on public.health_screening_target_groups_v2026 for select to authenticated
using(auth.uid() is not null);

alter table public.health_screening_plan_v2023
  add column if not exists target_enabled boolean not null default false;

create index if not exists health_screening_plan_field_target_v2026_idx
  on public.health_screening_plan_v2023(target_enabled,plan_date,route,source_pcucode,source_pid);

-- Main active worklist now uses exactly Type 1/3 + nation 99, while residence review remains separate.
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
where p.service_population_eligible=true
  and coalesce(s.service_target_active,true)=true;

revoke all on table public.health_person_worklist_active_v1841 from anon;

revoke insert,update,delete,truncate,references,trigger on table public.health_person_worklist_active_v1841 from authenticated;

grant select on table public.health_person_worklist_active_v1841 to authenticated;

create or replace function public.refresh_health_screening_plan_v2023(p_as_of date default current_date)
returns jsonb
language plpgsql security definer
set search_path=''
as $$
declare
  v_day date:=coalesce(p_as_of,current_date);
  v_count bigint:=0;
  v_targets bigint:=0;
  v_population bigint:=0;
begin
  if auth.role()<>'service_role' and (auth.uid() is null or private.current_role()<>'admin') then
    raise exception 'ADMIN_OR_SERVICE_REQUIRED';
  end if;
  if v_day<date '2020-01-01' or v_day>current_date+interval '370 days' then
    raise exception 'INVALID_PLAN_DATE';
  end if;

  with base as (
    select p.source_pcucode,p.source_pid,p.birth_date,
      extract(year from age(v_day,p.birth_date))::integer as age_years,
      ((extract(year from age(v_day,p.birth_date))::integer*12)+extract(month from age(v_day,p.birth_date))::integer) as age_months
    from public.health_persons p
    where p.active=true
      and p.service_population_eligible=true
      and p.birth_date is not null
      and p.birth_date<=v_day
      and extract(year from age(v_day,p.birth_date)) between 0 and 120
  ), routed as (
    select b.*,private.screening_route_v190(b.age_months) as route
    from base b
  )
  insert into public.health_screening_plan_v2023(
    source_pcucode,source_pid,plan_date,birth_date,age_years,age_months,
    route,route_label,dspm_target_months,target_enabled,updated_at
  )
  select r.source_pcucode,r.source_pid,v_day,r.birth_date,r.age_years,r.age_months,
    r.route,
    case r.route
      when 'child_0_5' then 'เธเนเธณเธซเธเธฑเธ/เธชเนเธงเธเธชเธนเธ + เธเธฑเธ’เธเธฒเธเธฒเธฃเน€เธเธทเนเธญเธเธ•เนเธ'
      when 'school_6_14' then 'เธเนเธณเธซเธเธฑเธ/เธชเนเธงเธเธชเธนเธ'
      when 'youth_15_34' then 'เธเธฑเธ”เธเธฃเธญเธเน€เธชเธฃเธดเธกเธ•เธฒเธกเธเนเธงเธเธ—เธตเน Admin เน€เธเธดเธ”'
      when 'ncd_35_59' then 'NCD Screening'
      else 'NCD Screening เธเนเธญเธ เนเธฅเนเธงเธ—เธณเธเธนเนเธชเธนเธเธญเธฒเธขเธธ 9 เธ”เนเธฒเธ'
    end,
    case when r.age_months<72 then private.closest_dspm_target_v190(r.age_months) else null end,
    coalesce(g.enabled,false),
    now()
  from routed r
  left join public.health_screening_target_groups_v2026 g on g.route=r.route
  on conflict(source_pcucode,source_pid) do update set
    plan_date=excluded.plan_date,birth_date=excluded.birth_date,
    age_years=excluded.age_years,age_months=excluded.age_months,
    route=excluded.route,route_label=excluded.route_label,
    dspm_target_months=excluded.dspm_target_months,
    target_enabled=excluded.target_enabled,updated_at=now();
  get diagnostics v_count=row_count;

  delete from public.health_screening_plan_v2023 x
  where not exists(
    select 1 from public.health_persons p
    where p.source_pcucode=x.source_pcucode and p.source_pid=x.source_pid
      and p.active=true and p.service_population_eligible=true and p.birth_date is not null
  );

  select count(*) into v_population
  from public.health_persons p
  where p.active=true and p.service_population_eligible=true;

  select count(*) into v_targets
  from public.health_screening_plan_v2023 x
  where x.plan_date=v_day and x.target_enabled=true;

  return jsonb_build_object(
    'ok',true,'plan_date',v_day,'prepared_rows',v_count,
    'eligible_population',v_population,'field_targets',v_targets,
    'population_definition','jhcis_typelive_1_3_and_nation_99','version','2.0.26'
  );
end;
$$;

revoke all on function public.refresh_health_screening_plan_v2023(date) from public,anon;

grant execute on function public.refresh_health_screening_plan_v2023(date) to authenticated,service_role;

-- Align cached rows immediately with current population and route settings.
delete from public.health_screening_plan_v2023 x
where not exists(
  select 1 from public.health_persons p
  where p.source_pcucode=x.source_pcucode and p.source_pid=x.source_pid
    and p.active=true and p.service_population_eligible=true and p.birth_date is not null
);

update public.health_screening_plan_v2023 pl
set target_enabled=coalesce(g.enabled,false),updated_at=now()
from public.health_screening_target_groups_v2026 g
where g.route=pl.route
  and pl.target_enabled is distinct from g.enabled;

create or replace view public.health_person_worklist_active_v1847
with (security_invoker=true) as
select w.*,p.has_cvd,p.cvd_population_eligible,
       pl.plan_date as screening_plan_date,
       pl.age_months as screening_age_months,
       pl.route as screening_route,
       pl.route_label as screening_route_label,
       pl.dspm_target_months as screening_dspm_target_months,
       pl.updated_at as screening_plan_updated_at,
       pl.target_enabled as field_target_enabled
from public.health_person_worklist_active_v1841 w
join public.health_persons p
  on p.source_pcucode=w.source_pcucode and p.source_pid=w.source_pid
left join public.health_screening_plan_v2023 pl
  on pl.source_pcucode=w.source_pcucode and pl.source_pid=w.source_pid;

revoke all on table public.health_person_worklist_active_v1847 from anon;

revoke insert,update,delete,truncate,references,trigger on table public.health_person_worklist_active_v1847 from authenticated;

grant select on table public.health_person_worklist_active_v1847 to authenticated;

-- Slim precomputed list for the first field screen. It intentionally avoids the heavy history view.
create or replace view public.health_screening_target_worklist_v2026
with (security_invoker=true) as
select
  p.source_pcucode,p.source_pid,p.hcode,h.house_no,h.moo,h.community,h.volunteer_pid,
  p.display_name,p.gender,p.birth_date,pl.age_years,
  case when pl.age_years<=5 then 'เน€เธ”เนเธเธเธเธกเธงเธฑเธข'
       when pl.age_years<=14 then 'เน€เธ”เนเธเธงเธฑเธขเน€เธฃเธตเธขเธ'
       when pl.age_years<=24 then 'เธงเธฑเธขเธฃเธธเนเธเนเธฅเธฐเน€เธขเธฒเธงเธเธ'
       when pl.age_years<=59 then 'เธงเธฑเธขเธ—เธณเธเธฒเธ'
       else 'เธเธนเนเธชเธนเธเธญเธฒเธขเธธ' end::text as life_stage,
  p.has_ht,p.has_dm,(p.has_ht or p.has_dm) as known_ncd,
  (pl.age_years>=35 and not (p.has_ht or p.has_dm)) as ncd_target,
  p.previous_screened_on as latest_screened_on,
  case when p.previous_screened_on is not null then 'เธกเธตเธเธฃเธฐเธงเธฑเธ•เธดเธเธฑเธ”เธเธฃเธญเธเน€เธ”เธดเธก' else null end::text as latest_ncd_status,
  null::text as latest_severity,
  false::boolean as screened_current_fy,
  p.previous_screened_on,p.previous_weight_kg,p.previous_height_cm,p.previous_waist_cm,
  p.previous_sbp,p.previous_dbp,p.previous_glucose_mg_dl,p.previous_bmi,p.previous_source,
  ''::text as previous_smoking,''::text as previous_alcohol,''::text as previous_exercise,
  p.has_cvd,p.cvd_population_eligible,
  pl.plan_date as screening_plan_date,pl.age_months as screening_age_months,
  pl.route as screening_route,pl.route_label as screening_route_label,
  pl.dspm_target_months as screening_dspm_target_months,
  pl.target_enabled as field_target_enabled,pl.updated_at as screening_plan_updated_at
from public.health_screening_plan_v2023 pl
join public.health_persons p
  on p.source_pcucode=pl.source_pcucode and p.source_pid=pl.source_pid
join public.houses h
  on h.source_pcucode=p.house_pcucode and h.hcode=p.hcode
left join public.health_person_residence_status rs
  on rs.source_pcucode=p.source_pcucode and rs.source_pid=p.source_pid
where p.active=true
  and p.service_population_eligible=true
  and pl.target_enabled=true
  and coalesce(rs.service_target_active,true)=true;

revoke all on table public.health_screening_target_worklist_v2026 from anon;

revoke insert,update,delete,truncate,references,trigger on table public.health_screening_target_worklist_v2026 from authenticated;

grant select on table public.health_screening_target_worklist_v2026 to authenticated;

create or replace function public.screening_target_settings_v2026()
returns jsonb
language plpgsql stable security definer
set search_path=''
as $$
declare
  v_groups jsonb;
  v_population bigint:=0;
  v_prepared bigint:=0;
  v_targets bigint:=0;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'route',g.route,'label',g.label,'age_label',g.age_label,
    'enabled',g.enabled,'locked',g.locked,'display_order',g.display_order,
    'updated_at',g.updated_at
  ) order by g.display_order),'[]'::jsonb) into v_groups
  from public.health_screening_target_groups_v2026 g;

  select count(*) into v_population from public.health_persons p
   where p.active=true and p.service_population_eligible=true;
  select count(*) into v_prepared from public.health_screening_plan_v2023 p
   where p.plan_date=current_date;
  select count(*) into v_targets from public.health_screening_plan_v2023 p
   where p.plan_date=current_date and p.target_enabled=true;

  return jsonb_build_object(
    'version','2.0.26','population_definition','Type 1/3 + nation 99',
    'eligible_population',v_population,'prepared_rows',v_prepared,
    'field_targets',v_targets,'groups',v_groups
  );
end;
$$;

revoke all on function public.screening_target_settings_v2026() from public,anon;

grant execute on function public.screening_target_settings_v2026() to authenticated;

create or replace function public.admin_set_screening_target_group_v2026(p_route text,p_enabled boolean)
returns jsonb
language plpgsql security definer
set search_path=''
as $$
declare
  v_row public.health_screening_target_groups_v2026%rowtype;
  v_refresh jsonb;
begin
  if auth.uid() is null or private.current_role()<>'admin' then raise exception 'ADMIN_REQUIRED'; end if;
  select * into v_row from public.health_screening_target_groups_v2026 where route=btrim(p_route) for update;
  if not found then raise exception 'UNKNOWN_TARGET_GROUP'; end if;
  if v_row.locked and coalesce(p_enabled,false)=false then raise exception 'AGE_35_PLUS_TARGET_IS_REQUIRED'; end if;

  update public.health_screening_target_groups_v2026
  set enabled=coalesce(p_enabled,false),updated_by=auth.uid(),updated_at=now()
  where route=v_row.route;

  v_refresh:=public.refresh_health_screening_plan_v2023(current_date);
  insert into public.health_audit_log(operator_id,action,entity,entity_id,severity,details)
  values(auth.uid(),'UPDATE','screening_target_group',v_row.route,'',jsonb_build_object('enabled',coalesce(p_enabled,false),'refresh',v_refresh));
  return public.screening_target_settings_v2026();
end;
$$;

revoke all on function public.admin_set_screening_target_group_v2026(text,boolean) from public,anon;

grant execute on function public.admin_set_screening_target_group_v2026(text,boolean) to authenticated;

create or replace function public.admin_refresh_screening_targets_v2026()
returns jsonb
language plpgsql security definer
set search_path=''
as $$
declare v_refresh jsonb;
begin
  if auth.uid() is null or private.current_role()<>'admin' then raise exception 'ADMIN_REQUIRED'; end if;
  v_refresh:=public.refresh_health_screening_plan_v2023(current_date);
  insert into public.health_audit_log(operator_id,action,entity,entity_id,severity,details)
  values(auth.uid(),'REFRESH','screening_targets','all','',v_refresh);
  return v_refresh || jsonb_build_object('settings',public.screening_target_settings_v2026());
end;
$$;

revoke all on function public.admin_refresh_screening_targets_v2026() from public,anon;

grant execute on function public.admin_refresh_screening_targets_v2026() to authenticated;

insert into public.app_settings(key,value)
values('population_definition_v2026',jsonb_build_object(
  'version','2.0.26','source','JHCIS read-only',
  'typelive',jsonb_build_array(1,3),'nation','99',
  'definition','เธเธฃเธฐเธเธฒเธเธฃ operational = typelive 1/3 เนเธฅเธฐ nation=99',
  'jhcis_write_back',false
)) on conflict(key) do update set value=excluded.value,updated_at=now();

insert into public.app_settings(key,value)
values('screening_targets_v2026',jsonb_build_object(
  'version','2.0.26','default_target','age_35_plus',
  'admin_configurable_routes',jsonb_build_array('child_0_5','school_6_14','youth_15_34'),
  'locked_routes',jsonb_build_array('ncd_35_59','elderly_60_plus'),
  'strategy','precompute_then_fast_worklist','jhcis_write_back',false
)) on conflict(key) do update set value=excluded.value,updated_at=now();

notify pgrst,'reload schema';

commit;
