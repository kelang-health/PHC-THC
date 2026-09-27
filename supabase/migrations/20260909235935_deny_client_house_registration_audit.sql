drop policy if exists house_registration_audit_deny_clients on public.house_registration_audit;
create policy house_registration_audit_deny_clients
on public.house_registration_audit
as restrictive
for all
to anon, authenticated
using (false)
with check (false);
