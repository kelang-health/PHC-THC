
create or replace function private.invoke_daily_admin_summary_v2136(p_period text, p_test boolean default false)
returns integer
language plpgsql
security definer
set search_path = private, public, extensions, pg_temp
as $$
declare
  v_status integer;
  v_body jsonb;
begin
  v_body := jsonb_build_object('period', case when p_period='morning' then 'morning' else 'evening' end, 'test', coalesce(p_test,false));
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','15000');
  select (extensions.http_post(
    'https://tgeezbwbrovfyjbeykrj.supabase.co/functions/v1/daily-admin-summary',
    v_body
  )).status into v_status;
  perform extensions.http_reset_curlopt();
  return v_status;
exception when others then
  perform extensions.http_reset_curlopt();
  raise;
end;
$$;

revoke all on function private.invoke_daily_admin_summary_v2136(text,boolean) from public, anon, authenticated;
grant execute on function private.invoke_daily_admin_summary_v2136(text,boolean) to service_role;
