
create or replace function public.refresh_health_screening_plan_v2023(p_as_of date default current_date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_day date:=greatest(coalesce(p_as_of,current_date),date '2026-10-01');
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
      when 'child_0_5' then 'น้ำหนัก/ส่วนสูง + พัฒนาการเบื้องต้น'
      when 'school_6_14' then 'น้ำหนัก/ส่วนสูง'
      when 'youth_15_34' then 'คัดกรองเสริมตามช่วงที่ Admin เปิด'
      when 'ncd_35_59' then 'NCD Screening'
      else 'NCD Screening ก่อน แล้วทำผู้สูงอายุ 9 ด้าน'
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
  where (current_plan.plan_date,current_plan.birth_date,current_plan.age_years,current_plan.age_months,current_plan.route,current_plan.route_label,current_plan.dspm_target_months,current_plan.target_enabled)
  is distinct from
  (excluded.plan_date,excluded.birth_date,excluded.age_years,excluded.age_months,excluded.route,excluded.route_label,excluded.dspm_target_months,excluded.target_enabled);
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
    'population_definition','jhcis_typelive_1_3_and_nation_99','version','2.1.60'
  );
end;
$function$;

create or replace function public.local_admin_refresh_targets_v2076()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
DECLARE
 v_role text:=coalesce(nullif(current_setting('request.jwt.claim.role',true),''),
  coalesce(nullif(current_setting('request.jwt.claims',true),'{}')::jsonb->>'role',''));
 v_today date:=greatest((now() at time zone 'Asia/Bangkok')::date,date '2026-10-01');
 v_stale bigint;v_drift bigint;v_plan jsonb;v_cache jsonb;v_count bigint;
BEGIN
 IF v_role<>'service_role' THEN RAISE EXCEPTION 'SERVICE_ROLE_REQUIRED' USING errcode='42501'; END IF;
 IF NOT pg_try_advisory_xact_lock(hashtext('osm_phc_screening_targets_daily_v2075')) THEN
   RETURN jsonb_build_object('ok',false,'status','busy_retry');
 END IF;
 SELECT count(*) INTO v_stale FROM public.health_screening_plan_v2023
  WHERE plan_date IS DISTINCT FROM v_today;
 SELECT count(*) INTO v_drift FROM public.health_screening_target_cache_v2030 c
 LEFT JOIN public.houses h ON h.source_pcucode=c.source_pcucode AND h.hcode=c.hcode
 WHERE c.screening_plan_date IS DISTINCT FROM v_today OR h.id IS NULL
 OR ROW(c.house_no,c.moo,c.community,c.volunteer_pid)
 IS DISTINCT FROM ROW(h.house_no,h.moo,h.community,h.volunteer_pid);
 IF v_stale=0 AND v_drift=0 THEN
   RETURN jsonb_build_object('ok',true,'status','already_current','plan_date',v_today);
 END IF;
 v_plan:=public.refresh_health_screening_plan_v2023(v_today);
 v_cache:=public.refresh_screening_target_cache_v2030();
 SELECT count(*) INTO v_count FROM public.health_screening_target_cache_v2030;
 IF NOT coalesce((v_plan->>'ok')::boolean,false) OR NOT coalesce((v_cache->>'ok')::boolean,false)
 OR v_count<>(SELECT count(*) FROM public.health_screening_target_worklist_v2026)
 OR EXISTS(SELECT 1 FROM public.health_screening_plan_v2023 WHERE plan_date IS DISTINCT FROM v_today)
 THEN RAISE EXCEPTION 'TARGET_REFRESH_VALIDATION_FAILED'; END IF;
 RETURN jsonb_build_object('ok',true,'status','refreshed','plan_date',v_today,
  'plan_rows',v_plan->'prepared_rows','cache_rows',v_count);
END;
$function$;

create or replace function private.refresh_screening_targets_daily_v2075()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
DECLARE
  v_plan jsonb;v_cache jsonb;v_expected bigint;v_actual bigint;
  v_reference date:=greatest(current_date,date '2026-10-01');
