-- Reuse the existing coalescing report queue and its existing scheduled worker.
create or replace function public.service_queue_report_refresh_v2228(p_reason text default 'local_sync')
returns jsonb language plpgsql security invoker set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
 perform private.enqueue_report_refresh_v2074(p_reason);
 return jsonb_build_object('ok',true,'status','queued','refreshed',false);
end $$;
revoke all on function public.service_queue_report_refresh_v2228(text) from public,anon,authenticated;
grant execute on function public.service_queue_report_refresh_v2228(text) to service_role;

