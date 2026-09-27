
CREATE OR REPLACE FUNCTION private.refresh_screening_targets_daily_v2075()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $job$
DECLARE v_plan jsonb;v_cache jsonb;v_expected bigint;v_actual bigint;
BEGIN
  -- Scheduled maintenance only; do not expose elevated refresh to client roles.
  IF session_user<>'postgres' OR auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'CRON_POSTGRES_ONLY';
  END IF;
  IF NOT pg_try_advisory_xact_lock(hashtext('osm_phc_screening_targets_daily_v2075')) THEN
    RETURN jsonb_build_object('ok',true,'status','busy_skipped');
  END IF;
  -- pg_cron is UTC. Schedule after UTC midnight so current_date is Bangkok's date.
  PERFORM set_config('request.jwt.claim.role','service_role',true);
  v_plan:=public.refresh_health_screening_plan_v2023(current_date);
  v_cache:=public.refresh_screening_target_cache_v2030();
  IF NOT coalesce((v_plan->>'ok')::boolean,false)
     OR NOT coalesce((v_cache->>'ok')::boolean,false) THEN
    RAISE EXCEPTION 'DAILY_SCREENING_REFRESH_INCOMPLETE';
  END IF;
  SELECT count(*) INTO v_expected FROM public.health_screening_target_worklist_v2026;
  SELECT count(*) INTO v_actual FROM public.health_screening_target_cache_v2030;
  IF v_expected<>v_actual OR EXISTS(
    SELECT 1 FROM public.health_screening_plan_v2023 WHERE plan_date<>current_date
  ) THEN
    RAISE EXCEPTION 'DAILY_SCREENING_REFRESH_VALIDATION_FAILED';
  END IF;
  RETURN jsonb_build_object('ok',true,'status','ready','plan_date',current_date,
    'plan_rows',v_plan->'prepared_rows','changed_rows',v_plan->'changed_rows',
    'cache_rows',v_actual,'production_screenings_restored',v_cache->'production_screenings_restored');
END;
$job$;

REVOKE ALL ON FUNCTION private.refresh_screening_targets_daily_v2075() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private.refresh_screening_targets_daily_v2075() TO postgres;

SELECT cron.schedule(
  'osm-phc-screening-targets-daily-v2075',
  '10 0 * * *',
  $cron$select private.refresh_screening_targets_daily_v2075();$cron$
);