BEGIN
  IF session_user<>'postgres' OR auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'CRON_POSTGRES_ONLY';
  END IF;
  IF NOT pg_try_advisory_xact_lock(hashtext('osm_phc_screening_targets_daily_v2075')) THEN
    RETURN jsonb_build_object('ok',true,'status','busy_skipped');
  END IF;
  PERFORM set_config('request.jwt.claim.role','service_role',true);
  v_plan:=public.refresh_health_screening_plan_v2023(v_reference);
  v_cache:=public.refresh_screening_target_cache_v2030();
  IF NOT coalesce((v_plan->>'ok')::boolean,false)
     OR NOT coalesce((v_cache->>'ok')::boolean,false) THEN
    RAISE EXCEPTION 'DAILY_SCREENING_REFRESH_INCOMPLETE';
  END IF;
  SELECT count(*) INTO v_expected FROM public.health_screening_target_worklist_v2026;
  SELECT count(*) INTO v_actual FROM public.health_screening_target_cache_v2030;
  IF v_expected<>v_actual OR EXISTS(
    SELECT 1 FROM public.health_screening_plan_v2023 WHERE plan_date<>v_reference
  ) THEN
    RAISE EXCEPTION 'DAILY_SCREENING_REFRESH_VALIDATION_FAILED';
  END IF;
  RETURN jsonb_build_object('ok',true,'status','ready','plan_date',v_reference,
    'plan_rows',v_plan->'prepared_rows','changed_rows',v_plan->'changed_rows',
    'cache_rows',v_actual,'production_screenings_restored',v_cache->'production_screenings_restored');
END;
$function$;

create or replace function public.health_parity_snapshot_v2120()
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $function$
declare
  v_health_hash text;
  v_reference date:=greatest(current_date,date '2026-10-01');
begin
  if auth.role()<>'service_role'
     and (auth.uid() is null or private.current_role()<>'admin') then
    raise exception 'ADMIN_OR_SERVICE_REQUIRED';
  end if;

  select md5(coalesce(string_agg(
    concat_ws('|',
      p.source_pcucode,p.source_pid::text,coalesce(p.hcode,''),coalesce(p.jhcis_typelive::text,''),
      coalesce(p.has_dm::text,'false'),coalesce(p.has_ht::text,'false'),coalesce(p.birth_date::text,''),
      coalesce(p.source_updated_at,'')
    ), E'\n' order by p.source_pcucode,p.source_pid
  ),'')) into v_health_hash
  from public.health_persons p
  where p.active=true and p.service_population_eligible=true;

  return jsonb_build_object(
    'version','2.1.60','as_of',now(),'target_reference_date',v_reference,
    'health_state_hash',v_health_hash,
    'health_active_service',(select count(*) from public.health_persons p where p.active=true and p.service_population_eligible=true),
    'age35',(select count(*) from public.health_persons p where p.active=true and p.service_population_eligible=true and p.birth_date is not null and extract(year from age(v_reference,p.birth_date))::int>=35),
    'none_age35',(select count(*) from public.health_persons p where p.active=true and p.service_population_eligible=true and p.birth_date is not null and extract(year from age(v_reference,p.birth_date))::int>=35 and not coalesce(p.has_dm,false) and not coalesce(p.has_ht,false)),
    'dm_only_age35',(select count(*) from public.health_persons p where p.active=true and p.service_population_eligible=true and p.birth_date is not null and extract(year from age(v_reference,p.birth_date))::int>=35 and coalesce(p.has_dm,false) and not coalesce(p.has_ht,false)),
    'ht_only_age35',(select count(*) from public.health_persons p where p.active=true and p.service_population_eligible=true and p.birth_date is not null and extract(year from age(v_reference,p.birth_date))::int>=35 and not coalesce(p.has_dm,false) and coalesce(p.has_ht,false)),
    'both_age35',(select count(*) from public.health_persons p where p.active=true and p.service_population_eligible=true and p.birth_date is not null and extract(year from age(v_reference,p.birth_date))::int>=35 and coalesce(p.has_dm,false) and coalesce(p.has_ht,false)),
    'dm_target_expected',(select count(*) from public.health_persons p where p.active=true and p.service_population_eligible=true and p.birth_date is not null and extract(year from age(v_reference,p.birth_date))::int>=35 and not coalesce(p.has_dm,false)),
    'ht_target_expected',(select count(*) from public.health_persons p where p.active=true and p.service_population_eligible=true and p.birth_date is not null and extract(year from age(v_reference,p.birth_date))::int>=35 and not coalesce(p.has_ht,false)),
    'target_cache_rows',(select count(*) from public.health_screening_target_cache_v2030),
    'target_cache_age35',(select count(*) from public.health_screening_target_cache_v2030 where age_years>=35),
    'target_cache_dm_target',(select count(*) from public.health_screening_target_cache_v2030 where dm_target),
    'target_cache_ht_target',(select count(*) from public.health_screening_target_cache_v2030 where ht_target),
    'verified_houses',(select count(*) from public.houses h where h.source_pcucode='06116' and h.verification_status='verified_jhcis' and h.superseded_by is null)
  );
end;
$function$;
