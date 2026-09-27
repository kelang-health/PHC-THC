-- Cloud v2.0.45 / database component v2.0.46
-- 1. Queue a Telegram admin notification when a field-created house is added.
-- 2. Count verified Cloud password failures without storing login identifiers or passwords.

begin;

create table if not exists private.cloud_login_failures_v2046 (
  login_hash text primary key check (login_hash ~ '^[0-9a-f]{64}$'),
  source_hash text not null check (source_hash ~ '^[0-9a-f]{64}$'),
  login_label text not null default 'เธเธฑเธเธเธต Cloud',
  failure_count integer not null default 0 check (failure_count >= 0),
  window_started_at timestamptz not null default now(),
  last_failed_at timestamptz not null default now(),
  alerted_at timestamptz
);

revoke all on private.cloud_login_failures_v2046 from public, anon, authenticated;

grant usage on schema private to service_role;

grant select, insert, update, delete on private.cloud_login_failures_v2046 to service_role;

-- The caller is the Edge Function's service client. Keep this wrapper invoker-rights
-- and grant only service_role; the existing private emitter remains non-public.
grant execute on function private.emit_admin_notification_v190(text,text,text,text,text,jsonb,boolean) to service_role;

create or replace function public.record_cloud_login_failure_v2046(
  p_login_hash text,
  p_source_hash text,
  p_login_label text default 'เธเธฑเธเธเธต Cloud'
) returns jsonb
language plpgsql
security invoker
set search_path=''
as $$
declare
  v_count integer;
  v_started timestamptz;
  v_alerted timestamptz;
  v_label text := left(coalesce(nullif(btrim(p_login_label),''),'เธเธฑเธเธเธต Cloud'),80);
begin
  if coalesce(p_login_hash,'') !~ '^[0-9a-f]{64}$'
     or coalesce(p_source_hash,'') !~ '^[0-9a-f]{64}$' then
    raise exception 'INVALID_LOGIN_MONITOR_HASH';
  end if;

  delete from private.cloud_login_failures_v2046
   where last_failed_at < now() - interval '24 hours';

  insert into private.cloud_login_failures_v2046 as f(
    login_hash,source_hash,login_label,failure_count,window_started_at,last_failed_at,alerted_at
  ) values (
    p_login_hash,p_source_hash,v_label,1,now(),now(),null
  )
  on conflict(login_hash) do update set
    source_hash=excluded.source_hash,
    login_label=excluded.login_label,
    failure_count=case
      when f.window_started_at < now() - interval '10 minutes' then 1
      else f.failure_count + 1
    end,
    window_started_at=case
      when f.window_started_at < now() - interval '10 minutes' then now()
      else f.window_started_at
    end,
    last_failed_at=now(),
    alerted_at=case
      when f.window_started_at < now() - interval '10 minutes' then null
      else f.alerted_at
    end
  returning failure_count,window_started_at,alerted_at
       into v_count,v_started,v_alerted;

  if v_count >= 3 and v_alerted is null then
    perform private.emit_admin_notification_v190(
      'security.cloud_login_failed',
      'alert',
      'OSM-PHC: เธฅเนเธญเธเธญเธดเธ Cloud เธเธดเธ”เน€เธเธดเธ 2 เธเธฃเธฑเนเธ',
      format('เธ•เธฃเธงเธเธเธเธเธฒเธฃเธเธฃเธญเธเธฃเธซเธฑเธชเธเนเธฒเธเนเธกเนเธ–เธนเธเธ•เนเธญเธ %s เธเธฃเธฑเนเธเธ เธฒเธขเนเธ 10 เธเธฒเธ—เธต เธชเธณเธซเธฃเธฑเธ %s เธเธฃเธธเธ“เธฒเธ•เธฃเธงเธเธชเธญเธเธเธงเธฒเธกเธเธฅเธญเธ”เธ เธฑเธขเธเธญเธเธเธฑเธเธเธต',v_count,v_label),
      '?view=admin',
      jsonb_build_object(
        'attempts',v_count,
        'window_started_at',v_started,
        'login_ref',left(p_login_hash,12),
        'source_ref',left(p_source_hash,12)
      ),
      true
    );
    update private.cloud_login_failures_v2046
       set alerted_at=now()
     where login_hash=p_login_hash;
    v_alerted:=now();
  end if;

  return jsonb_build_object(
    'attempts',v_count,
    'threshold',3,
    'window_seconds',600,
    'alerted',v_alerted is not null
  );
end;
$$;

revoke all on function public.record_cloud_login_failure_v2046(text,text,text) from public,anon,authenticated;

grant execute on function public.record_cloud_login_failure_v2046(text,text,text) to service_role;

create or replace function public.clear_cloud_login_failures_v2046(p_login_hash text)
returns void
language sql
security invoker
set search_path=''
as $$
  delete from private.cloud_login_failures_v2046
   where login_hash=p_login_hash
$$;

revoke all on function public.clear_cloud_login_failures_v2046(text) from public,anon,authenticated;

grant execute on function public.clear_cloud_login_failures_v2046(text) to service_role;

create or replace function private.notify_new_field_house_v2046()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_house public.houses%rowtype;
begin
  if new.action <> 'add' then return new; end if;
  select * into v_house from public.houses where id=new.house_id;
  if not found or v_house.entry_source <> 'field' then return new; end if;

  perform private.emit_admin_notification_v190(
    'house.created',
    'warning',
    'OSM-PHC: เธกเธตเธเธฒเธฃเน€เธเธดเนเธกเธเนเธฒเธเน€เธฅเธเธ—เธตเนเนเธซเธกเน',
    format(
      'เน€เธเธดเนเธกเธเนเธฒเธเน€เธฅเธเธ—เธตเน %s เธซเธกเธนเน %s เธเธธเธกเธเธ %s เธเนเธฒเธเธฃเธฐเธเธเธ เธฒเธเธชเธเธฒเธก เธเธฃเธธเธ“เธฒเน€เธเธดเธ”เธฃเธฐเธเธเน€เธเธทเนเธญเธ•เธฃเธงเธเธชเธญเธ',
      coalesce(nullif(v_house.house_no,''),'เนเธกเนเธฃเธฐเธเธธ'),
      coalesce(nullif(v_house.moo,''),'เนเธกเนเธฃเธฐเธเธธ'),
      coalesce(nullif(v_house.community,''),'เนเธกเนเธฃเธฐเธเธธ')
    ),
    '?view=communities',
    jsonb_build_object(
      'house_id',v_house.id,
      'community',v_house.community,
      'moo',v_house.moo,
      'created_by_role',new.role
    ),
    true
  );
  return new;
end;
$$;

revoke all on function private.notify_new_field_house_v2046() from public,anon,authenticated,service_role;

drop trigger if exists trg_notify_new_field_house_v2046 on public.house_registration_audit;

create trigger trg_notify_new_field_house_v2046
after insert on public.house_registration_audit
for each row when (new.action='add')
execute function private.notify_new_field_house_v2046();

insert into public.app_settings(key,value)
values('security_notification_v2046',jsonb_build_object(
  'version','2.0.46',
  'new_field_house_telegram',true,
  'cloud_login_failure_telegram',true,
  'cloud_login_failure_threshold',3,
  'cloud_login_failure_window_seconds',600,
  'stores_password',false,
  'stores_raw_login',false,
  'stores_raw_ip',false
))
on conflict(key) do update set value=excluded.value,updated_at=now();

notify pgrst,'reload schema';

commit;
