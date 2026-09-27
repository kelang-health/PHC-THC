select pg_advisory_xact_lock(hashtext('osm_phc_report_snapshot_v2031'));

do $$
declare
  v_def text;
  v_new text;
  v_old text := 'and coalesce(r.finished_at,r.started_at)<now()-interval ''7 days''';
begin
  v_def := pg_get_functiondef('private.refresh_report_snapshots_v2031(text)'::regprocedure);
  if strpos(v_def, v_old) = 0 then
    raise exception 'Expected v2031 7-day retention predicate not found; aborting migration';
  end if;

  v_new := replace(v_def, v_old, '');
  execute v_new;
end
$$;

with keep as (
  select id
  from public.report_snapshot_runs_v2031
  where status = 'success'
  order by finished_at desc nulls last
  limit 4
)
delete from public.report_snapshot_runs_v2031 r
where r.status <> 'running'
  and not exists (select 1 from keep k where k.id = r.id);
