
create or replace function public.admin_morning_operational_status_v2136()
returns jsonb
language sql
stable
security definer
set search_path = public, private, cron, pg_temp
as $$
with bounds as (
  select
    (date_trunc('day', now() at time zone 'Asia/Bangkok') at time zone 'Asia/Bangkok') as day_start,
    ((date_trunc('day', now() at time zone 'Asia/Bangkok') + interval '1 day') at time zone 'Asia/Bangkok') as day_end
),
nightly as (
  select j.status,j.start_time,j.end_time,j.return_message
  from cron.job_run_details j,bounds b
  where j.jobid=2
    and j.start_time>=b.day_start
    and j.start_time<b.day_start+interval '1 hour'
  order by j.start_time desc
  limit 1
),
login_today as (
  select
    count(*)::int as state_rows,
    coalesce(sum(f.failure_count),0)::int as current_failure_count,
    max(f.last_failed_at) as last_failed_at
  from private.cloud_login_failures_v2046 f,bounds b
  where f.last_failed_at>=b.day_start
    and f.last_failed_at<b.day_end
)
select jsonb_build_object(
  'timezone','Asia/Bangkok',
  'nightly_found',exists(select 1 from nightly),
  'nightly_status',coalesce((select status from nightly),'missing'),
  'nightly_ok',coalesce((select status='succeeded' from nightly),false),
  'nightly_started_at',(select start_time from nightly),
  'nightly_finished_at',(select end_time from nightly),
  'nightly_return_message',(select return_message from nightly),
  'login_failed_states_today',coalesce((select state_rows from login_today),0),
  'login_failure_count_today',coalesce((select current_failure_count from login_today),0),
  'login_last_failed_at_today',(select last_failed_at from login_today)
);
$$;

revoke all on function public.admin_morning_operational_status_v2136() from public, anon, authenticated;
grant execute on function public.admin_morning_operational_status_v2136() to service_role;
