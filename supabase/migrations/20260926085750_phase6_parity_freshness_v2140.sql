-- Phase 6 freshness: distinguish last write sync from exact read-only parity verification.
-- No operational house/person rows are changed by this migration.

CREATE OR REPLACE FUNCTION public.admin_daily_system_summary_v2066()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_day date := (now() at time zone 'Asia/Bangkok')::date;
  v_start timestamptz := ((now() at time zone 'Asia/Bangkok')::date::timestamp at time zone 'Asia/Bangkok');
  v_end timestamptz := (((now() at time zone 'Asia/Bangkok')::date + 1)::timestamp at time zone 'Asia/Bangkok');

  v_active_accounts integer:=0;
  v_active_users integer:=0;
  v_active_staff integer:=0;
  v_signed_in_today integer:=0;
  v_line_connected integer:=0;
  v_line_not_connected integer:=0;
  v_line_connected_today integer:=0;
  v_line_login_users_today integer:=0;
  v_line_login_events_today integer:=0;

  v_locked_now integer:=0;
  v_failed_states integer:=0;
  v_security_alerts_today integer:=0;
  v_security_critical_today integer:=0;

  v_work_target integer:=0;
  v_work_complete integer:=0;
  v_work_partial integer:=0;
  v_work_due integer:=0;
  v_follow_open integer:=0;
  v_follow_red integer:=0;
  v_follow_orange integer:=0;

  v_health_active integer:=0;
  v_houses_current integer:=0;
  v_houses_verified integer:=0;
  v_houses_review integer:=0;
  v_houses_pending integer:=0;
  v_active_volunteers integer:=0;
  v_out_scope integer:=0;
  v_dup_pid integer:=0;
  v_orphan_house integer:=0;
  v_health_sync timestamptz;
  v_vol_sync timestamptz;
  v_parity_verified timestamptz;
  v_freshness_at timestamptz;
  v_details jsonb;
