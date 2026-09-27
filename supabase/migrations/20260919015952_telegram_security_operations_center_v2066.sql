
create table if not exists public.security_monitor_state_v2066 (
  rule_key text primary key,
  severity text not null,
  status text not null default 'ok',
  current_value integer not null default 0,
  last_alerted_at timestamptz,
  last_recovered_at timestamptz,
  updated_at timestamptz not null default now(),
  details jsonb not null default '{}'::jsonb
);

alter table public.security_monitor_state_v2066 enable row level security;
revoke all on public.security_monitor_state_v2066 from anon, authenticated;
grant select, insert, update on public.security_monitor_state_v2066 to service_role;

create or replace function private.security_monitor_record_v2066(
  p_rule_key text,
  p_severity text,
  p_current_value integer,
  p_is_alert boolean,
  p_title text,
  p_body text,
  p_action_path text default '',
  p_metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare
  v_prev public.security_monitor_state_v2066%rowtype;
  v_should_alert boolean := false;
begin
  select * into v_prev
  from public.security_monitor_state_v2066
  where rule_key=p_rule_key
  for update;

  if p_is_alert then
    v_should_alert :=
      v_prev.rule_key is null
      or v_prev.status <> 'alert'
      or v_prev.current_value <> coalesce(p_current_value,0)
      or v_prev.last_alerted_at is null
      or v_prev.last_alerted_at < now()-interval '6 hours';

    if v_should_alert then
      perform private.emit_admin_notification_v190(
        'security.'||p_rule_key,
        p_severity,
        p_title,
        p_body,
        p_action_path,
        coalesce(p_metadata,'{}'::jsonb) || jsonb_build_object('rule_key',p_rule_key,'value',coalesce(p_current_value,0)),
        true
      );
    end if;

    insert into public.security_monitor_state_v2066(
      rule_key,severity,status,current_value,last_alerted_at,updated_at,details
    )
    values(
      p_rule_key,p_severity,'alert',coalesce(p_current_value,0),
      case when v_should_alert then now() else v_prev.last_alerted_at end,
      now(),coalesce(p_metadata,'{}'::jsonb)
    )
    on conflict(rule_key) do update set
      severity=excluded.severity,
      status='alert',
      current_value=excluded.current_value,
      last_alerted_at=excluded.last_alerted_at,
      updated_at=now(),
      details=excluded.details;
  else
    if v_prev.rule_key is not null and v_prev.status='alert' then
      perform private.emit_admin_notification_v190(
        'security.'||p_rule_key||'.recovered',
        'success',
        'โ… OSM-PHC Security: เธชเธ–เธฒเธเธฐเธเธฅเธฑเธเน€เธเนเธเธเธเธ•เธด',
        left(p_title||' เธเธฅเธฑเธเน€เธเนเธเธเธเธ•เธดเนเธฅเนเธง',500),
        p_action_path,
        coalesce(p_metadata,'{}'::jsonb) || jsonb_build_object('rule_key',p_rule_key,'value',coalesce(p_current_value,0)),
        true
      );
    end if;

    insert into public.security_monitor_state_v2066(
      rule_key,severity,status,current_value,last_recovered_at,updated_at,details
    )
    values(
      p_rule_key,p_severity,'ok',coalesce(p_current_value,0),
      case when v_prev.rule_key is not null and v_prev.status='alert' then now() else v_prev.last_recovered_at end,
      now(),coalesce(p_metadata,'{}'::jsonb)
    )
    on conflict(rule_key) do update set
      severity=excluded.severity,
      status='ok',
      current_value=excluded.current_value,
      last_recovered_at=excluded.last_recovered_at,
      updated_at=now(),
      details=excluded.details;
  end if;
end;
$$;

revoke all on function private.security_monitor_record_v2066(text,text,integer,boolean,text,text,text,jsonb) from public,anon,authenticated;

create or replace function private.security_monitor_scan_v2066()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_out_scope integer:=0;
  v_dup_pid integer:=0;
  v_orphan_house integer:=0;
  v_locked integer:=0;
  v_sync_stale integer:=0;
  v_health_sync timestamptz;
  v_vol_sync timestamptz;
  v_review integer:=0;
  v_pending integer:=0;
begin
  select count(*)::int into v_out_scope
  from public.health_persons
  where active=true
    and (coalesce(jhcis_typelive,0) not in (1,3) or coalesce(service_population_eligible,false)=false);

  select count(*)::int into v_dup_pid
  from (
    select volunteer_pid
    from public.profiles
    where active=true and role in ('user','staff') and volunteer_pid is not null
    group by volunteer_pid
    having count(*)>1
  ) x;

  select count(*)::int into v_orphan_house
  from public.houses h
  where h.superseded_at is null
    and h.superseded_by is null
    and h.volunteer_pid is not null
    and not exists(
      select 1 from public.volunteers v
      where v.source_pid=h.volunteer_pid and v.active=true
    );

  select count(*)::int into v_locked
  from public.login_security_state
  where locked_until>now();

  select nullif(value->>'synced_at','')::timestamptz into v_health_sync
  from public.app_settings where key='health_target_sync';

  select nullif(value->>'synced_at','')::timestamptz into v_vol_sync
  from public.app_settings where key='volunteer_registry_sync';

  if v_health_sync is null or v_vol_sync is null
     or least(v_health_sync,v_vol_sync) < now()-interval '36 hours' then
    v_sync_stale:=1;
  end if;

  select count(*) filter(where verification_status='review_required')::int,
         count(*) filter(where verification_status='pending_jhcis_create')::int
  into v_review,v_pending
  from public.houses
  where superseded_at is null and superseded_by is null;

  perform private.security_monitor_record_v2066(
    'population_out_of_scope_active','critical',v_out_scope,v_out_scope>0,
    '๐”ด เธเธเธเธฃเธฐเธเธฒเธเธฃเธเธญเธเธเธดเธขเธฒเธกเธขเธฑเธ Active เธเธ Cloud',
    format('เธเธ %s เธฃเธฒเธขเธ—เธตเนเนเธกเนเธเนเธฒเธเธเธดเธขเธฒเธก Type 1/3 + service population เนเธ•เนเธขเธฑเธ active เธ•เนเธญเธเธ•เธฃเธงเธ Full Sync',v_out_scope),
    '',
    jsonb_build_object('definition','typelive 1/3 + nation 99')
  );

  perform private.security_monitor_record_v2066(
    'duplicate_active_volunteer_pid','critical',v_dup_pid,v_dup_pid>0,
    '๐”ด เธเธ volunteer_pid เธเนเธณเนเธเธเธฑเธเธเธต Active',
    format('เธเธ %s PID เธ—เธตเนเธ–เธนเธเธเธนเธเธเธฑเธเธเธฑเธเธเธต user/staff Active เธกเธฒเธเธเธงเนเธฒ 1 เธเธฑเธเธเธต',v_dup_pid),
    '',
    '{}'::jsonb
  );

  perform private.security_monitor_record_v2066(
    'orphan_house_assignment','alert',v_orphan_house,v_orphan_house>0,
    '๐  เธเธเธเนเธฒเธเธเธนเธเธเธฑเธ เธญเธชเธก.เธ—เธตเนเนเธกเน Active',
    format('เธเธ %s เธเนเธฒเธเธเธฑเธเธเธธเธเธฑเธเธ—เธตเน volunteer_pid เนเธกเนเธ•เธฃเธเธเธฑเธเธ—เธฐเน€เธเธตเธขเธ เธญเธชเธก. Active',v_orphan_house),
    '',
    '{}'::jsonb
  );

  perform private.security_monitor_record_v2066(
    'account_locked','alert',v_locked,v_locked>0,
    '๐  เธกเธตเธเธฑเธเธเธตเธ–เธนเธเธฅเนเธญเธเธเธฒเธเธเธฒเธฃ Login เธเธดเธ”เธเนเธณ',
    format('เธเธ“เธฐเธเธตเนเธกเธต %s เธเธฑเธเธเธตเธญเธขเธนเนเนเธเธชเธ–เธฒเธเธฐเธฅเนเธญเธเธเธฑเนเธงเธเธฃเธฒเธง',v_locked),
    '',
    '{}'::jsonb
  );

  perform private.security_monitor_record_v2066(
    'cloud_sync_stale','warning',v_sync_stale,v_sync_stale>0,
    '๐ก Cloud Sync เน€เธเธดเธ 36 เธเธฑเนเธงเนเธกเธ',
    format('Health sync เธฅเนเธฒเธชเธธเธ” %s ยท Volunteer sync เธฅเนเธฒเธชเธธเธ” %s',
      coalesce(to_char(v_health_sync at time zone 'Asia/Bangkok','DD/MM/YYYY HH24:MI'),'เนเธกเนเธเธ'),
      coalesce(to_char(v_vol_sync at time zone 'Asia/Bangkok','DD/MM/YYYY HH24:MI'),'เนเธกเนเธเธ')),
    '',
    jsonb_build_object('health_sync',v_health_sync,'volunteer_sync',v_vol_sync)
  );

  return jsonb_build_object(
    'ok',true,
    'out_of_scope_active',v_out_scope,
    'duplicate_active_volunteer_pid',v_dup_pid,
    'orphan_house_assignment',v_orphan_house,
    'locked_accounts',v_locked,
    'cloud_sync_stale',v_sync_stale,
    'review_required_houses',v_review,
    'pending_jhcis_create_houses',v_pending,
    'checked_at',now()
  );
end;
$$;

revoke all on function private.security_monitor_scan_v2066() from public,anon,authenticated;

create or replace function private.notify_login_lock_v2066()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if new.locked_until is not null
     and new.locked_until>now()
     and (tg_op='INSERT' or old.locked_until is distinct from new.locked_until) then
    perform private.emit_admin_notification_v190(
      'security.login_lock',
      'alert',
      '๐  เธเธฑเธเธเธตเธ–เธนเธเธฅเนเธญเธเธเธฒเธเธเธฒเธฃ Login เธเธดเธ”เธเนเธณ',
      format('เธกเธตเธเธฑเธเธเธตเธ–เธนเธเธฅเนเธญเธเธเธฑเนเธงเธเธฃเธฒเธงเธซเธฅเธฑเธ Login เธเธดเธ” %s เธเธฃเธฑเนเธ เธฃเธฐเธเธเนเธกเนเธชเนเธเธเธทเนเธญเธเธนเนเนเธเนเธซเธฃเธทเธญเธเนเธญเธกเธนเธฅเธฅเธฑเธเธเนเธฒเธ Telegram',new.failed_attempts),
      '',
      jsonb_build_object('failed_attempts',new.failed_attempts,'locked_until',new.locked_until),
      true
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_login_lock_v2066 on public.login_security_state;
create trigger trg_notify_login_lock_v2066
after insert or update of locked_until on public.login_security_state
for each row execute function private.notify_login_lock_v2066();

create or replace function private.notify_profile_privilege_change_v2066()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_name text;
  v_title text;
  v_severity text;
begin
  if tg_op='INSERT' then
    if new.active=true and new.role in ('staff','admin') then
      v_name:=left(coalesce(new.display_name,'เธเธฑเธเธเธตเนเธกเนเธฃเธฐเธเธธเธเธทเนเธญ'),80);
      v_severity:=case when new.role='admin' then 'critical' else 'warning' end;
      v_title:=case when new.role='admin' then '๐”ด เธกเธตเธเธฒเธฃเธชเธฃเนเธฒเธเธเธฑเธเธเธต Admin' else '๐ก เธกเธตเธเธฒเธฃเธชเธฃเนเธฒเธเธเธฑเธเธเธต Staff' end;
      perform private.emit_admin_notification_v190(
        'security.privileged_account_created',v_severity,v_title,
        format('%s ยท role=%s ยท community=%s',v_name,new.role,coalesce(new.community,'โ€”')),
        '',
        jsonb_build_object('user_id',new.user_id,'role',new.role),
        true
      );
    end if;
  elsif old.role is distinct from new.role then
    v_name:=left(coalesce(new.display_name,'เธเธฑเธเธเธตเนเธกเนเธฃเธฐเธเธธเธเธทเนเธญ'),80);
    v_severity:=case when new.role='admin' then 'critical' when new.role='staff' then 'alert' else 'warning' end;
    v_title:=case when new.role='admin' then '๐”ด เธกเธตเธเธฒเธฃเน€เธเธฅเธตเนเธขเธเธชเธดเธ—เธเธดเนเน€เธเนเธ Admin' else '๐  เธกเธตเธเธฒเธฃเน€เธเธฅเธตเนเธขเธ Role เธเธฑเธเธเธต' end;
    perform private.emit_admin_notification_v190(
      'security.role_changed',v_severity,v_title,
      format('%s ยท %s โ’ %s ยท community=%s',v_name,coalesce(old.role,'โ€”'),coalesce(new.role,'โ€”'),coalesce(new.community,'โ€”')),
      '',
      jsonb_build_object('user_id',new.user_id,'old_role',old.role,'new_role',new.role),
      true
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_profile_privilege_change_v2066 on public.profiles;
create trigger trg_notify_profile_privilege_change_v2066
after insert or update of role on public.profiles
for each row execute function private.notify_profile_privilege_change_v2066();

create index if not exists health_audit_line_login_day_v2066_idx
on public.health_audit_log(created_at desc, action)
where action in ('LINE_LOGIN_APPROVE','LINE_OAUTH_LOGIN_APPROVE');
