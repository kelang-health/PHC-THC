-- Cloud account lifecycle: force first password change without exposing service role in browser.
alter table public.profiles
  add column if not exists must_change_password boolean not null default false;

create or replace function public.complete_password_change()
returns void
language sql
security definer
set search_path = ''
as $$
  update public.profiles
  set must_change_password = false,
      updated_at = now()
  where user_id = auth.uid();
$$;

revoke all on function public.complete_password_change() from public;

grant execute on function public.complete_password_change() to authenticated;
