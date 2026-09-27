-- v2.1.44 Local reporting sync probe.
-- One lightweight read-only RPC for the Local admin to decide whether a manual sync is needed.
begin;

create or replace function private.tracking_sync_probe_v2144()
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
select jsonb_build_object(
  'generated_at',now(),
  'screening_sessions',jsonb_build_object(
    'count',(select count(*) from public.screening_sessions),
    'marker',(select max(updated_at) from public.screening_sessions)
  ),
  'health_ncd_screenings',jsonb_build_object(
    'count',(select count(*) from public.health_ncd_screenings),
    'marker',(select max(recorded_at) from public.health_ncd_screenings)
  ),
  'health_growth_screenings',jsonb_build_object(
    'count',(select count(*) from public.health_growth_screenings),
    'marker',(select max(created_at) from public.health_growth_screenings)
  ),
  'child_development_screenings',jsonb_build_object(
    'count',(select count(*) from public.child_development_screenings),
    'marker',(select max(created_at) from public.child_development_screenings)
  ),
  'mental_health_2q_screenings_v206',jsonb_build_object(
    'count',(select count(*) from public.mental_health_2q_screenings_v206),
    'marker',(select max(updated_at) from public.mental_health_2q_screenings_v206)
  ),
  'elderly9_domain_results',jsonb_build_object(
    'count',(select count(*) from public.elderly9_domain_results),
    'marker',(select max(updated_at) from public.elderly9_domain_results)
  ),
  'screening_followups',jsonb_build_object(
    'count',(select count(*) from public.screening_followups),
    'marker',(select max(updated_at) from public.screening_followups)
  )
);
$$;

revoke all on function private.tracking_sync_probe_v2144() from public,anon,authenticated;
grant execute on function private.tracking_sync_probe_v2144() to service_role;

comment on function private.tracking_sync_probe_v2144() is
  'Read-only one-call count/marker probe for manual Cloud->Local reporting sync. No row data returned.';

commit;
