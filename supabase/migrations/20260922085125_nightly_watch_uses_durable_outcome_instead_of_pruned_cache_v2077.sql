CREATE OR REPLACE FUNCTION private.monitor_nightly_snapshot_v2068()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_day date:=(now() at time zone 'Asia/Bangkok')::date;
  v_local_clock timestamp:=(now() at time zone 'Asia/Bangkok');
  v_start timestamptz;
  v_success timestamptz;
  v_previous text;
  v_last_success timestamptz;
  v_result text;
  v_outcome text;
  v_outcome_error text;
begin
  if not pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtext('osm-phc-nightly-watch-v2068')) then
    return jsonb_build_object('ok',true,'status','busy','day',v_day);
  end if;
  -- Do not alarm before the scheduled 00:05 run and its 30-minute grace period.
  if v_local_clock::time < time '00:35' then
    return jsonb_build_object('ok',true,'status','pending','day',v_day);
  end if;
  v_start:=v_day::timestamp at time zone 'Asia/Bangkok';
  -- Independent daily outcome; successful cache generations may be pruned.
  select o.status,o.finished_at,o.error_message
  into v_outcome,v_success,v_outcome_error
  from private.nightly_snapshot_outcomes_v2077 o
  where o.day_bkk=v_day;
  if v_outcome IS DISTINCT FROM 'success' then v_success:=null; end if;

  select w.status into v_previous
  from private.nightly_snapshot_watch_v2068 w
  where w.run_date=v_day for update;

  if v_outcome='unverified' then
    -- A historical pg_cron success cannot prove a refresh function succeeded:
    -- its old detailed result was pruned. Do not claim either failure or success.
    if v_previous='alert' then
      perform private.emit_admin_notification_v190(
        'operations.nightly_snapshot.legacy_audit_gap','warning',
        'OSM-PHC: เนเธเนเนเธเธชเธ–เธฒเธเธฐเนเธเนเธเน€เธ•เธทเธญเธเธฃเธญเธ 00:05',
        format('เธฃเธญเธเธงเธฑเธเธ—เธตเน %s pg_cron เธ—เธณเธเธฒเธเธเธ เนเธ•เนเธเธฃเธฐเธงเธฑเธ•เธดเธเธฅเธฃเธฒเธขเธเธฒเธเธฃเธธเนเธเน€เธเนเธฒเธ–เธนเธเธฅเธเธเนเธญเธเธเธฒเธฃเธ•เธฃเธงเธเธเนเธณ เธเธถเธเธขเธทเธเธขเธฑเธเธเธฅเธชเธณเน€เธฃเนเธเธซเธฃเธทเธญเธฅเนเธกเน€เธซเธฅเธงเธขเนเธญเธเธซเธฅเธฑเธเนเธกเนเนเธ”เน เธเธ“เธฐเธเธตเนเนเธขเธเน€เธเนเธเธเธฅเธฃเธฒเธขเธเธทเธเนเธฅเนเธง',
          to_char(v_day,'DD/MM/YYYY')),
        '',
        jsonb_build_object('processing_day',v_day,'reason','historical_outcome_pruned'),
        true
      );
    end if;
    insert into private.nightly_snapshot_watch_v2068(run_date,status,checked_at)
    values(v_day,'unverified',now())
    on conflict(run_date) do update set status='unverified',checked_at=now();
    return jsonb_build_object('ok',true,'status','unverified_legacy','day',v_day);
  end if;

  if v_success is not null then
    if v_previous='alert' then
      perform private.emit_admin_notification_v190(
        'operations.nightly_snapshot.recovered','success',
        'โ… OSM-PHC เธเธฃเธฐเธกเธงเธฅเธเธฅเธฃเธฒเธขเธเธทเธเธเธฅเธฑเธเธกเธฒเธชเธณเน€เธฃเนเธ',
        format('เธฃเธญเธ 00:05 เธงเธฑเธเธ—เธตเน %s เธชเธณเน€เธฃเนเธเนเธฅเนเธงเน€เธกเธทเนเธญ %s เธ.',
          to_char(v_day,'DD/MM/YYYY'),
          to_char(v_success at time zone 'Asia/Bangkok','HH24:MI')),
        '',
        jsonb_build_object('processing_day',v_day,'completed_at',v_success),
        true
      );
    end if;
    insert into private.nightly_snapshot_watch_v2068(run_date,status,checked_at,recovered_at)
    values(v_day,'ok',now(),case when v_previous='alert' then now() else null end)
    on conflict(run_date) do update
    set status='ok',checked_at=now(),
        recovered_at=coalesce(private.nightly_snapshot_watch_v2068.recovered_at,excluded.recovered_at);
    v_result:='ok';
  else
    if v_previous is distinct from 'alert' then
      select max(o.finished_at) into v_last_success
      from private.nightly_snapshot_outcomes_v2077 o
      where o.status='success';
      perform private.emit_admin_notification_v190(
        'operations.nightly_snapshot.missing','warning',
        '๐ก OSM-PHC เนเธกเนเธเธเธเธฅเธเธฃเธฐเธกเธงเธฅเธเธฅเธฃเธญเธ 00:05',
        format('เธฃเธญเธเธงเธฑเธเธ—เธตเน %s เธขเธฑเธเนเธกเนเธเธเธเธฅเธชเธณเน€เธฃเนเธ เธ“ เน€เธงเธฅเธฒ %s เธ. เธเธฅเธชเธณเน€เธฃเนเธเธเธฃเธฑเนเธเธเนเธญเธ %s เธเธฃเธธเธ“เธฒเธ•เธฃเธงเธเธชเธญเธ Scheduled Job',
          to_char(v_day,'DD/MM/YYYY'),
          to_char(v_local_clock,'HH24:MI'),
          coalesce(to_char(v_last_success at time zone 'Asia/Bangkok','DD/MM/YYYY HH24:MI'),'เนเธกเนเธเธ')),
        '',
        jsonb_build_object('processing_day',v_day,'last_nightly_success',v_last_success),
        true
      );
    end if;
    insert into private.nightly_snapshot_watch_v2068(run_date,status,checked_at,alert_sent_at)
    values(v_day,'alert',now(),now())
    on conflict(run_date) do update set
      status='alert',checked_at=now(),
      alert_sent_at=coalesce(private.nightly_snapshot_watch_v2068.alert_sent_at,excluded.alert_sent_at);
    v_result:='alert';
  end if;
  return jsonb_build_object('ok',true,'status',v_result,'day',v_day,
    'nightly_success_at',v_success,'checked_at',now());
end;
$function$;
