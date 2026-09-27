
CREATE TABLE IF NOT EXISTS private.cloud_storage_daily_v2076(
 day_bkk date PRIMARY KEY,
 checked_at timestamptz NOT NULL DEFAULT now(),
 database_bytes bigint NOT NULL CHECK(database_bytes>=0),
 report_cache_bytes bigint NOT NULL CHECK(report_cache_bytes>=0),
 report_generations int NOT NULL CHECK(report_generations>=0),
 report_cache_rows bigint NOT NULL CHECK(report_cache_rows>=0),
 target_plan_rows bigint NOT NULL CHECK(target_plan_rows>=0),
 target_cache_rows bigint NOT NULL CHECK(target_cache_rows>=0),
 target_cache_stale_rows bigint NOT NULL CHECK(target_cache_stale_rows>=0),
 target_refresh_latest_status text
);
REVOKE ALL ON private.cloud_storage_daily_v2076 FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION private.capture_cloud_storage_daily_v2076()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_day date:=(now() at time zone 'Asia/Bangkok')::date;
        v_latest text; v_snapshot private.cloud_storage_daily_v2076%ROWTYPE;
BEGIN
 IF session_user<>'postgres' THEN RAISE EXCEPTION 'CRON_POSTGRES_ONLY'; END IF;
 SELECT j.status INTO v_latest
 FROM cron.job_run_details j
 WHERE j.jobid=(SELECT jobid FROM cron.job WHERE jobname='osm-phc-screening-targets-daily-v2075' LIMIT 1)
 ORDER BY j.start_time DESC LIMIT 1;
 INSERT INTO private.cloud_storage_daily_v2076 (
 day_bkk,checked_at,database_bytes,report_cache_bytes,report_generations,
 report_cache_rows,target_plan_rows,target_cache_rows,target_cache_stale_rows,target_refresh_latest_status
 )
 VALUES (
 v_day,clock_timestamp(),pg_database_size(current_database()),
 pg_total_relation_size('public.report_snapshot_cache_v2031'::regclass),
 (SELECT count(distinct generation)::int FROM public.report_snapshot_cache_v2031),
 (SELECT count(*) FROM public.report_snapshot_cache_v2031),
 (SELECT count(*) FROM public.health_screening_plan_v2023),
 (SELECT count(*) FROM public.health_screening_target_cache_v2030),
 (SELECT count(*) FROM public.health_screening_target_cache_v2030 WHERE screening_plan_date IS DISTINCT FROM v_day),
 v_latest
 )
 ON CONFLICT(day_bkk) DO UPDATE SET
 checked_at=excluded.checked_at,database_bytes=excluded.database_bytes,
 report_cache_bytes=excluded.report_cache_bytes,report_generations=excluded.report_generations,
 report_cache_rows=excluded.report_cache_rows,target_plan_rows=excluded.target_plan_rows,
 target_cache_rows=excluded.target_cache_rows,target_cache_stale_rows=excluded.target_cache_stale_rows,
 target_refresh_latest_status=excluded.target_refresh_latest_status
 RETURNING * INTO v_snapshot;
 DELETE FROM private.cloud_storage_daily_v2076 WHERE day_bkk<v_day-interval '45 days';
 RETURN jsonb_build_object('ok',true,'date',v_day,'database_bytes',v_snapshot.database_bytes,
 'report_generations',v_snapshot.report_generations,'target_cache_rows',v_snapshot.target_cache_rows);
END;
$fn$;
REVOKE ALL ON FUNCTION private.capture_cloud_storage_daily_v2076() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private.capture_cloud_storage_daily_v2076() TO postgres;

CREATE OR REPLACE FUNCTION public.local_admin_retention_status_v2076()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_role text:=coalesce(nullif(current_setting('request.jwt.claim.role',true),''),
  coalesce(nullif(current_setting('request.jwt.claims',true),'{}')::jsonb->>'role',''));
        v_daily_job bigint;v_latest jsonb;v_history jsonb;
        v_today date:=(now() at time zone 'Asia/Bangkok')::date;
BEGIN
 IF v_role<>'service_role' THEN RAISE EXCEPTION 'SERVICE_ROLE_REQUIRED' USING errcode='42501'; END IF;
 SELECT jobid INTO v_daily_job FROM cron.job WHERE jobname='osm-phc-screening-targets-daily-v2075' AND active=true LIMIT 1;
 SELECT jsonb_build_object('status',status,'started_at',start_time,'ended_at',end_time,
  'message',left(coalesce(return_message,''),140))
 INTO v_latest FROM cron.job_run_details WHERE jobid=v_daily_job ORDER BY start_time DESC LIMIT 1;
 SELECT coalesce(jsonb_agg(jsonb_build_object('day',day_bkk,'database_bytes',database_bytes,
  'report_generations',report_generations,'target_cache_rows',target_cache_rows,
  'target_cache_stale_rows',target_cache_stale_rows,'checked_at',checked_at) ORDER BY day_bkk),'[]'::jsonb)
 INTO v_history FROM (SELECT * FROM private.cloud_storage_daily_v2076 ORDER BY day_bkk DESC LIMIT 30) h;
 RETURN jsonb_build_object(
  'checked_at',clock_timestamp(),'database_bytes',pg_database_size(current_database()),
  'database_limit_bytes',524288000,'usage_alert_percent',75,
  'report_cache_bytes',pg_total_relation_size('public.report_snapshot_cache_v2031'::regclass),
  'report_generations',(SELECT count(distinct generation) FROM public.report_snapshot_cache_v2031),
  'report_cache_rows',(SELECT count(*) FROM public.report_snapshot_cache_v2031),
  'report_retention_generations',4,
  'plan_rows',(SELECT count(*) FROM public.health_screening_plan_v2023),
  'plan_stale_rows',(SELECT count(*) FROM public.health_screening_plan_v2023 WHERE plan_date IS DISTINCT FROM v_today),
  'target_rows',(SELECT count(*) FROM public.health_screening_target_cache_v2030),
  'target_stale_rows',(SELECT count(*) FROM public.health_screening_target_cache_v2030 WHERE screening_plan_date IS DISTINCT FROM v_today),
  'daily_target_job_enabled',v_daily_job IS NOT NULL,
  'daily_target_time_bkk','07:10',
  'daily_target_last_run',v_latest,'daily_metrics_time_bkk','07:20',
  'history',v_history,
  'data_policy',jsonb_build_object(
    'jhcis','Local JHCIS remains the source of truth; read-only access from OSM-PHC.',
    'cloud_operational','Current verified houses, scoped person fields, current targets and worklists remain in Cloud.',
    'cloud_screenings','Submitted production screenings, clinical history and unconfirmed synchronizations are not auto-deleted.',
    'report_cache','Cloud retains current and three previous successful derived-report generations.',
    'screening_cache','Cloud holds current screening plan and target cache; do not archive duplicate person-level data automatically.',
    'local_archive','Only aggregate monitoring reports are exported to Local; encrypted Local application backups remain a separate action.',
    'audit','Retain assignment and data-verification audit trails; investigate before any lifecycle pruning.',
    'metrics','Cloud retains 45 days of small, non-personal daily usage snapshots.'
  ));
END;
$fn$;
REVOKE ALL ON FUNCTION public.local_admin_retention_status_v2076() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.local_admin_retention_status_v2076() TO service_role;

SELECT cron.schedule('osm-phc-storage-health-daily-v2076','20 0 * * *',
 $cron$SELECT private.capture_cloud_storage_daily_v2076();$cron$);
