-- Synthetic, disposable PostgreSQL 17 grant/RLS contract. Never run on production.
-- Names and rows are fixtures, not real patients, members or borrowers.
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN BYPASSRLS;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- Reproduce OLD default on an isolated database.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO anon, authenticated, service_role;
CREATE TABLE public.phase4_before (id int);
DO $test$ BEGIN
 IF NOT has_table_privilege('anon','public.phase4_before','SELECT') THEN
  RAISE EXCEPTION 'Fixture did not reproduce initial implicit GRANT';
 END IF;
END $test$;

-- Exercise exact candidate SQL as committed in PR, not a hand-edited equivalent.
\i database/phase2/20260924_future_public_table_defaults_candidate.sql

CREATE TABLE public.phase4_health_fixture(
 id text PRIMARY KEY,
 owner_id text NOT NULL,
 label text NOT NULL
);
ALTER TABLE public.phase4_health_fixture ENABLE ROW LEVEL SECURITY;
CREATE POLICY fixture_own_select ON public.phase4_health_fixture
 FOR SELECT TO authenticated
 USING (owner_id = COALESCE(NULLIF(current_setting('request.jwt.claims', true),'')::jsonb->>'sub', NULLIF(current_setting('request.jwt.claim.sub', true),'')));
GRANT SELECT ON TABLE public.phase4_health_fixture TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.phase4_health_fixture TO service_role;
INSERT INTO public.phase4_health_fixture VALUES
 ('fixture-1','test-user-a','synthetic-a'),
 ('fixture-2','test-user-b','synthetic-b');

CREATE TABLE public.phase4_server_only(id int PRIMARY KEY);
ALTER TABLE public.phase4_server_only ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.phase4_server_only TO service_role;

DO $test$ BEGIN
 IF has_table_privilege('anon','public.phase4_health_fixture','SELECT')
 OR has_table_privilege('anon','public.phase4_server_only','SELECT')
 OR has_table_privilege('authenticated','public.phase4_server_only','SELECT') THEN
   RAISE EXCEPTION 'Future table exposed to unauthorized API role';
 END IF;
 IF NOT has_table_privilege('authenticated','public.phase4_health_fixture','SELECT')
 OR NOT has_table_privilege('service_role','public.phase4_health_fixture','SELECT') THEN
   RAISE EXCEPTION 'Explicit per-table GRANT missing';
 END IF;
END $test$;

SET ROLE authenticated;
SET request.jwt.claim.sub='test-user-a';
DO $test$ BEGIN
 IF (SELECT count(*) FROM public.phase4_health_fixture) <> 1 THEN
  RAISE EXCEPTION 'RLS synthetic user A did not see exactly own row';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM public.phase4_health_fixture WHERE id='fixture-1') THEN
  RAISE EXCEPTION 'Synthetic user A own row missing';
 END IF;
END $test$;
SET request.jwt.claim.sub='test-user-b';
DO $test$ BEGIN
 IF (SELECT count(*) FROM public.phase4_health_fixture) <> 1 THEN
  RAISE EXCEPTION 'RLS synthetic user B did not see exactly own row';
 END IF;
 IF EXISTS (SELECT 1 FROM public.phase4_health_fixture WHERE id='fixture-1') THEN
  RAISE EXCEPTION 'Cross-user row exposed';
 END IF;
END $test$;
RESET ROLE;

SET ROLE anon;
DO $test$ BEGIN
 IF has_table_privilege(current_user,'public.phase4_health_fixture','SELECT')
 OR has_table_privilege(current_user,'public.phase4_server_only','SELECT') THEN
  RAISE EXCEPTION 'Anonymous role has private table access';
 END IF;
END $test$;
RESET ROLE;

SET ROLE service_role;
DO $test$ BEGIN
 IF (SELECT count(*) FROM public.phase4_health_fixture) <> 2 THEN
  RAISE EXCEPTION 'Synthetic backend cannot see intended rows';
 END IF;
END $test$;
RESET ROLE;

SELECT 'PASS: isolated PostgreSQL 17 default GRANT, scoped RLS, anon denial and server-only table tests' AS result;
