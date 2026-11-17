-- Phase 2 read-only verification: PostgreSQL catalog, no row-level patient data.
-- Run in each Supabase project's SQL Editor. Do not alter grants based on this
-- report alone: compare with documented API usage, RLS policies and exposed schemas.

-- 1) Effective public-table privileges for Data API roles, RLS and policy count.
SELECT
  n.nspname AS schema_name, c.relname AS table_name,
  c.relrowsecurity AS rls_enabled,
  (SELECT count(*) FROM pg_policies p
   WHERE p.schemaname=n.nspname AND p.tablename=c.relname) AS policy_count,
  has_table_privilege('anon',c.oid,'SELECT') AS anon_select,
  has_table_privilege('anon',c.oid,'INSERT') AS anon_insert,
  has_table_privilege('anon',c.oid,'UPDATE') AS anon_update,
  has_table_privilege('anon',c.oid,'DELETE') AS anon_delete,
  has_table_privilege('authenticated',c.oid,'SELECT') AS authenticated_select,
  has_table_privilege('authenticated',c.oid,'INSERT') AS authenticated_insert,
  has_table_privilege('authenticated',c.oid,'UPDATE') AS authenticated_update,
  has_table_privilege('authenticated',c.oid,'DELETE') AS authenticated_delete,
  has_table_privilege('service_role',c.oid,'SELECT') AS service_role_select,
  has_table_privilege('service_role',c.oid,'INSERT') AS service_role_insert,
  has_table_privilege('service_role',c.oid,'UPDATE') AS service_role_update,
  has_table_privilege('service_role',c.oid,'DELETE') AS service_role_delete
FROM pg_class c
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relkind IN ('r','p')
ORDER BY c.relname;

-- 2) Views: security_invoker must be checked independently of table RLS.
SELECT c.relname AS view_name, c.reloptions,
       has_table_privilege('anon',c.oid,'SELECT') AS anon_select,
       has_table_privilege('authenticated',c.oid,'SELECT') AS authenticated_select
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relkind='v'
ORDER BY c.relname;

-- 3) Creator-scoped default privileges: catalog values may differ by creator.
SELECT d.defaclrole::regrole::text AS creating_role,
       COALESCE(n.nspname,'<global>') AS default_schema,
       d.defaclobjtype AS object_type,
       d.defaclacl::text AS default_acl
FROM pg_default_acl d
LEFT JOIN pg_namespace n ON n.oid=d.defaclnamespace
WHERE n.nspname='public' OR n.nspname IS NULL
ORDER BY 1,2,3;

-- 4) Check whether the connected SQL role can change the defaults proposed.
SELECT current_user AS sql_role,
       pg_has_role(current_user,'postgres','MEMBER') AS can_manage_postgres_defaults,
       pg_has_role(current_user,'supabase_admin','MEMBER') AS can_manage_supabase_admin_defaults;

-- 5) SECURITY DEFINER functions need case-by-case review of identity/scope.
SELECT p.proname AS function_name,
       pg_get_function_identity_arguments(p.oid) AS arguments,
       has_function_privilege('anon',p.oid,'EXECUTE') AS anon_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prosecdef
  AND (has_function_privilege('anon',p.oid,'EXECUTE')
       OR has_function_privilege('authenticated',p.oid,'EXECUTE'))
ORDER BY p.proname,arguments;

-- Dashboard → Data API → Exposed Schemas must be verified separately.
-- has_schema_privilege(...) alone does not establish API schema exposure.
