-- Phase 2 candidate: opt-in Data API grants for FUTURE public tables only.
-- STAGED FOR REVIEW. DO NOT RUN ON PRODUCTION UNTIL:
--   1) the complete historical migration baseline is checked into source control,
--   2) every new public table in migrations has explicit role-specific GRANTs and RLS,
--   3) isolated db reset / branch tests pass, and the current app is regression-tested.
-- Does not REVOKE access to any existing table and does not touch Auth or LINE Login.
-- PostgreSQL default ACLs are scoped per *creating role* and per schema.
--
-- Run each role-specific clause as a database administrator with the required
-- role membership. Avoid broadening grants if your deployment creator differs.
BEGIN;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE SELECT, INSERT, UPDATE, DELETE ON TABLES
  FROM anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
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
