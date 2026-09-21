# Phase 5 — Training Dashboard & Readiness (22 September 2026)

## Local data reconciliation (read-only)
- Local production training: 1 course, 1 event, 71 participation records.
- Cloud volunteer_training_history: 71 rows; local-only 0, cloud-only 0, status mismatch 0.
- Active JHCIS Type 09 volunteers: 270 (Local scoped, read-only JHCIS query).
- Active Cloud User/Staff accounts: 267; accounts with recorded training: 70.
- Missing history for an account is not automatically a sync error: Local presently contains only one recorded event.

## Data-quality backlog (overlapping categories)
- Verified houses: 4,479.
- Houses without linked volunteer: 295.
- Houses with missing community: 43.
- Houses without coordinates: 208.
- Houses flagged for review: 1,837.
Do not add these categories together: one house may belong to multiple categories.

## Cloud v2.0.77
- Lazily loads read-only scoped training-dashboard data on the Work menu.
- Admin sees all active volunteers, Staff only the assigned community, User only the linked volunteer.
- Uses the existing volunteers/training-history RLS; no new database policies or writes.
- Excludes cancelled training, distinguishes training-data coverage from certification, and shows a guard if result counts exceed the safe first-page limit.

## Tests and limitations
- Local admin audit endpoint: no authentication -> 401, Staff -> 403, Admin -> 200 against production MySQL and Cloud (without any account credential exposure).
- Cloud training aggregate unit-browser test: Admin, Staff, User scope, cancelled records; passed.
- Phase 3/4 mobile regression: 6 viewport widths; passed.
- Real signed-in iPhone Safari workflow and actual network latency per role still require field acceptance; no account credentials are used or invented by these tests.
- Go-live approval is NOT automatic: data-quality backlog remains.
