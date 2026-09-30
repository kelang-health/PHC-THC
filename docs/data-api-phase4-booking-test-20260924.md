# Phase 4 — booking table test and closure decision (2026-09-24)

## Decision: booking test PASS, whole Phase 4 NOT closed

**An actual production booking table already exists**: `public.cloud_event_bookings_v2085` with companion `public.cloud_event_slots_v2085`. Both have RLS and authenticated SELECT policy; authenticated direct table INSERT/UPDATE is not granted on either. Booking/announcements Cloud rollout remains paused per user instruction; do not add another production booking table just to demonstrate future-table grants.

## Executed safe test

Added `tests/phase4-booking-grant-rls.sql` and `tests/phase4-booking-http.cjs` to PR #1. GitHub Actions run 35946868880 passed three jobs: static SQL candidate and inventory checks, isolated PostgreSQL 17 grant/RLS/booking fixture, and disposable PostgREST HTTP role tests. The HTTP booking test step **passed**. The historical-migration-gate **failed/blocked as designed**, since a complete replayable historical source tree is still missing.

All booking rows are synthetic. Test table `public.phase4_booking_fixture` exists ONLY in the disposable CI database and is not migrated to production. It has an explicit authenticated SELECT GRANT, owner/community/admin SELECT policy based on synthetic signed JWT claims, backend-only writes, and a slot/person duplicate constraint. HTTP tests covered: anonymous private booking denial, USER A/B sees only their own row, STAFF community A/B sees only their community rows, ADMIN sees all synthetic rows, and client POST/PATCH/DELETE denied. This tests a representative contractual pattern, **not** the production policy `private.health_can_access_house`, application H7 eligibility, scheduling capacity or actual LOGIN/LINE auth. Production Cloud booking stays disabled.

## Exact conditions to close complete Phase 4

1. Recover and vet the **complete** original recorded migration history in a restricted workspace: OSM-PHC 182 versions; currently inspected local source has 115 files of which 101 versions match, 81 recorded versions missing, and 14 source-only versions. Other med-device-sharing source history (46 versions) is also not fully available in the examined paths. Review historical inserts, auth secrets and non-canonical DB statement formatting before copying or replaying.
2. Verify that every new exposed public table is created with RLS and appropriate explicit least-privilege GRANT at creation time and that server-only tables remain non-exposed. Verify creator role and default ACL behavior; no blanket client grants.
3. Replay a vetted full stack in an approved isolated Supabase-compatible test database; compare schema, policies, grants, functions, views, auth and Data API exposed schemas, and regression-test real frontend/backend paths with synthetic ADMIN/STAFF/USER/anon identities and cross-community negative cases.
4. Verify booking-specific real backend eligibility, duplicate detection, work queue and capacity with local synthetic data, without activating the paused Cloud booking feature.
5. Only after these gates PASS review production change and rollback/forward-fix; existing tables continue operating on existing privileges and DO NOT need a new table merely for the Supabase future-table grant change.

Do not promote this draft PR or call a synthetic booking fixture a complete migration replay. No production schema/auth/config/user data changed.
