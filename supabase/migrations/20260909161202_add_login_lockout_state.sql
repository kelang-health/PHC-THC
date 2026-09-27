create table if not exists public.login_security_state (
  login_hash text primary key,
  failed_attempts smallint not null default 0 check (failed_attempts between 0 and 5),
  locked_until timestamptz,
  last_failed_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.login_security_state enable row level security;
revoke all on table public.login_security_state from anon, authenticated;
grant all on table public.login_security_state to service_role;

insert into public.app_settings(key,value,updated_at)
values (
  'login_security_policy',
  jsonb_build_object(
    'version','1.8.15',
    'max_failed_attempts',5,
    'lock_minutes',10,
    'idle_timeout_minutes',10,
    'failed_attempt_storage','server_side_hmac_identifier',
    'idle_logout_scope','local'
  ),
  now()
)
on conflict (key) do update set value=excluded.value, updated_at=now();