begin
  if auth.role()<>'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED';
  end if;

  select
    count(*) filter(where p.role='user')::int,
    count(*) filter(where p.role='staff')::int,
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
    and u.last_sign_in_at>=v_start
    and u.last_sign_in_at<v_end;

  select count(*)::int
  into v_line_connected
  from public.user_line_links l
  join public.profiles p on p.user_id=l.app_user_id
  where l.active=true and p.active=true and p.role in ('user','staff');

  v_line_not_connected:=greatest(v_active_accounts-v_line_connected,0);

  select count(*)::int
  into v_line_connected_today
  from public.user_line_links l
  join public.profiles p on p.user_id=l.app_user_id
  where l.active=true and p.active=true and p.role in ('user','staff')
    and l.linked_at>=v_start and l.linked_at<v_end;

  select count(distinct h.operator_id)::int,count(*)::int
  into v_line_login_users_today,v_line_login_events_today
  from public.health_audit_log h
  where h.created_at>=v_start and h.created_at<v_end
    and h.action in ('LINE_LOGIN_APPROVE','LINE_OAUTH_LOGIN_APPROVE');

  select count(*)::int into v_locked_now
  from public.login_security_state where locked_until>now();

  select count(*)::int into v_failed_states
  from public.login_security_state where failed_attempts>0;

  select
    count(*)::int,
    count(*) filter(where severity='critical')::int
  into v_security_alerts_today,v_security_critical_today
  from public.notifications
  where created_at>=v_start and created_at<v_end
    and event_type like 'security.%'
    and event_type not like '%.recovered';

  select
    coalesce(sum(target),0)::int,
    coalesce(sum(complete),0)::int,
    coalesce(sum(partial),0)::int,
    coalesce(sum(due),0)::int
  into v_work_target,v_work_complete,v_work_partial,v_work_due
  from public.field_work_progress_v200;

  select
    coalesce(sum(total) filter(where status in ('open','in_progress')),0)::int,
    coalesce(sum(total) filter(where status in ('open','in_progress') and priority='red'),0)::int,
    coalesce(sum(total) filter(where status in ('open','in_progress') and priority='orange'),0)::int
  into v_follow_open,v_follow_red,v_follow_orange
  from public.field_followup_progress_v200;

  select count(*)::int into v_health_active
  from public.health_persons where active=true;

  select
    count(*)::int,
    count(*) filter(where verification_status='verified_jhcis')::int,
    count(*) filter(where verification_status='review_required')::int,
    count(*) filter(where verification_status='pending_jhcis_create')::int
  into v_houses_current,v_houses_verified,v_houses_review,v_houses_pending
  from public.houses
  where superseded_at is null and superseded_by is null;

  select count(*)::int into v_active_volunteers
  from public.volunteers where active=true;

  select count(*)::int into v_out_scope
  from public.health_persons
  where active=true
    and (coalesce(jhcis_typelive,0) not in (1,3) or coalesce(service_population_eligible,false)=false);

  select count(*)::int into v_dup_pid
  from (
    select volunteer_pid
    from public.profiles
    where active=true and role in ('user','staff') and volunteer_pid is not null
    group by volunteer_pid having count(*)>1
  ) x;

  select count(*)::int into v_orphan_house
  from public.houses h
  where h.superseded_at is null and h.superseded_by is null
    and h.volunteer_pid is not null
    and not exists(
      select 1 from public.volunteers v
      where v.source_pid=h.volunteer_pid and v.active=true
    );

  select nullif(value->>'synced_at','')::timestamptz into v_health_sync
  from public.app_settings where key='health_target_sync';

  select nullif(value->>'synced_at','')::timestamptz into v_vol_sync
  from public.app_settings where key='volunteer_registry_sync';

  select nullif(value->>'verified_at','')::timestamptz into v_parity_verified
  from public.app_settings where key='phase6_parity_verified';

  v_freshness_at:=greatest(
    coalesce(least(v_health_sync,v_vol_sync),'1970-01-01'::timestamptz),
    coalesce(v_parity_verified,'1970-01-01'::timestamptz)
  );

  v_details:=jsonb_build_object(
    'security',jsonb_build_object(
      'locked_now',v_locked_now,
      'failed_login_states',v_failed_states,
      'alerts_today',v_security_alerts_today,
      'critical_today',v_security_critical_today
    ),
    'operations',jsonb_build_object(
      'target',v_work_target,
      'complete',v_work_complete,
      'partial',v_work_partial,
      'due',v_work_due,
      'followup_open',v_follow_open,
      'followup_red',v_follow_red,
      'followup_orange',v_follow_orange
    ),
    'data_quality',jsonb_build_object(
      'health_active',v_health_active,
      'houses_current',v_houses_current,
      'houses_operational_verified',v_houses_verified,
      'houses_verified',v_houses_verified,
      'houses_review_required',v_houses_review,
      'houses_pending_jhcis_create',v_houses_pending,
      'active_volunteers',v_active_volunteers,
      'out_of_scope_active',v_out_scope,
      'duplicate_active_volunteer_pid',v_dup_pid,
      'orphan_house_assignment',v_orphan_house
    ),
    'sync',jsonb_build_object(
      'health_synced_at',v_health_sync,
      'volunteer_synced_at',v_vol_sync,
      'parity_verified_at',v_parity_verified,
      'freshness_at',v_freshness_at,
      'freshness_basis',case when v_parity_verified is not null and v_parity_verified>=coalesce(least(v_health_sync,v_vol_sync),'1970-01-01'::timestamptz) then 'parity_verification' else 'write_sync' end,
      'stale_36h',(v_freshness_at<now()-interval '36 hours')
    ),
    'population','active profiles role user/staff',
    'signin_source','auth.users.last_sign_in_at',
    'line_source','public.user_line_links'
  );

  insert into public.daily_system_summary(
    summary_date,timezone,active_accounts,active_users,active_staff,
    signed_in_today,line_connected,line_not_connected,line_connected_today,
    line_login_users_today,line_login_events_today,generated_at,details
  )
  values(
    v_day,'Asia/Bangkok',v_active_accounts,v_active_users,v_active_staff,
    v_signed_in_today,v_line_connected,v_line_not_connected,v_line_connected_today,
    v_line_login_users_today,v_line_login_events_today,now(),v_details
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
    'details',v_details,
    'generated_at',now()
  );
end;
$function$
;
