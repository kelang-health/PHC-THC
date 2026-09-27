
do $$
declare v bigint;
begin
  select jobid into v from cron.job where jobname='osm-phc-security-scan-v2066';
  if v is not null then perform cron.unschedule(v); end if;
end $$;

select cron.schedule(
  'osm-phc-security-scan-v2066',
  '*/10 * * * *',
  $cron$
    select private.security_monitor_scan_v2066(),
           private.performance_monitor_scan_v2067();
  $cron$
);
