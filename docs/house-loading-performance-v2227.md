# Cloud v2.0.184 — House loading performance

22 October 2026 (Asia/Bangkok)

House navigation previously waited about 4–5.5 seconds for `house_groups_v2225` in the supplied browser trace. The database implementation repeatedly looked up the current profile while checking every house. It now uses the active profile already verified at entry, retaining the same admin, community-scoped staff, assigned-user, and registration-review exceptions. Registration review JSON is joined by house ID rather than searched through correlated subqueries. Public RPC signatures and payloads are unchanged.

The grouped house page reuses the review data in the house response for decoration instead of fetching the same review list on activation. Opening a review still uses the existing review loading and save validation. The legacy review page remains available if the grouped module fails to initialize.

The page retains existing cards during refresh and shows an update message. The cache remains 60 seconds; failed RPC responses are no longer cached. Pagination remains client-side at 30 cards per page: the measured SQL improvement makes a new pagination API unnecessary for this release, and preserves complete search and group counts.

Diagnostics Phase 1.2 waits for an explicit successful house render, including empty results. Hidden panels can be recognized as already having cached data. `dataReadyMs` records availability of existing data, and `freshDataReadyMs` records completion of a network refresh. Reports include the displayed Cloud release, Long Tasks API support, and a caveat that resource byte measurements can be incomplete for cached or cross-origin resources. The diagnostic report does not include the internal review-sharing event or its payload.

## Verification

- Transactional comparison of the full ordered JSON response: identical before/after for 7 existing profiles (1 admin, 3 staff, 3 users); all test DDL rolled back.
- Paired database timings: admin 2,500.749 → 239.014 ms; staff 2,601.641–2,618.736 → 58.829–70.077 ms; users 1,713.461–1,728.907 → 16.117–17.437 ms.
- After deployment, all 277 active profiles checked for returned community values, assignment restrictions, no person-name fields, and school exclusion. Mean/max database time: 6 admins 261.30/302.65 ms; 16 staff 62.21/77.05 ms; 255 users 16.71/27.98 ms.
- Existing SQL regression suite: 14 checks passed, including role scope, inactive/anonymous rejection, count-only data, explicit audited names, and school exclusion. Test transactions rolled back including test audit rows.
- Actual `authenticated` database role can call the public RPC; anonymous EXECUTE remains revoked; public wrapper remains SECURITY INVOKER.
- Before/after fingerprints of houses, health persons, target cache, and screening history match. Active persons remain 8,947; active type 2 remains zero.
- Security advisor categories and counts unchanged after migration.
- Browser fixtures: existing house-group and registration-review tests, plus `tests/house-loading-perf-v2227.cjs` covering delayed and empty responses, old placeholders, cached hidden panels, cache expiry, refresh preservation, error retry, review integration, and diagnostic metadata.
- New migration version/name matches production, and migration integrity passes against the parent commit. The broader production-history audit found existing drift (49 remote-only and 25 historical local-only entries, excluding the matching new migration). These historical migrations were not replayed or altered; reconcile them separately before a future bulk migration push.

Database times above exclude network transit and browser rendering. A fresh iOS field trace is needed to compare end-to-end latency with the supplied trace. Browser interaction tests use fixtures; production verification checks the public login page, displayed release, published file contents, and anonymous API denial without signing in to real user accounts.

## Rollback

Restore the frontend files from the parent release as one unit. Restore `private.house_groups_v2225()` from migration `20261022002649_staff_direct_care_house_groups_v2226.sql` through a new migration; never edit applied historical migrations. No business records need to be restored because this release does not modify them.
