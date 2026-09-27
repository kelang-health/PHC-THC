-- Admin-only diagnostics used by the Local control center.
-- The RPC is callable only with the server-side service_role token.
create or replace function public.local_admin_cloud_diagnostics_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_database_bytes bigint;
  v_storage_bytes bigint;
  v_storage_objects bigint;
  v_public_tables_without_rls integer;
  v_public_views_without_security_invoker integer;
  v_authenticated_security_definer integer;
  v_anon_security_definer integer;
  v_database_limit bigint := 524288000;
  v_storage_limit bigint := 1073741824;
begin
  v_role := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb ->> 'role',
    ''
  );
  if v_role <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;

  v_database_bytes := pg_database_size(current_database());

  select coalesce(sum(
    case
      when coalesce(o.metadata ->> 'size', '') ~ '^[0-9]+$'
      then (o.metadata ->> 'size')::bigint
      else 0
    end
  ), 0), count(*)
  into v_storage_bytes, v_storage_objects
  from storage.objects o;

  select count(*)::integer
  into v_public_tables_without_rls
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind in ('r','p')
    and not c.relrowsecurity;

  select count(*)::integer
  into v_public_views_without_security_invoker
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind = 'v'
    and not coalesce(c.reloptions @> array['security_invoker=true'], false);

  select count(*)::integer
  into v_authenticated_security_definer
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prosecdef
    and pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE');

  select count(*)::integer
  into v_anon_security_definer
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prosecdef
    and pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE');

  return jsonb_build_object(
    'checked_at', now(),
    'plan_reference', 'free',
    'database_bytes', v_database_bytes,
    'database_limit_bytes', v_database_limit,
    'database_percent', round(v_database_bytes * 100.0 / v_database_limit, 2),
    'storage_bytes', v_storage_bytes,
    'storage_limit_bytes', v_storage_limit,
    'storage_percent', round(v_storage_bytes * 100.0 / v_storage_limit, 2),
    'storage_objects', v_storage_objects,
    'public_tables_without_rls', v_public_tables_without_rls,
    'public_views_without_security_invoker', v_public_views_without_security_invoker,
    'authenticated_security_definer_functions', v_authenticated_security_definer,
    'anon_security_definer_functions', v_anon_security_definer,
    'database_level', case when v_database_bytes >= v_database_limit then 'danger' when v_database_bytes >= v_database_limit * 0.75 then 'warn' else 'good' end,
    'storage_level', case when v_storage_bytes >= v_storage_limit then 'danger' when v_storage_bytes >= v_storage_limit * 0.75 then 'warn' else 'good' end
  );
end
$$;

revoke all on function public.local_admin_cloud_diagnostics_v1() from public;

revoke all on function public.local_admin_cloud_diagnostics_v1() from anon;

revoke all on function public.local_admin_cloud_diagnostics_v1() from authenticated;

grant execute on function public.local_admin_cloud_diagnostics_v1() to service_role;
