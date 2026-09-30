# Data API Phase 4 — controlled follow-up and stability assessment (25 Sep 2026)

## Production-safety decisions
- **No live SQL writes, production migration, default-ACL changes, RLS policy changes, Supabase preview branch creation, GitHub merge, Auth/LINE change or Cloud booking/announcement activation occurred in this work.**
- Draft PR only. Keep the separate **DEPLOY READINESS** gate failing until the complete history is vetted, replayed on a disposable Supabase-compatible database, and real application role-scope checks pass.
- All PostgreSQL/PostgREST test records, users, keys and passwords in GitHub Actions are synthetic and disposable. Synthetic CI latency is *not* a real-user production performance measurement.

## Implemented in draft PR
- Updated future-`postgres`-created-`public`-table candidate from CRUD-only REVOKE to `REVOKE ALL PRIVILEGES` for `anon, authenticated, service_role`. A CRUD-only REVOKE can leave TRUNCATE/REFERENCES/TRIGGER/MAINTAIN rights from historical broad defaults. Existing tables are not affected by ALTER DEFAULT PRIVILEGES.
- Updated static candidate scope check and PostgreSQL fixture to exercise and reject all inherited table privileges for browser roles, then explicitly GRANT only required table operations. This candidate covers the creating role `postgres` only; independently assess any other SQL creator role before a production plan.
- Extended disposable PostgREST HTTP checks with 40 repeated scoped synthetic authenticated reads; fail on any unexpected HTTP result or cross-user row, report CI-fixture p95 (do not apply an arbitrary production latency SLA to hosted GitHub Actions).
- Extended disposable PostgREST checks to verify synthetic server role can still read its explicitly granted tables, so hardening does not silently break the expected backend pattern. Production service-role JWTs and real user records are NOT used.
- Existing database/application/Auth/booking continue to use current permissions until separately approved after real-role regression testing.

## Required next gates
1. Recover original migration source into a private, access-controlled **non-web-served** workspace. Never commit raw source history to a public GitHub repository without inspecting data-import statements, identifiers, credentials, URL tokens, or external side effects. Compare SQL content semantics, not only filename versions or whitespace-sensitive hashes.
2. Review and replace historical data imports, scheduled jobs, network calls, and external-system dependencies with safe synthetic/disabled equivalents for replay, recording each difference. Verify all extension, auth, storage and role prerequisites without modifying the real deployment.
3. Run entire vetted history from scratch in an isolated fully Supabase-compatible target; verify final schema, policies, functions, RLS, sequences, function EXECUTE, Data API schema exposure, and least-privilege grants. A synthetic two-table PostgreSQL fixture is not a substitute.
4. Run real frontend/backend API flows with synthetic anon/USER/STAFF/ADMIN/service identities and **negative** cross-volunteer/community/house tests, alongside login, JHCIS sync, LINE Hub and paused H7 compatibility.
5. Review advisories and explicit function authorization; baseline production performance before deployment. If any actual privilege or latency regression appears, do not merge/deploy; use a reviewed forward fix, not a blind global grant/rollback affecting live users.

**Operational assessment:** draft-only CI security hardening has no production runtime impact. Full Phase 4 closure is currently blocked on the historical source/full-stack replay; the separate GitHub readiness failure is intentional.

## PHC-specific evidence
- Production recorded history: 191 versions. Inspected local OSM-PHC migration folder: 121 SQL files, 101 version matches, 90 recorded versions missing locally, 20 local-only version numbers. Matching names alone cannot prove matching SQL content.
- Catalog review: 59 existing public tables (RLS enabled); all current public table owners in the observed catalog are `postgres`. `postgres` and `supabase_admin` have different role-scoped default ACLs, so the candidate MUST NOT be assumed to cover future tables created under another role.
- Security-definer review: 149 definer functions are SQL EXECUTE-callable by `authenticated` (130 `public`, 19 `private`). Seven `private` functions have an `anon` EXECUTE privilege but anonymous callers lacked schema USAGE when observed. Role/function privilege alone does not establish exposed Data API reachability or exploitable cross-user access.
- Representative manual read-only function review: `save_health_ncd_screening_v2` delegates write to `save_health_ncd_screening`, which checks authenticated identity, current role, and `private.health_can_access_house` before inserting. `update_house_coordinates_v1858` checks current role and volunteer/community scope before UPDATE. This does **not** certify all 130 public definer RPCs or the security of their dependencies. Its pre-check row lock and role-dependent error timing warrant testing under concurrent synthetic use before any rewrite.
- Supabase advisors still report 130 signed-in-callable definer function findings, RLS-without-policy notices (some tables intentionally server-only), and disabled leaked-password protection. Do not react to no-policy notices by granting blanket client access.
- One production DB stats snapshot: 8 sessions, 1 active, 0 waiting on locks, 0 cumulative deadlocks since the reported stats-reset timestamp. This snapshot does not certify day-long uptime or latency. Keep paused Cloud announcements/booking paused.
