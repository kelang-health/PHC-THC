# Phase 4 continuation — protect current web UI and user-facing performance (2026-09-25)

## Non-disruption controls executed

- Both audit PR #1 branches remain **DRAFT and unmerged**. Their changed-file inventory contains only `database/phase2/**`, `tests/data-api-*/phase4-*`, `docs/data-api-*`, and the named Data API-only GitHub Actions workflows. No released HTML, CSS, JS, image, public `supabase/migrations`, authentication, production deploy workflow or runtime code changed in these PRs.
- Added `tests/data-api-frontend-unchanged.cjs` and a pull-request diff check to the offline GitHub Actions workflow. This verifies *actual base/head commit file paths*, rejecting front-end, runtime, deployment or live-migration changes, and deletions of security test files. Filename checks are a narrow **path firewall**, not a substitute for code review of the permitted audit files.
- Offline synthetic PostgreSQL/PostgREST tests use GitHub Actions disposable services and no production API keys or user records. No load test was sent to the live website. No production Supabase SQL write, branch creation, Auth/LINE login change, or H7 booking reactivation was done.
- Deployment-readiness remains a separately failing check until complete vetted migration replay and real-app access/performance regression tests are verified. Do not change branch protection or mark its failure as success to silence GitHub email.

## Assessment and decisions

**Current-site change risk from this continuation:** No production-facing code was modified or deployed. The draft candidate change to future-table ACLs has not been applied; normal page requests still use existing production rights. This does not prove that current live performance has no independent problems.

**Full Phase 4:** BLOCKED. A passing isolated role/table fixture and a verified UI-unchanged diff do not replace whole-history migration replay, real login/house/community-scoping tests, or production-comparable latency measurements.

**Rollout plan after provenance work:** private/offline SQL source classification → full isolated Supabase-compatible replay with synthetic data and disabled external side effects → real synthetic USER/STAFF/ADMIN/backend scenarios and booking-off checks → baseline/compare p50/p95 request timings and concurrency on a non-production environment → separately authorize any reviewed production migration with smoke tests and forward-fix plan. Never run history imports or force GRANTs on live production to make a CI status green.
## PHC source-recovery evidence

Production registered history: 191 versions. Inspected current local OSM-PHC migration directory contains 121 SQL files; only 101 of the recorded version numbers match; 90 recorded version numbers absent and 20 local-only version numbers. A filename-only scan of the OSM-PHC **backup** subtree found 139 backup migration filenames, of which 52 were named `remote_applied_placeholder`. The non-placeholder backup subset has 57 unique version numbers, only three absent from current local source: `20260913190000_report_snapshot_cache_v2031.sql`, `20260913194500_public_branding_bucket_v2031.sql`, and `20260913195500_report_snapshot_state_fk_index_v2031.sql`. The names correspond to recorded Supabase migrations but the *actual recorded versions differ*: `20260913071623`, `20260913092407`, `20260913093939` respectively. This backup discovery recovers **zero verified matching-version historical sources** so far, and no SQL-body identity/replay result can be inferred from a matching name. Do not rename or execute these files before provenance review.

Other local backup paths may contain source SQL, but broad recursive scanning or copying real SQL bodies is not justified while current web performance and personal-data confidentiality are priorities. Any future source recovery goes to a restricted non-web-served workspace; do not copy history to public GitHub.
