CREATE OR REPLACE FUNCTION public.refresh_screening_target_cache_v2030()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_count bigint;
  v_production_merged bigint:=0;
begin
  if auth.role()<>'service_role' and (auth.uid() is null or private.current_role()<>'admin') then
    raise exception 'ADMIN_OR_SERVICE_REQUIRED';
  end if;
  truncate table public.health_screening_target_cache_v2030;
  insert into public.health_screening_target_cache_v2030
  select * from public.health_screening_target_worklist_v2026;
  get diagnostics v_count=row_count;

  -- A full cache rebuild must not erase a newer real screening recorded in Cloud.
  -- Test-mode screenings are never promoted to production by this refresh.
  with latest_production as (
    select distinct on (s.source_pcucode,s.source_pid)
      s.source_pcucode,s.source_pid,s.screened_on,s.ncd_status,s.severity,
      s.weight_kg,s.height_cm,s.waist_cm,s.sbp,s.dbp,s.glucose_mg_dl,s.bmi,
      s.smoking_frequency,s.alcohol_frequency,s.exercise_frequency
    from public.health_ncd_screenings s
    where coalesce(s.record_mode,'production')='production'
    order by s.source_pcucode,s.source_pid,s.screened_on desc,s.recorded_at desc
  )
  update public.health_screening_target_cache_v2030 c set
    latest_screened_on=s.screened_on,
    latest_ncd_status=s.ncd_status,
    latest_severity=s.severity,
    screened_current_fy=s.screened_on >= (
      case when extract(month from current_date)>=10
        then make_date(extract(year from current_date)::int,10,1)
        else make_date(extract(year from current_date)::int-1,10,1) end
    ),
    previous_screened_on=s.screened_on,
    previous_weight_kg=s.weight_kg,
    previous_height_cm=s.height_cm,
    previous_waist_cm=s.waist_cm,
    previous_sbp=s.sbp,
    previous_dbp=s.dbp,
    previous_glucose_mg_dl=s.glucose_mg_dl,
    previous_bmi=s.bmi,
    previous_source='เธญเธชเธก. เธเธฅเธฑเธช',
    previous_smoking=coalesce(s.smoking_frequency,''),
    previous_alcohol=coalesce(s.alcohol_frequency,''),
    previous_exercise=coalesce(s.exercise_frequency,'')
  from latest_production s
  where c.source_pcucode=s.source_pcucode and c.source_pid=s.source_pid
    and (c.previous_screened_on is null or s.screened_on>=c.previous_screened_on);
  get diagnostics v_production_merged=row_count;

  return jsonb_build_object('ok',true,'cached_rows',v_count,'production_screenings_restored',v_production_merged,'version','2.0.30');
end;
$function$;
