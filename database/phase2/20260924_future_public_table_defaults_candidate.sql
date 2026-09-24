-- Phase 2 candidate: opt-in Data API grants for FUTURE public tables only.
-- STAGED FOR REVIEW. DO NOT RUN ON PRODUCTION UNTIL:
--   1) the complete historical migration baseline is checked into source control,
--   2) every new public table in migrations has explicit role-specific GRANTs and RLS,
--   3) isolated db reset / branch tests pass, and the current app is regression-tested.
-- Does not REVOKE access to any existing table and does not touch Auth or LINE Login.
-- PostgreSQL default ACLs are scoped per *creating role* and per schema.
-- Connected SQL role is postgres, which has NO membership in supabase_admin.
-- Therefore this candidate ONLY changes postgres-created future public tables.
-- Verify separately how supabase_admin-created tables receive default rights;
-- do not attempt ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin using postgres.
-- Avoid broadening grants if the deployment's creating role differs.
BEGIN;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE SELECT, INSERT, UPDATE, DELETE ON TABLES
  FROM anon, authenticated, service_role;

COMMIT;

-- TEMPLATE FOR A SEPARATE CREATE TABLE MIGRATION (illustration only):
-- CREATE TABLE public.<table_name> (...);
-- ALTER TABLE public.<table_name> ENABLE ROW LEVEL SECURITY;
-- CREATE POLICY ... ON public.<table_name> FOR SELECT TO authenticated
--   USING (<verified_scope_check>);
-- GRANT SELECT ON TABLE public.<table_name> TO authenticated;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.<table_name>
--   TO service_role;  -- only if an authorized server actually needs each operation
-- Do not GRANT to anon unless a documented public-access requirement exists.
-- For identity/serial sequences and RPCs grant USAGE/EXECUTE explicitly as needed.
