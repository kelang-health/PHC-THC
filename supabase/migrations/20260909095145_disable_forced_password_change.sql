-- v1.8.8: password changes are user-initiated only.
-- Keep the profile column for backward compatibility, but never use it as an
-- authorization gate and clear legacy flags for every existing account.
begin;

update public.profiles
set must_change_password = false,
    updated_at = now()
where must_change_password = true;

create or replace function private.current_role()
returns text
language sql stable security definer
set search_path = ''
as $$
  select p.role from public.profiles p
  where p.user_id = auth.uid()
    and p.active = true
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
  limit 1
$$;

insert into public.app_settings(key,value)
values ('password_policy',jsonb_build_object(
  'version','1.8.8',
  'forced_change',false,
  'change_available_from_menu',true,
  'user_pin','6-12 digits',
  'staff_admin_min_length',12
))
on conflict(key) do update set value=excluded.value,updated_at=now();

commit;
