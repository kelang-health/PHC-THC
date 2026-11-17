# Phase 3 — Data API readiness verification (24 Sep 2026)

**Outcome:** static SQL/fixture checks passed in GitHub Actions. **NOT production-ready.** Deployment gate intentionally blocks because the repository has no complete `supabase/migrations` baseline and no Supabase preview branch was available for a clean rebuild. No production SQL was executed; no app, Auth, LINE Login, or booking/announcement toggle changed.

## Tested and observed

- Inspected production PostgreSQL catalog with read-only SELECT, not patient or borrower records.
- All existing public tables have RLS enabled; no anon SELECT grant on an RLS-disabled public table.
- All existing 22 OSM-PHC public views use `security_invoker=true`; a view-level anon SQL grant is **not** proof of actual readable data, and underlying table grants/RLS must remain protected.
- OSM-PHC: health_persons, houses, health_ncd_screenings, cloud_event_bookings_v2085 lack anon SELECT. H7 eligibility/rules snapshot tables allow service role SELECT but not anon/authenticated SELECT.
- med-device-sharing: the only tables with permissive anon SELECT RLS policies are public_content and public_dashboard_stats. Server-only verification and meter tables lack anon/auth SELECT.
- Zero anonymous-callable public SECURITY DEFINER functions in both projects, but OSM-PHC has 125 signed-in-callable SECURITY DEFINER functions requiring separate code/scope review. Catalog-only results do not prove RPC authorization or actual HTTP behavior.
- The static checker initially failed due to a false positive: UPDATE/INSERT/DELETE privilege names within REVOKE were mistaken for DML. Updated it to require the candidate SQL to contain exactly BEGIN, ALTER DEFAULT PRIVILEGES for postgres/public, and COMMIT. Subsequent GitHub Actions static-sql-check **passed in both projects**.
- Historical migration gate **blocked in both projects**, as designed: `supabase/migrations` is absent. This is a missing-test-input result, not a database privilege regression.
- Actual Data API exposed schema configuration, authenticated HTTP tests, fresh branch/database reset, and role-scoped row authorization remain unverified; do not call this an end-to-end pass.

## How to finish the isolated validation safely

1. Reconstruct all recorded migrations as vetted SQL files in a **restricted** source/location (do not auto-publish secrets/PII or copy live records). Verify SQL sequence and compare clean-schema output with current production; recorded database migrations may not be faithfully replayable without editorial reconciliation.
2. Select an approved isolated Postgres/Supabase test target, resolving any branch cost/organization approval separately. Do not run `supabase db reset` on the production project.
3. Replay the complete migrations in isolation; verify table grants, RLS, ownership, default privileges, sequences, RPC EXECUTE and security_invoker. Test role-based API endpoints with synthetic users, including denial for anon and cross-community access.
4. Confirm the project Dashboard Data API exposed schemas explicitly; SQL `has_schema_privilege` is not evidence of Dashboard exposure.
5. Execute the staged default-privilege candidate only after migration replay/grant checks pass, in an approved change window with backup and rollback/forward-fix instructions. SQL role postgres cannot manage supabase_admin default ACL.
6. Recheck production catalog and application smoke tests. Keep paused public announcements/bookings paused unless separately authorized.

## Change boundary

This phase only adds tests, offline workflow and documentation to the draft PR branch. Do not merge/promote the candidate SQL automatically. No service-role secret or real patient data is part of this test.

## Project-specific checkpoints
Production reference tgeezbwbrovfyjbeykrj: 56 public tables, 22 views, 182 migration history records, 16 public RLS-enabled/no-policy tables intended for server-only review. Security Definer RPCs and health data are not approved for anon access. Keep H7 Cloud announcements and booking disabled as already configured.

GitHub Actions re-run: static-sql-check=success; historical-migration-gate=failure (missing complete baseline); run ID 35939661464.
