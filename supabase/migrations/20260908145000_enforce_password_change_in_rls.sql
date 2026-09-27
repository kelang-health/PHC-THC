-- Enforce first-password-change at the database authorization layer, not only in UI.
create or replace function private.current_role()
returns text
language sql stable security definer
set search_path = ''
as $$
  select p.role from public.profiles p
  where p.user_id = auth.uid()
    and p.active = true
    and p.must_change_password = false
  limit 1
$$;

create or replace function private.current_community()
returns text
language sql stable security definer
set search_path = ''
as $$
  select p.community from public.profiles p
  where p.user_id = auth.uid()
    and p.active = true
    and p.must_change_password = false
  limit 1
$$;

create or replace function private.current_volunteer_pid()
returns bigint
language sql stable security definer
set search_path = ''
as $$
  select p.volunteer_pid from public.profiles p
  where p.user_id = auth.uid()
    and p.active = true
    and p.must_change_password = false
  limit 1
$$;
