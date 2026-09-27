drop policy if exists login_security_state_deny_clients on public.login_security_state;
create policy login_security_state_deny_clients
on public.login_security_state
as restrictive
for all
to anon, authenticated
using (false)
with check (false);
