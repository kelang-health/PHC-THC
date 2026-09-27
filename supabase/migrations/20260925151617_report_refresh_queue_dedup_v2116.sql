begin;

create or replace function private.process_report_refresh_queue_v2031()
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_result jsonb;
  v_watermark timestamptz:=clock_timestamp();
  v_requested_at timestamptz;
  v_cover_started_at timestamptz;
  v_cover_finished_at timestamptz;
begin
  select min(r.requested_at)
    into v_requested_at
  from public.report_refresh_requests_v2031 r
  where r.processed_at is null;

  if v_requested_at is null then
    return jsonb_build_object('ok',true,'status','idle','version','2.0.116');
  end if;

  -- If another full snapshot started after the queued change (manual/nightly/etc.),
  -- it already includes that change. Mark the queue item complete instead of
  -- rebuilding the same cache again.
  select r.started_at,r.finished_at
    into v_cover_started_at,v_cover_finished_at
  from public.report_snapshot_runs_v2031 r
  where r.status='success'
    and r.started_at>=v_requested_at
  order by r.started_at desc
  limit 1;

  if v_cover_started_at is not null then
    update public.report_refresh_requests_v2031
       set processed_at=clock_timestamp(),result_status='success'
     where processed_at is null
       and requested_at<=v_watermark;

    return jsonb_build_object(
      'ok',true,
      'status','covered_by_newer_snapshot',
      'version','2.0.116',
      'requested_at',v_requested_at,
      'snapshot_started_at',v_cover_started_at,
      'snapshot_finished_at',v_cover_finished_at
    );
  end if;

  v_result:=private.refresh_report_snapshots_v2031('change_queue');

  if coalesce((v_result->>'ok')::boolean,false) then
    update public.report_refresh_requests_v2031
       set processed_at=clock_timestamp(),result_status='success'
     where processed_at is null
       and requested_at<=v_watermark;
  elsif v_result->>'status'='failed' then
    update public.report_refresh_requests_v2031
       set processed_at=clock_timestamp(),result_status='failed'
     where processed_at is null
       and requested_at<=v_watermark;
  end if;

  return v_result;
end;
$function$;

revoke all on function private.process_report_refresh_queue_v2031()
  from public,anon,authenticated,service_role;

insert into public.app_settings(key,value)
values(
  'report_refresh_queue_v2116',
  jsonb_build_object(
    'version','2.0.116',
    'single_pending_queue',true,
    'skip_rebuild_when_newer_snapshot_exists',true,
    'max_refresh_interval_minutes',5
  )
)
on conflict(key) do update
set value=excluded.value,updated_at=now();

commit;
