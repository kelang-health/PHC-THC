
create or replace function private.performance_monitor_scan_v2067()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_started timestamptz:=clock_timestamp();
  v_max integer:=0;
  v_conn integer:=0;
  v_active integer:=0;
  v_lock integer:=0;
  v_q3 integer:=0;
  v_q10 integer:=0;
  v_cron_fail integer:=0;
  v_cron_stuck integer:=0;
  v_pct numeric(6,2):=0;
  v_scan_ms integer:=0;
  v_status text:='ok';
  v_conn_level integer:=0;
  v_lock_level integer:=0;
  v_query_level integer:=0;
  v_cron_level integer:=0;
  v_cron_stuck_level integer:=0;
  v_scan_level integer:=0;
begin
  v_max:=current_setting('max_connections')::int;

  select
    count(*) filter(where datname=current_database())::int,
    count(*) filter(where datname=current_database() and state='active')::int,
    count(*) filter(where datname=current_database() and wait_event_type='Lock')::int,
    count(*) filter(where datname=current_database() and state='active'
      and pid<>pg_backend_pid() and query_start<now()-interval '3 seconds')::int,
    count(*) filter(where datname=current_database() and state='active'
      and pid<>pg_backend_pid() and query_start<now()-interval '10 seconds')::int
  into v_conn,v_active,v_lock,v_q3,v_q10
  from pg_catalog.pg_stat_activity;

  v_pct:=round((100.0*v_conn/greatest(v_max,1))::numeric,2);

  -- Only a terminal FAILED state is a real Cron failure.
  -- RUNNING rows are normal while pg_cron jobs overlap the monitor scan.
  select count(*)::int into v_cron_fail
  from cron.job_run_details
  where start_time>=now()-interval '15 minutes'
    and status='failed';

  -- Detect genuinely stuck jobs separately instead of calling all RUNNING jobs failures.
  select count(*)::int into v_cron_stuck
  from cron.job_run_details
  where status='running'
    and start_time<now()-interval '2 minutes';

  v_conn_level:=case when v_pct>=75 then 2 when v_pct>=50 then 1 else 0 end;
  v_lock_level:=case when v_lock>=3 then 2 when v_lock>=1 then 1 else 0 end;
  v_query_level:=case when v_q10>=1 then 2 when v_q3>=2 then 1 else 0 end;
  v_cron_level:=case when v_cron_fail>=3 then 2 when v_cron_fail>=1 then 1 else 0 end;
  v_cron_stuck_level:=case when v_cron_stuck>=2 then 2 when v_cron_stuck>=1 then 1 else 0 end;

  perform private.security_monitor_record_v2066(
    'performance_connection_pressure',
    case when v_conn_level=2 then 'critical' else 'warning' end,
    v_conn_level,
    v_conn_level>0,
    case when v_conn_level=2 then '๐”ด Cloud DB Connection เธชเธนเธเธกเธฒเธ' else '๐ก Cloud DB Connection เน€เธฃเธดเนเธกเธชเธนเธ' end,
    format('เนเธเน Connection %s/%s (%s%%) ยท Active %s',v_conn,v_max,v_pct,v_active),
    '',
    jsonb_build_object('connections',v_conn,'max_connections',v_max,'connection_pct',v_pct,'active',v_active)
  );

  perform private.security_monitor_record_v2066(
    'performance_lock_wait',
    case when v_lock_level=2 then 'critical' else 'warning' end,
    v_lock_level,
    v_lock_level>0,
    case when v_lock_level=2 then '๐”ด เธเธเธเธฒเธฃเธฃเธญ Lock เธซเธฅเธฒเธขเธฃเธฒเธขเธเธฒเธฃ' else '๐ก เน€เธฃเธดเนเธกเธเธ Query เธฃเธญ Lock' end,
    format('เธกเธต %s connection เธเธณเธฅเธฑเธเธฃเธญ Lock เธเธถเนเธเธญเธฒเธเธ—เธณเนเธซเนเธซเธเนเธฒเธเธญเธ•เธญเธเธชเธเธญเธเธเนเธฒเธฅเธ',v_lock),
    '',
    jsonb_build_object('waiting_on_lock',v_lock)
  );

  perform private.security_monitor_record_v2066(
    'performance_long_query',
    case when v_query_level=2 then 'critical' else 'warning' end,
    v_query_level,
    v_query_level>0,
    case when v_query_level=2 then '๐”ด เธเธ Query เธ—เธณเธเธฒเธเน€เธเธดเธ 10 เธงเธดเธเธฒเธ—เธต' else '๐ก เน€เธฃเธดเนเธกเธเธ Query เธ—เธณเธเธฒเธเธเธฒเธ' end,
    format('Query >3 เธงเธดเธเธฒเธ—เธต %s เธฃเธฒเธขเธเธฒเธฃ ยท >10 เธงเธดเธเธฒเธ—เธต %s เธฃเธฒเธขเธเธฒเธฃ',v_q3,v_q10),
    '',
    jsonb_build_object('over_3s',v_q3,'over_10s',v_q10)
  );

  perform private.security_monitor_record_v2066(
    'performance_cron_failure',
    case when v_cron_level=2 then 'critical' else 'warning' end,
    v_cron_level,
    v_cron_level>0,
    case when v_cron_level=2 then '๐”ด Scheduled jobs เธฅเนเธกเน€เธซเธฅเธงเธซเธฅเธฒเธขเธเธฃเธฑเนเธ' else '๐ก Scheduled job เธกเธตเธเนเธญเธเธดเธ”เธเธฅเธฒเธ”' end,
    format('เธเธ Cron job เธชเธ–เธฒเธเธฐ failed %s เธเธฃเธฑเนเธเนเธ 15 เธเธฒเธ—เธตเธฅเนเธฒเธชเธธเธ”',v_cron_fail),
    '',
    jsonb_build_object('cron_failed_15m',v_cron_fail,'count_policy','terminal_failed_only')
  );

  perform private.security_monitor_record_v2066(
    'performance_cron_stuck',
    case when v_cron_stuck_level=2 then 'critical' else 'warning' end,
    v_cron_stuck_level,
    v_cron_stuck_level>0,
    case when v_cron_stuck_level=2 then '๐”ด Scheduled jobs เธเนเธฒเธเธซเธฅเธฒเธขเธเธฒเธ' else '๐ก Scheduled job เธญเธฒเธเธเนเธฒเธ' end,
    format('เธเธ Cron job เธ—เธตเนเธขเธฑเธ running เน€เธเธดเธ 2 เธเธฒเธ—เธต %s เธเธฒเธ',v_cron_stuck),
    '',
    jsonb_build_object('running_over_2m',v_cron_stuck)
  );

  v_scan_ms:=greatest(0,round(extract(epoch from (clock_timestamp()-v_started))*1000)::int);
  v_scan_level:=case when v_scan_ms>=5000 then 2 when v_scan_ms>=2000 then 1 else 0 end;

  perform private.security_monitor_record_v2066(
    'performance_monitor_latency',
    case when v_scan_level=2 then 'critical' else 'warning' end,
    v_scan_level,
    v_scan_level>0,
    case when v_scan_level=2 then '๐”ด Performance Monitor เธ•เธญเธเธชเธเธญเธเธเนเธฒเธกเธฒเธ' else '๐ก Performance Monitor เน€เธฃเธดเนเธกเธเนเธฒ' end,
    format('เธฃเธญเธเธ•เธฃเธงเธเนเธเนเน€เธงเธฅเธฒ %s ms ยท baseline เน€เธ”เธดเธกเธเธฃเธฐเธกเธฒเธ“ 668 ms',v_scan_ms),
    '',
    jsonb_build_object('scan_ms',v_scan_ms,'warning_ms',2000,'critical_ms',5000)
  );

  v_status:=case
    when greatest(v_conn_level,v_lock_level,v_query_level,v_cron_level,v_cron_stuck_level,v_scan_level)>=2 then 'critical'
    when greatest(v_conn_level,v_lock_level,v_query_level,v_cron_level,v_cron_stuck_level,v_scan_level)=1 then 'warning'
    else 'ok'
  end;

  insert into public.performance_monitor_samples_v2067(
    max_connections,db_connections,active_connections,connection_pct,
    waiting_on_lock,active_over_3s,active_over_10s,cron_failures_15m,
    scan_ms,overall_status,details
  )
  values(
    v_max,v_conn,v_active,v_pct,v_lock,v_q3,v_q10,v_cron_fail,
    v_scan_ms,v_status,
    jsonb_build_object(
      'cron_running_over_2m',v_cron_stuck,
      'thresholds',jsonb_build_object(
        'connections_warning_pct',50,
        'connections_critical_pct',75,
        'lock_warning',1,
        'lock_critical',3,
        'long_query_warning','2 queries >3s',
        'long_query_critical','1 query >10s',
        'cron_failure_policy','status=failed only',
        'cron_stuck_warning','running >2 minutes',
        'scan_warning_ms',2000,
        'scan_critical_ms',5000
      )
    )
  );

  return jsonb_build_object(
    'ok',true,'status',v_status,'scan_ms',v_scan_ms,
    'connections',v_conn,'max_connections',v_max,'connection_pct',v_pct,
    'active_connections',v_active,'waiting_on_lock',v_lock,
    'active_over_3s',v_q3,'active_over_10s',v_q10,
    'cron_failures_15m',v_cron_fail,
    'cron_running_over_2m',v_cron_stuck,
    'checked_at',now()
  );
end;
$$;

revoke all on function private.performance_monitor_scan_v2067() from public,anon,authenticated;

insert into public.app_settings(key,value)
values(
  'performance_early_warning_v2067',
  jsonb_build_object(
    'version','2.0.67',
    'enabled',true,
    'scan_minutes',10,
    'telegram_dispatch_minutes',5,
    'connections_warning_pct',50,
    'connections_critical_pct',75,
    'lock_warning',1,
    'lock_critical',3,
    'long_query_warning','2 active queries >3 seconds',
    'long_query_critical','1 active query >10 seconds',
    'cron_failure_warning','1 terminal failed status in 15 minutes',
    'cron_failure_critical','3 terminal failed statuses in 15 minutes',
    'cron_stuck_warning','running >2 minutes',
    'monitor_warning_ms',2000,
    'monitor_critical_ms',5000,
    'dedupe_hours',6,
    'false_positive_fix','2026-09-19: running jobs are no longer counted as failures'
  )
)
on conflict(key) do update set value=excluded.value;
