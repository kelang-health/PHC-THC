# Phase 4 exit-gate report — 2026-09-24

## Decision

**BLOCKED — do not represent Complete Migration Replay & API Validation as complete.** A disposable PostgreSQL 17 + PostgREST role-scoped API contract passed in both GitHub repositories. This is not a replay of either production Supabase migration history or an end-to-end test of actual Cloud user/staff/backend flows. GitHub PR #1 in each repository remains **draft** and deliberately retains the failing `historical-migration-gate`.

## Confirmed safeguards

- No production migration, schema modification, default-privilege change, RLS-policy change, data export, branch creation, Auth/LINE Login change or Cloud announcement/booking reactivation was performed as part of this phase.
- The recorded migration registry in GitHub contains version/name metadata only. **Do not commit original migration SQL without secret and personal-data review.**
- Disposable CI checks passed: staged PostgreSQL default-ACL SQL, explicit grants, synthetic owner-scoped RLS, anonymous HTTP denial, authenticated synthetic cross-user HTTP isolation, and server-only table denial.
- The production role-specific API test on the real application with actual ADMIN, STAFF and USER accounts, Dashboard exposed-schemas check, and full-history replay have **not** passed or been performed.

## Non-negotiable exit gates

1. Recover a complete, vetted history (all original versions and exact statements or documented corrected/sanitized replacements); perform metadata, SQL-body and order reconciliation, including source-only versions and data-import migrations. Store any sensitive source in a restricted folder **outside the web server directory** and do not upload it to public GitHub.
2. Confirm isolated Supabase full-stack capability and budget approval if a managed development branch/project is necessary. No preview branch was available on the two production projects and no branch was created.
3. Replay the corrected complete set on an isolated disposable Supabase-compatible target. Confirm extensions/auth/storage prerequisites, actual schema diff, default ACL, grants, sequences, RLS, policies, views and RPC execute/scope. Use synthetic test persons and equipment only.
4. Test real app HTTP paths with synthetic ADMIN, STAFF, USER and anonymous identities, including negative cross-community/cross-volunteer checks, disabled Cloud announcements/bookings, and LINE/backend isolation. Do not alter existing production identities.
5. Review 125 signed-in-callable SECURITY DEFINER RPCs on OSM-PHC according to authorization risk before full security sign-off. Zero anon-callable definer RPCs alone is not full verification.
6. Recheck security/performance advisors and document deployment and rollback/forward-fix tests. No permission to merge/deploy follows from isolated fixture PASS alone.

**Operational status:** existing public tables remain usable under their existing privileges; the draft default-grant change should not be rushed into production simply to force a phase-complete label.

## OSM-PHC measured blocker details

- Production Supabase has 182 recorded migrations, with 56 existing public tables, all RLS-enabled.
- Inspected local source `D:\\AppServ\\www\\osm-phc\\supabase\\migrations`: 115 SQL files; 101 version numbers match live history; 81 recorded versions absent locally; 14 local version numbers absent from live history. Complete file recovery is NOT done.
- Exact raw SHA-256 digest comparison between the 101 version-matched local files and the `array_to_string(statements, E'\\n')` DB representation yielded 0 raw hash matches. These are **non-canonical representations** and can differ because the migration recorder splits statements, strips semicolons or changes separators. This does **not** prove the 101 scripts have different execution semantics. A canonical SQL-aware comparison is still required. Do not blindly rename/replace 14 unmatched local versions.
- Production migration history included 96 SQL records with an INSERT INTO match. Do not replay them until reviewing whether they write historical household, login, training or other live data.
- Synthetic PostgreSQL/PostgREST fixture GitHub run 35942828411: static PASS, isolated PostgreSQL grant/RLS PASS, isolated PostgREST HTTP PASS; complete-history gate FAIL as designed.
