
CREATE OR REPLACE FUNCTION public.local_admin_refresh_targets_v2076()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_role text:=coalesce(nullif(current_setting('request.jwt.claim.role',true),''),
  coalesce(nullif(current_setting('request.jwt.claims',true),'{}')::jsonb->>'role',''));
 v_today date:=(now() at time zone 'Asia/Bangkok')::date;
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
$fn$;
REVOKE ALL ON FUNCTION public.local_admin_refresh_targets_v2076() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.local_admin_refresh_targets_v2076() TO service_role;
