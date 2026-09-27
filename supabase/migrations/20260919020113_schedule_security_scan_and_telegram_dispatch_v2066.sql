
do $$
declare v bigint;
begin
  select jobid into v from cron.job where jobname='osm-phc-security-scan-v2066';
  if v is not null then perform cron.unschedule(v); end if;
  select jobid into v from cron.job where jobname='osm-phc-telegram-dispatch-v2066';
  if v is not null then perform cron.unschedule(v); end if;
end $$;

select cron.schedule(
  'osm-phc-security-scan-v2066',
  '*/10 * * * *',
  $cron$select private.security_monitor_scan_v2066();$cron$
);

select cron.schedule(
  'osm-phc-telegram-dispatch-v2066',
  '2-59/5 * * * *',
  $cron$
    select status
    from extensions.http_post(
      'https://tgeezbwbrovfyjbeykrj.supabase.co/functions/v1/telegram-outbox-dispatch',
      '{}'::varchar,
      'application/json'::varchar
    );
  $cron$
);
