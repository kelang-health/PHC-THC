
create table if not exists public.daily_system_summary (
  summary_date date primary key,
  timezone text not null default 'Asia/Bangkok',
  active_accounts integer not null default 0,
  active_users integer not null default 0,
  active_staff integer not null default 0,
  signed_in_today integer not null default 0,
  line_connected integer not null default 0,
  line_not_connected integer not null default 0,
  line_connected_today integer not null default 0,
  line_login_users_today integer not null default 0,
  line_login_events_today integer not null default 0,
  generated_at timestamptz not null default now(),
  details jsonb not null default '{}'::jsonb
);

alter table public.daily_system_summary enable row level security;

revoke all on public.daily_system_summary from anon, authenticated;
grant select, insert, update on public.daily_system_summary to service_role;

create or replace function public.admin_daily_system_summary_v2066()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_day date := (now() at time zone 'Asia/Bangkok')::date;
  v_start timestamptz := ((now() at time zone 'Asia/Bangkok')::date::timestamp at time zone 'Asia/Bangkok');
  v_end timestamptz := (((now() at time zone 'Asia/Bangkok')::date + 1)::timestamp at time zone 'Asia/Bangkok');
  v_active_accounts integer := 0;
  v_active_users integer := 0;
  v_active_staff integer := 0;
  v_signed_in_today integer := 0;
  v_line_connected integer := 0;
  v_line_not_connected integer := 0;
  v_line_connected_today integer := 0;
  v_line_login_users_today integer := 0;
  v_line_login_events_today integer := 0;
begin
  if auth.role() <> 'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED';
  end if;

  select
    count(*) filter (where p.role='user')::int,
    count(*) filter (where p.role='staff')::int,
    count(*)::int
  into v_active_users,v_active_staff,v_active_accounts
  from public.profiles p
  where p.active=true and p.role in ('user','staff');

  select count(distinct u.id)::int
  into v_signed_in_today
  from auth.users u
  join public.profiles p on p.user_id=u.id
  where p.active=true
    and p.role in ('user','staff')
    and u.last_sign_in_at >= v_start
    and u.last_sign_in_at < v_end;

  select count(*)::int
  into v_line_connected
  from public.user_line_links l
  join public.profiles p on p.user_id=l.app_user_id
  where l.active=true
    and p.active=true
    and p.role in ('user','staff');

  v_line_not_connected := greatest(v_active_accounts-v_line_connected,0);

  select count(*)::int
  into v_line_connected_today
  from public.user_line_links l
  join public.profiles p on p.user_id=l.app_user_id
  where l.active=true
    and p.active=true
    and p.role in ('user','staff')
    and l.linked_at >= v_start
    and l.linked_at < v_end;

  select
    count(distinct h.operator_id)::int,
    count(*)::int
  into v_line_login_users_today,v_line_login_events_today
  from public.health_audit_log h
  where h.created_at >= v_start
    and h.created_at < v_end
    and h.action in ('LINE_LOGIN_APPROVE','LINE_OAUTH_LOGIN_APPROVE');

  insert into public.daily_system_summary(
    summary_date,timezone,active_accounts,active_users,active_staff,
    signed_in_today,line_connected,line_not_connected,line_connected_today,
    line_login_users_today,line_login_events_today,generated_at,details
  )
  values(
    v_day,'Asia/Bangkok',v_active_accounts,v_active_users,v_active_staff,
    v_signed_in_today,v_line_connected,v_line_not_connected,v_line_connected_today,
    v_line_login_users_today,v_line_login_events_today,now(),
    jsonb_build_object(
      'population','active profiles role user/staff',
      'signin_source','auth.users.last_sign_in_at',
      'line_source','public.user_line_links',
      'line_login_source','public.health_audit_log'
    )
  )
  on conflict(summary_date) do update set
    timezone=excluded.timezone,
    active_accounts=excluded.active_accounts,
    active_users=excluded.active_users,
    active_staff=excluded.active_staff,
    signed_in_today=excluded.signed_in_today,
    line_connected=excluded.line_connected,
    line_not_connected=excluded.line_not_connected,
    line_connected_today=excluded.line_connected_today,
    line_login_users_today=excluded.line_login_users_today,
    line_login_events_today=excluded.line_login_events_today,
    generated_at=excluded.generated_at,
    details=excluded.details;

  return jsonb_build_object(
    'summary_date',v_day,
    'timezone','Asia/Bangkok',
    'active_accounts',v_active_accounts,
    'active_users',v_active_users,
    'active_staff',v_active_staff,
    'signed_in_today',v_signed_in_today,
    'line_connected',v_line_connected,
    'line_not_connected',v_line_not_connected,
    'line_connected_today',v_line_connected_today,
    'line_login_users_today',v_line_login_users_today,
    'line_login_events_today',v_line_login_events_today,
    'generated_at',now()
  );
end;
$$;

revoke all on function public.admin_daily_system_summary_v2066() from public, anon, authenticated;
grant execute on function public.admin_daily_system_summary_v2066() to service_role;
