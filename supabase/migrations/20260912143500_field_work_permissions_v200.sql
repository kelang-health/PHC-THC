-- OSM-PHC v2.0.0 permission refinement for security-invoker reporting views.
-- These helpers expose only current work-period metadata and no person data.

begin;

grant execute on function private.field_period_start_v200() to authenticated, service_role;

grant execute on function private.field_period_mode_v200() to authenticated, service_role;

commit;
