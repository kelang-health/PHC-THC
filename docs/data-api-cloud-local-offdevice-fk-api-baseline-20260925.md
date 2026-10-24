# Phase 4 next-gates report — Cloud→Local, safe restore and isolated role/latency testing (25 September 2026)

## Change control
This report records **actual checks completed now**, not permission to merge/deploy. Draft PR only; no active website HTML/CSS/JS/backend was edited or deployed, no Production SQL/Cloud purge/JHCIS write, no Auth/LINE changes or H7 reactivation, and no live load test. The actual PR-diff path firewall passed the most recent code commit, limiting it to audit SQL/docs/tests/workflows. `DEPLOY READINESS` must remain red until the full vetted historical migration history is replayed and real UI/role/sync tests pass.

## 1. Independently restorable archive — actual result and blocker
A fresh read-only, DB-disconnected Python process independently reopened the existing encrypted *new* Local backup file (`archive-backups/cloud_registry_inactive_20260925_full_restore_v2.enc`) using the two existing separate key files **locally**, validated every inner encrypted payload's SHA-256, reference key and PCU, and successfully reconstructed **10,474** archived records (10,380 inactive people and 94 removed/superseded houses). No plaintext, identities, credentials or encryption keys were printed, transmitted to GitHub, or written as a report.

The *old* encrypted backup file previously failed current-key decryption and remains preserved unmodified; do not count it as restorable or silently replace either key. The new archive file and source Local `jreportdb` reside on the **same machine**. One connected machine, C:/D: local drives and zero currently mounted network drives were observed, so no separately approved off-device destination or verified off-device restore was available. **Off-device backup gate: NOT MET.** Do not copy sensitive records to an arbitrary folder, JHCIS primary server, ordinary cloud drive or GitHub just to claim this passed.

Existing Local archived cohort key counts/digests matched an earlier Cloud read-only cohort snapshot. That proves key-set parity at that snapshot, NOT every current Cloud field's equality, user-facing references, up-to-date JHCIS reconciliation or a legal retention decision.

## 2. Isolated Cloud minimum-house/member API contract — actual test
The existing synthetic candidate compares 4,700 fabricated houses and 8,600 fabricated active people in memory; it excludes synthetic historical columns while preserving a limited sample of current card identity/scope/status fields. New **disposable PostgreSQL FK ROLLBACK-only** test reproduced both risks: RESTRICT prevents deletion of an archived referenced person/house, while CASCADE can remove archived clinical history on a different person. The fixture deliberately rolls back; no live table was modified.

A new **disposable PostgreSQL 17 + PostgREST** integration fixture constructed 48 fake houses across 16 communities and 144 fake people, then used synthetic signed JWT role-claims to check fake ADMIN/STAFF/USER/empty-scope/anonymous row visibility over HTTP. 96 measured repeated HTTP calls completed with no test errors or cross-scope exposure; fixture p95 was **4.08 ms** in one GitHub Actions runner. This is a test of a *fabricated policy*, not existing OSM-PHC roles, production RLS/functions or the real front-end. No new Cloud view, endpoint, thin tombstone or browser→Local call was deployed.

Observed real Production function names still reference `health_screening_target_cache_v2030`, `report_snapshot_cache_v2031` and the associated health worklist/target RPCs. Removing these caches without a role-compatible replacement could break pages. Real UI page and session/auth checks remain a prerequisite for rollout.

## 3. Baseline and Cloud storage consequences
Read-only `pg_stat_statements` baseline, statistics accumulated since 8 Sep 2026 (database SQL time **not** browser/app latency, and query-name matching is approximate):
- `health_worklist_assignment_json_v2054`: 1,254 recorded calls, weighted average database execution **48.18 ms**.
- `my_screening_targets_json_v2030`: 1,017 calls, weighted average **6.22 ms**.
- `report_snapshot_v2031`: 7,952 calls, weighted average **4.02 ms**.
These cumulative values are not a before/after experiment, current p95 or guarantee of UI responsiveness. Synthetic 4,700-house/8,600-person full JSON 7,095,618 bytes versus thin-card JSON 3,631,818 bytes; gzip 205,377 versus 186,324 bytes. The synthetic 48-house/144-person HTTP p95 above is also **not** the live app performance.

After read-only verification, the PHC Production PostgreSQL database size was approximately **95,923,347 bytes**, with 191 recorded migrations, 59 `public` tables and 0 `public` tables having RLS off; no lock wait was seen in that point-in-time snapshot. Database size can change during normal user activity and cannot be attributed to this audit. **Cloud bytes freed by this work: 0.** Archive copies alone do not reclaim bytes while Cloud FK, RPC and historical records must remain. Do not bulk DELETE or VACUUM FULL live tables: such work can lock sessions or remove dependent history without demonstrated space gains.

## Go/no-go and next work
1. Approved encrypted **off-device** destination outside web roots and GitHub with controlled keys and restricted reader access, followed by a truly independent restore and identity/integrity checks on a second authorized device. Existing same-PC backup is insufficient for disaster recovery.
2. Complete current Cloud↔JHCIS↔Local field-level version/lineage parity and per-row FK/dependent-data inventory under read-only low-load checks; define records that *must* remain as narrow Cloud FK anchors. Review clinical/audit retention and rights before proposing anything deletable. Do not expose private Local services directly to mobile clients.
3. Restore/vet all historical migrations (PHC 191 recorded, outstanding source gaps noted in prior audits); replay on a disposable fully Supabase-compatible environment, then test the **actual** Auth/LINE/RPC/household/volunteer/staff/admin/booking-off flows, Local offline fallback, sync conflicts and no duplicate senders.
4. Collect production-compatible **non-load-intensive** current mobile endpoint and page p50/p95 and request-count baselines with approved access and redacted telemetry. Compare a staged, representative synthetic Local-precompute candidate, including cloud response payload, SQL p50/p95, storage/TOAST/index bytes and outage behavior. Reject regressions; no Production change from passing synthetic CI alone.
5. Only after all gates and reviewed retention/deployment/rollback plan: separate authorization for a reversible quiet-window Production migration, with authenticated smoke tests and immediate stop criteria. Keep both audit PRs DRAFT and deploy-readiness gate BLOCKED meanwhile.
