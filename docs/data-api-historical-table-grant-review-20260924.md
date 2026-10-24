# Historical table-grant review — OSM-PHC (2026-09-24)

**Review-only evidence. Do not execute a mass GRANT or apply a default-privilege change to production.**

Per-table examination of recorded Supabase migration SQL identified 58 literal `CREATE TABLE public.*` occurrences across 182 history records; **10 occurrences lack a table-specific GRANT within their own migration** (textual conservative check, not a proven production failure). Other 16 create-table occurrences are in the `private` schema. The existing public catalog contains 56 tables, all RLS-enabled. Table name/owner can be repeated in CREATE IF NOT EXISTS, so create occurrences are not equal to unique table count.

| Recorded migration | Table | Catalog privilege / policy classification | Required action before isolated replay |
| --- | --- | --- | --- |
| 20260908121831 | app_settings | authenticated SELECT policy; currently broad SQL-level anon/auth grants | Verify pre-login app request behavior; explicit authenticated SELECT in same create migration if API reading is required; do not add anon merely because the original default did. |
| 20260908121831 | communities | authenticated scoped SELECT policy | Explicit minimum authenticated SELECT; verify staff/user scope. |
| 20260908121831 | houses | authenticated scoped SELECT policy; currently no anon SELECT | Explicit authenticated SELECT as required; deny anon; verify house assignment scope. |
| 20260908121831 | profiles | authenticated self/admin SELECT and admin ALL policies | Explicit authenticated SELECT and admin write mechanism via scoped RLS/RPC as needed; verify login/bootstrap and role assignment. |
| 20260908121831 | sync_runs | authenticated admin SELECT policy | Explicit authenticated SELECT only if admin UI uses direct table; otherwise backend-only. |
| 20260908121831 | tambon_boundaries | authenticated SELECT policy | Explicit authenticated SELECT for required map use; decide separately whether a true anonymous map API is intended. |
| 20260908121831 | volunteers | authenticated scoped SELECT policy | Explicit authenticated SELECT; verify own volunteer/staff/other village restrictions. |
| 20260910014310 | volunteer_profile_media | client-deny restrictive RLS; no anon/auth current SELECT | **Server-only:** retain no client GRANT. |
| 20260912102000 | line_messages | no client SELECT grants or RLS policies | **Server-only:** retain no client GRANT. |
| 20260912102000 | user_line_links | no client SELECT grants or RLS policies | **Server-only:** retain no client GRANT. |

The original initial-migration statements are not in GitHub's replayable `supabase/migrations` history. Edit the real historical migration **in a restricted workspace**, or add an immediately adjacent replay-only correction migration, and validate fresh bootstrap. A late, unconditional catch-up GRANT on production can hide missing new-table grants and accidentally broaden access.

**Additional API behavior gate:** existing anon SQL-level GRANT plus RLS may currently produce HTTP 200 with an empty result, whereas a fresh table with no anon GRANT may return 42501/403. Preserve working login/boot by testing, not by opening patient/residence tables to anon.

The stored SQL migration body is approximately 1.30 million characters across 182 entries, and many statements include words relating to tokens/auth. Do not indiscriminately publish the entire DB migration history to this public repository; review for secrets and data literals first.

Next: reconstruct vetted historical scripts, perform isolated DB reset, verify GRANT/RLS per table, and test actual role-bound Data API, as documented in Phase 3. Existing public tables and Data API default ACLs remain unchanged.
