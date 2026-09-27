-- Keep the privileged row-scope implementation outside the exposed API schema.
alter function public.h7_my_services_v2107(uuid,text,bigint) set schema private;
revoke all on function private.h7_my_services_v2107(uuid,text,bigint) from public,anon;
grant usage on schema private to authenticated;
grant execute on function private.h7_my_services_v2107(uuid,text,bigint) to authenticated;

create function public.h7_my_services_v2107(p_event uuid,p_pcucode text,p_pid bigint)
returns jsonb language sql stable security invoker set search_path='' as $$
  select private.h7_my_services_v2107(p_event,p_pcucode,p_pid);
$$;
revoke all on function public.h7_my_services_v2107(uuid,text,bigint) from public,anon;
grant execute on function public.h7_my_services_v2107(uuid,text,bigint) to authenticated;
