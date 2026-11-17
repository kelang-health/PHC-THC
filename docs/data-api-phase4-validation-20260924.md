# Phase 4 — Migration replay and API validation report (24 Sep 2026)

**Status: isolated PostgreSQL / PostgREST contract PASS; complete historical migration replay BLOCKED. Draft PR only; NO production deploy, db reset, GRANT, RLS, Auth, LINE Login or feature-toggle changes.**

## Verified actions

- Added a version-only historical migration manifest to the draft PR; source migration SQL and real production rows were NOT published in GitHub.
- Inspected the authorized Windows local machine for source migration files and compared their filenames to Supabase recorded migration versions. The comparison reads FILENAMES only and cannot establish script-body identity.
- Added `tests/phase4-migration-inventory.cjs` and a GitHub Actions self-test. It rejects duplicate/invalid versions and detects missing/extra source files. Deployment gate still blocks absent/incomplete `supabase/migrations`.
- Executed `tests/phase4-postgres-grant-rls.sql` on disposable PostgreSQL 17 in GitHub Actions. It reproduced broad OLD default grants in the test DB, ran the EXACT staged default-grant SQL, created NEW synthetic scoped and server-only tables, and verified missing anon grant, explicit authenticated/service grants, two-user row isolation, and backend access.
- Executed `tests/phase4-postgrest-http.cjs` against an ephemeral PostgREST container and synthetic JWTs, on the same disposable database. Anonymous private-table GET and anonymous/authenticated server-only-table GET were rejected; two authenticated synthetic users each retrieved only their own synthetic row.
- First HTTP fixture run exposed that PostgREST supplies JWT subject as `request.jwt.claims` JSON, not the legacy `request.jwt.claim.sub` session setting used in the initial isolated fixture. Corrected the TEST fixture only and reran both repos successfully. No production policy changed.

## What PASS does and does not establish

PASS establishes that the staged SQL and a representative grant+RLS+JWT/PostgREST pattern work on **synthetic** tables with synthetic roles and fake JWTs. It does NOT establish a full Supabase stack replay, that Supabase Dashboard exposes appropriate schemas, that actual production RPC SECURITY DEFINER functions are scope-safe, that user/staff/community policies match business rules, or that real frontend/backend endpoints work with every actual auth mode.

`historical-migration-gate` remains an intentional CI FAIL, not an infrastructure regression. DO NOT bypass it, mark this PR production-ready, or merge candidate SQL to a deploy pipeline.

## Remaining gates to complete Phase 4 safely

1. Recover all historic migrations in a RESTRICTED, non-web-served workspace. Screen for secrets, patient/borrower identifiers and production-data import statements; never push raw unreviewed history to public GitHub.
2. Resolve version collisions and source SQL differences; compare against complete Supabase recorded history and actual schema, and distinguish data import from schema/function/permission migrations. Restore needed structural and synthetic seed equivalents without exporting live person rows into the test DB.
3. Provision an explicitly approved disposable full Supabase stack/project or equivalent compatible local environment. No Supabase preview branch was created because one was not available and creation requires separate cost confirmation. The authorized Windows machine had Node/Git but no discovered Docker/psql/PostgreSQL binary; GitHub Actions provided only a synthetic PostgreSQL/PostgREST fixture.
4. Replay the COMPLETE vetted migration history in sequence on the disposable full stack, validate schema parity, table and sequence grants, RLS, policies, views, RPC EXECUTE and exposed schemas, then run real-app anonymous, ADMIN, STAFF, USER cross-community negative API cases and backend-only LINE Hub/JHCIS work.
5. Only after all tests PASS assess whether early opt-in default privilege change is needed at all; existing tables are unaffected by the upcoming Supabase change, and new tables should have explicit minimal grants in their creation migrations. Deploy the smallest reviewed change, with rollback/forward-fix and smoke tests.

**No real user data was exported for these synthetic checks.** GitHub workflows contain only deliberately disposable, non-production fixture passwords/JWT test secrets.

## Project-specific observed source inventory
- Recorded Supabase migrations: 182 versions.
- Windows source: `D:\\AppServ\\www\\osm-phc\\supabase\\migrations` contains 115 SQL files; 101 versions match recorded history, 81 recorded versions are missing from this local directory, and 14 local versions do not match recorded history. Matching version numbers do NOT establish identical SQL bodies.
- Existing GitHub repository had no complete replayable `supabase/migrations` directory.
- The recorded history contains 96 migrations with literal INSERT INTO matches; treat content as sensitive until reviewed, including any embedded auth/secret/data literals.
- 125 authenticated-callable SECURITY DEFINER functions flagged for independent per-function authorization review.
- GitHub Actions run 35942828411: static-sql-check PASS; isolated-postgres-grant-rls PASS; isolated-postgrest-http PASS; historical-migration-gate FAIL (missing complete source baseline).
- Keep existing Cloud announcements and booking UI paused and JHCIS read-only.
