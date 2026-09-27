-- v2.1.37 governance hardening: remove inherited PUBLIC execute from internal SECURITY DEFINER functions.
-- No function body, trigger, RLS policy, or row data is changed.

begin;

revoke all on function private.mark_assignment_summary_dirty_v2058() from public, anon, authenticated;
revoke all on function private.notify_profile_privilege_change_v2066() from public, anon, authenticated;
revoke all on function private.refresh_assignment_summary_after_report_v2058() from public, anon, authenticated;
revoke all on function private.refresh_assignment_summary_cache_v2058(text) from public, anon, authenticated;
revoke all on function private.set_boundary_geom() from public, anon, authenticated;
revoke all on function private.set_house_geom() from public, anon, authenticated;
revoke all on function private.sync_screening_target_cache_person_v2030() from public, anon, authenticated;

grant execute on function private.refresh_assignment_summary_cache_v2058(text) to service_role;

commit;
