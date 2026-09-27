
select cron.alter_job(
  6,
  command => $cron_command$
do $dispatcher$
declare
  v_http_status integer;
begin
  -- Do not make a network call when no Telegram message is due.
  if exists (
    select 1
    from private.notification_outbox_v190 o
    where o.channel='telegram'
      and o.status in ('queued','failed')
      and o.next_attempt_at <= now()
      and o.attempt_count < 5
  ) then
    perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS'::varchar,'12000'::varchar);
    begin
      select h.status into v_http_status
      from extensions.http_post(
        'https://tgeezbwbrovfyjbeykrj.supabase.co/functions/v1/telegram-outbox-dispatch',
        '{}'::varchar,
        'application/json'::varchar
      ) h;
      perform extensions.http_reset_curlopt();
      if v_http_status is null or v_http_status not between 200 and 299 then
        raise exception 'Telegram dispatcher returned HTTP status %',coalesce(v_http_status,0);
      end if;
    exception when others then
      perform extensions.http_reset_curlopt();
      raise;
    end;
  end if;
end
$dispatcher$;
$cron_command$
);
