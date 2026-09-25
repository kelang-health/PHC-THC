begin;

create or replace function private.notify_nightly_snapshot_success_v2133()
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_day date := (now() at time zone 'Asia/Bangkok')::date;
  v_started timestamptz;
  v_finished timestamptz;
  v_status text;
  v_already_sent boolean := false;
  v_duration_seconds integer;
begin
  if not pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtext('osm-phc-nightly-success-v2133')) then
    return jsonb_build_object('ok',true,'status','busy','day',v_day);
  end if;

  select o.status,o.started_at,o.finished_at
    into v_status,v_started,v_finished
  from private.nightly_snapshot_outcomes_v2077 o
  where o.day_bkk=v_day;

  if v_status is distinct from 'success' or v_finished is null then
    return jsonb_build_object(
      'ok',true,
      'status',case when v_status is null then 'waiting' else v_status end,
      'day',v_day
    );
  end if;

  select exists(
    select 1
    from public.notifications n
    where n.event_type='operations.nightly_snapshot.success'
      and n.metadata->>'processing_day'=v_day::text
  ) into v_already_sent;

  if v_already_sent then
    return jsonb_build_object('ok',true,'status','already_sent','day',v_day,'completed_at',v_finished);
  end if;

  v_duration_seconds := greatest(
    0,
    ceil(extract(epoch from (v_finished-coalesce(v_started,v_finished))))::integer
  );

  perform private.emit_admin_notification_v190(
    'operations.nightly_snapshot.success',
    'success',
    '✅ OSM-PHC ประมวลผลรอบ 00:05 สำเร็จ',
    format(
      'วันที่ %s ประมวลผลรายงานเสร็จเวลา %s น. ใช้เวลา %s วินาที ระบบรายงานพร้อมใช้งาน',
      to_char(v_day,'DD/MM/YYYY'),
      to_char(v_finished at time zone 'Asia/Bangkok','HH24:MI'),
      v_duration_seconds
    ),
    '',
    jsonb_build_object(
      'processing_day',v_day,
      'started_at',v_started,
      'completed_at',v_finished,
      'duration_seconds',v_duration_seconds
    ),
    true
  );

  return jsonb_build_object(
    'ok',true,
    'status','queued',
    'day',v_day,
    'completed_at',v_finished,
    'duration_seconds',v_duration_seconds
  );
end;
$function$;

revoke all on function private.notify_nightly_snapshot_success_v2133()
  from public,anon,authenticated,service_role;

do $schedule$
declare v_job record;
begin
  for v_job in
    select jobid from cron.job
    where jobname='osm-phc-nightly-snapshot-success-v2133'
  loop
    perform cron.unschedule(v_job.jobid);
  end loop;
end;
$schedule$;

select cron.schedule(
  'osm-phc-nightly-snapshot-success-v2133',
  '10-30/5 17 * * *',
  $cron$select private.notify_nightly_snapshot_success_v2133();$cron$
);

insert into public.app_settings(key,value)
values(
  'nightly_snapshot_success_telegram_v2133',
  jsonb_build_object(
    'enabled',true,
    'processing_time_bangkok','00:05',
    'success_checks_bangkok',jsonb_build_array('00:10','00:15','00:20','00:25','00:30'),
    'failure_check_bangkok','00:35',
    'telegram_admin_only',true,
    'contains_personal_data',false,
    'dedupe_by_processing_day',true
  )
)
on conflict(key) do update
set value=excluded.value,updated_at=now();

commit;
