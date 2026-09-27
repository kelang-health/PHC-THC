create policy health_person_residence_events_no_direct_access
on public.health_person_residence_events
as restrictive
for all
to authenticated
using (false)
with check (false);

revoke all on function public.complete_password_change() from public, anon;
grant execute on function public.complete_password_change() to authenticated;

revoke all on function public.rls_auto_enable() from public, anon, authenticated;
grant execute on function public.rls_auto_enable() to service_role;
