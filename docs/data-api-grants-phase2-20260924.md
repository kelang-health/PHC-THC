# Phase 2 — Data API explicit GRANT readiness (24 Sep 2026)

**Status: staged for review; no SQL applied to production.** Scope: OSM-PHC Cloud / PHC-THC. Existing authentication, LINE Login, RLS policies, JHCIS read-only linkage and paused announcements/bookings remain unchanged.

## Evidence from connected production DB (read-only inspection)

- Project `tgeezbwbrovfyjbeykrj`: 56 public tables, all RLS-enabled; 22 public views, all `security_invoker=true`.
- Seven public tables have `anon` SQL-level SELECT/INSERT/UPDATE/DELETE grants; inspected policies grant row-level access to authenticated sessions, not anon.
- 21 public tables do not have authenticated SELECT; this may be intentional for server-only cache/audit tables. Do not bulk GRANT.
- The recorded default ACL for creating roles `postgres` and `supabase_admin` automatically grants table DML to API roles. On October 30 this platform default changes for new tables. Never rely on it.
- 182 Supabase migration records in the database; the complete canonical `supabase/migrations` history is **not in this repository**. Until it has been restored and compared, DO NOT point `supabase db reset` at the isolated candidate file as if it were a complete replayable baseline.
- SQL text audit: of 40 migrations containing `CREATE TABLE`, two lack a literal `GRANT` in the same migration. They concern a temporary `pg_temp` cache-build table and `private.nightly_snapshot_outcomes_v2077` (explicitly revoked), not missing public Data API grants. The other 38 contain `GRANT` somewhere, which does NOT prove every created table has the necessary table-specific grant.
- Supabase Security Advisor flagged 125 signed-in-callable `SECURITY DEFINER` RPCs. These are *audit candidates*, not confirmed vulnerabilities; do not revoke RPC EXECUTE en masse because that may break client flows.

## Implementation now

`database/phase2/20260924_future_public_table_defaults_candidate.sql` is **review-only**. It changes default ACLs for **future** tables created in public by `postgres` or `supabase_admin`; it changes no existing table. Keep it OUT of auto-deployed `supabase/migrations` until historical baseline, creator-role privileges, deployment sequencing, and isolated tests are verified. Applying it prematurely can make subsequent new tables inaccessible until their per-table GRANTs are added.

For every NEW public table migration include, in the **same transaction/migration**:
1. Explicit RLS and scoped policy appropriate to user/admin/staff/volunteer, with service-only tables keeping API grants absent for anon/authenticated.
2. Explicit minimum table GRANT per required API role; choose SELECT-only for field readers; no anon grant for identifiable health/residence information.
3. Any required identity sequence USAGE and RPC EXECUTE scoped to the intended role; RPC SECURITY DEFINER must verify caller identity, scope and input inside the function.
4. A smoke test using anon, authenticated and authorized server contexts, plus at least one negative cross-community / cross-volunteer check.

## Gates before deployment

- Restore/export complete historical migrations and compare the resulting clean schema against live production before attempting `supabase db reset`.
- Validate each `CREATE TABLE public.*` against that table's actual grants; do not treat `GRANT` anywhere in a migration as proof. Review temporary/private tables separately.
- Verify Dashboard → Data API → Exposed schemas; catalog `has_schema_privilege` is not the Data API configuration.
- Audit sensitive views and the Security Advisor's SECURITY DEFINER list; do not infer full endpoint security merely from RLS-enabled=true.
- Test in an existing authorized isolated environment; production changes and rollout are a separate gated operation.
