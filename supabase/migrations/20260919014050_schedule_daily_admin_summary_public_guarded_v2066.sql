
do $$
declare v_jobid bigint;
begin
  select jobid into v_jobid
  from cron.job
  where jobname='osm-phc-daily-admin-summary-v2066';
  if v_jobid is not null then
    perform cron.unschedule(v_jobid);
  end if;
end $$;

select cron.schedule(
  'osm-phc-daily-admin-summary-v2066',
  '0 11 * * *',
  $cron$
    select status
    from extensions.http_post(
      'https://tgeezbwbrovfyjbeykrj.supabase.co/functions/v1/daily-admin-summary',
      '{}'::jsonb
    );
  $cron$
);
