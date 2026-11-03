-- Retry transient summary failures within the existing delivery window.
-- Successful deliveries skip HTTP entirely. The Edge Function's integrity,
-- claim, per-recipient deduplication and time-window checks remain unchanged.
create or replace function private.summary_delivery_due_v2191(
  p_period text, p_at timestamptz default now()
) returns boolean language sql stable security definer set search_path='' as $f$
  select coalesce(
    p_period in ('noon','evening')
    and extract(hour from p_at at time zone 'Asia/Bangkok') =
      case when p_period='noon' then 12 else 18 end
    and extract(minute from p_at at time zone 'Asia/Bangkok') <= 20
    and not exists (
      select 1 from private.telegram_summary_deliveries_20261016
      where summary_date=(p_at at time zone 'Asia/Bangkok')::date
        and period=p_period and status='sent'
    ),false);
$f$;
revoke all on function private.summary_delivery_due_v2191(text,timestamptz) from public,anon,authenticated;
grant execute on function private.summary_delivery_due_v2191(text,timestamptz) to service_role;

create or replace function private.invoke_daily_admin_summary_v2136(
  p_period text, p_test boolean default false
) returns integer language plpgsql security definer set search_path='' as $f$
declare v_status integer;
begin
  if p_test then raise exception 'Use authenticated dry_run endpoint; test never sends Telegram'; end if;
  if p_period is null or p_period not in ('noon','evening') then raise exception 'INVALID_PERIOD'; end if;
  if not private.summary_delivery_due_v2191(p_period) then return 204; end if;
  -- This lock only coordinates callers of this wrapper. It is deliberately
  -- different from the Edge RPC claim lock to avoid a cross-request deadlock.
  if not pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtext(
    'summary-invoke-v2191-'||(now() at time zone 'Asia/Bangkok')::date||'-'||p_period
  )) then return 204; end if;
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','15000');
  select (extensions.http_post(
    'https://tgeezbwbrovfyjbeykrj.supabase.co/functions/v1/daily-admin-summary',
    jsonb_build_object('period',p_period)::text,'application/json'
  )).status into v_status;
  perform extensions.http_reset_curlopt();
  if v_status is distinct from 200 then raise exception 'SUMMARY_HTTP_%',coalesce(v_status,0); end if;
  return v_status;
exception when others then
  perform extensions.http_reset_curlopt();
  raise;
end;
$f$;
revoke all on function private.invoke_daily_admin_summary_v2136(text,boolean) from public,anon,authenticated;
grant execute on function private.invoke_daily_admin_summary_v2136(text,boolean) to service_role;

do $f$
declare j record;
begin
  for j in select jobid,jobname from cron.job where jobname in (
    'osm-phc-daily-admin-summary-v2066','osm-phc-morning-admin-summary-v2135'
  ) loop
    perform cron.alter_job(j.jobid,
      schedule => case when j.jobname='osm-phc-daily-admin-summary-v2066'
        then '0,5,10,15,20 11 * * *' else '0,5,10,15,20 5 * * *' end);
  end loop;
end;
$f$;

-- Delivery may have occurred before a worker stopped, so do not replay stale
-- messages or mark them sent. Preserve their original state for manual review.
create table if not exists private.notification_delivery_review_v2191 (
  outbox_id bigint primary key,
  quarantined_at timestamptz not null default now(),
  prior_state jsonb not null,
  reason text not null
);
alter table private.notification_delivery_review_v2191 enable row level security;
revoke all on private.notification_delivery_review_v2191 from public,anon,authenticated;

with stale as (
  select * from private.notification_outbox_v190
  where channel='telegram' and status='sending'
    and created_at < now()-interval '24 hours'
  for update
), saved as (
  insert into private.notification_delivery_review_v2191(outbox_id,prior_state,reason)
  select id,to_jsonb(stale),'Delivery unconfirmed; manual review required; do not replay automatically'
  from stale on conflict(outbox_id) do nothing returning outbox_id
)
update private.notification_outbox_v190 o
set status='failed',attempt_count=greatest(o.attempt_count,5),
    last_error='DELIVERY_UNCONFIRMED_REVIEW_V2191: original state preserved in private review table; no automatic replay'
from saved s where o.id=s.outbox_id;
