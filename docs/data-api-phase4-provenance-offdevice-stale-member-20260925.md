# Data API / Cloud→Local next-phase evidence — 25 September 2026

## Decision and blast radius
All work in this continuation was read-only on Production and Local migration/source files, metadata-only in the restricted Local governance directory, or isolated synthetic PostgreSQL/PostgREST CI. No active frontend/backend/line-auth/sync/JHCIS change, Cloud data export, Cloud deletion, production grant/RLS/migration edit, Production load test, Supabase branch, or PR merge. The OSM-PHC Cloud event/booking remains paused.

## 1. Off-device encrypted backup
The prior separately encrypted archive file holding 10,474 archived Local records remains in the restricted Local private directory and was fully restored in a fresh process disconnected from DB in the previous phase. This continuation found only ONE authorized connected remote computer. No verified separately approved backup target/second machine is connected or authorized. C: and D: on the same computer, and unapproved network/cloud folders, do NOT satisfy independent-device disaster recovery. No personal/health record was transmitted to a different endpoint in this phase.

**Off-device backup and restore: BLOCKED.** Keep the two original encryption keys and existing encrypted file private. Do not rotate or replace credentials to make the old unreadable file appear recoverable. A separately approved off-device storage and offline restore test remain mandatory for any irreversible Cloud data-reduction rollout.

## 2. Historical migration provenance (no real SQL copied to GitHub)
Read-only compared live PHC `supabase_migrations.schema_migrations` inventory (191 recorded versions) with actual local current and backup SQL filenames, and computed only private metadata/file-body hashes:
- 121 current local SQL files, 139 SQL files in the inspected backup subtree.
- 101 recorded versions have a same-version file candidate; **90 recorded versions have no exact-version SQL candidate** in these inspected locations.
- **51 recorded versions** have multiple non-placeholder SQL source variants with different normalized text (BOM, newline and trailing-whitespace normalization did not remove the difference). This is a file-provenance mismatch; it is NOT proof the live database was modified incorrectly or that the variations change SQL semantics.
- Nine of the 90 missing-version entries have a same-name file under a different version number. Renaming, repurposing or replaying these files blindly could corrupt migration order.
- Missing recorded versions by recorded date: 13 Sep 3, 15 Sep 2, 17 Sep 2, 19 Sep 10, 20 Sep 2, 21 Sep 5, 22 Sep 15, 23 Sep 42, 24 Sep 9.

Created `D:\\AppServ\\private\\osm-phc\\governance\\data-api-migration-provenance-20260925.json` (85,243 bytes) *on the authorized Local machine, outside web root*, recording inventory, version status, candidate relative paths, content SHA-256 hashes and same-name version aliases. The manifest contains **NO SQL payload, actual patient record, credentials or encryption key**. No file variant is auto-declared canonical: `canonical_source_confirmed=false` for every recorded version. The document/manifest are provenance aids, not a source restoration or SQL replay.

**Full historical replay: BLOCKED.** Do not mark existing CI deployment readiness green or run 101 partial files against a real database as a substitute for a complete, vetted, ordered historical source.

## 3. Actual RPC metadata review and stricter isolated negative case
Read-only reviewed current live function definitions: `my_household_cards_v1860` uses authenticated current volunteer ID to select verified, non-superseded assigned houses. `staff_household_cards_v2072` checks the signed-in staff profile and requested community in the same moo, and indicates own-community manage versus different-community read-only. This is source-code review of selected routines, NOT authenticated USER/STAFF/ADMIN end-to-end authorization testing and NOT certification of every dependent RPC.

The earlier fake member/house PostgREST fixture trusted the member's denormalized community and volunteer fields; this could conceal a stale-member-metadata scope error in the *test*. Updated `tests/phase4-cloud-local-scoped-http.sql` so synthetic member visibility is gated by the referenced house's RLS. Added a member whose own scope metadata is misleading and negative HTTP cases proving staff and volunteer roles cannot see it through the out-of-scope house. The new test uses **fictional IDs/data and disposable JWTs**. The updated CI run `36077594297` succeeded in all three offline jobs; the synthetic PostgREST fixture completed 96 timed calls, p95 4.23 ms *inside disposable CI only*. Do not assert an actual Production vulnerability or real-web latency improvement from this fixture.

Verified one public HEAD request to the current GitHub Pages PHC-THC landing URL returned HTTP 200; a HEAD check cannot validate authenticated UX, current screens, LINE login, app cache or p95 page timings.

## 4. Storage/performance release gate
No Cloud record was removed. Cloud storage reclaimed by this work **0 bytes**. Read-only status and previous cumulative SQL statement timing remain baselines only, not pre/post performance proof. Existing Cloud `health_persons` and `houses` are FK anchors with RESTRICT and CASCADE paths; current health worklist, target and report-cache functions rely on live Cloud table data. No mobile client should make an additional direct request to Local/private services to compensate for deleting current Cloud data.

**Next required gates**: (1) authorized protected off-device encrypted backup + standalone recovery on second device; (2) source provenance and correct SQL contents for all 191 histories, data-migration sanitization and isolated Supabase-compatible full replay; (3) realistic synthetic role/JWT/profile/house/community/Moo and active clinical/booking-off/sync tests using the actual frontend/API, plus Local disconnected/error fallback and single-writer fencing; (4) non-load-intensive real-user-request-count/p50/p95 baseline and controlled isolated before/after footprint + traffic tests; (5) independently approved, reversible Production maintenance with no loss of FK/history/scope. Do not create a cost-bearing Supabase branch or deploy without separate reviewed approval.
