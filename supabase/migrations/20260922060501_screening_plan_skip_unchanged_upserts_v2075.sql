CREATE OR REPLACE FUNCTION public.refresh_health_screening_plan_v2023(p_as_of date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  insert into public.health_screening_plan_v2023 as current_plan(
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
    target_enabled=excluded.target_enabled,updated_at=now()
  where (current_plan.plan_date,current_plan.birth_date,current_plan.age_years,current_plan.age_months,current_plan.route,current_plan.route_label,current_plan.dspm_target_months,current_plan.target_enabled) is distinct from (excluded.plan_date,excluded.birth_date,excluded.age_years,excluded.age_months,excluded.route,excluded.route_label,excluded.dspm_target_months,excluded.target_enabled);
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
    'ok',true,'plan_date',v_day,'prepared_rows',(select count(*) from public.health_screening_plan_v2023 where plan_date=v_day),'changed_rows',v_count,
    'eligible_population',v_population,'field_targets',v_targets,
    'population_definition','jhcis_typelive_1_3_and_nation_99','version','2.0.26'
  );
end;
$function$;
