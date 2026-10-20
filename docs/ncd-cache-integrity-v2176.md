# Cloud 2.0.176 — NCD Production evidence and report integrity

Production service dates determine fiscal-year completion by `(source_pcucode, source_pid)`. Imported JHCIS history can be newer without hiding Production status or severity. The latest valid Production row uses service date, recorded time, then ID; future-dated and test records are excluded. `previous_*` keeps the newer source measurements. Imported history remains unchanged in `health_persons`.

The full refresh and incremental screening trigger share `private.reconcile_ncd_cache_v2176`. DM and HT retain their existing target and imported measurement rules, but collect valid measurements from **any** Production visit in the fiscal year. Repeated visits and changes of current house/community never create a second person.

Care snapshots use the same cache target/status fields. A candidate generation must match actual Production identities and care/field community totals before it becomes current. Failures retain the preceding generation and record an internal aggregate diagnostic. Blank communities use “ยังไม่ระบุชุมชน”; unknown or inactive community labels fail validation instead of being reassigned. New audit tables/functions have no anonymous/authenticated direct access.

The existing midnight refresh remains. An additional 07:30 Bangkok snapshot refresh is followed by a 07:35 integrity check. Daily/weekly service activity counts distinct current target people per period, so weekly totals are computed directly rather than summed from daily counts. The scoped field report exposes these comparisons only after validation. Daily summary metrics exclude tests and require validated NCD data; no notification is sent by deployment/tests.

## Validation

Run with `@electric-sql/pglite` 0.5.8 and `linkedom` 0.18.13 available:

```
node tests/ncd-cache-v2176/test-cache.cjs
node tests/ncd-cache-v2176/test-report-ui.cjs
python tools/check_migration_integrity.py
```

The isolated PostgreSQL fixture uses synthetic identities and the actual migration functions/view. It covers later JHCIS history, old FY only, repeat screening, tests, disease-specific measurements, severity, future service dates, repeat refresh, 16 communities, unknown community, moved house, deletion/incremental refresh, and rejected snapshot publication.

## Deployment and rollback

Back up current function/view definitions, cache/snapshot aggregate status and protected-table fingerprints before deployment. Apply only this migration; never push unrelated pending migrations. Refresh target cache, then report snapshots; check `private.ncd_integrity_v2176(current_generation)` and the 69-person historical cohort. Repeat refresh and compare identities/statuses. Verify the live page release and login label agree at 2.0.176.

The task artifact directory contains `rollback.sql`, with the exact pre-change refresh/trigger/view/snapshot/daily-metric definitions and commands to remove only the two new cron jobs. Execute it transactionally with a short lock timeout, then refresh derived cache and reports. It does not delete clinical records, people, houses, GPS or accounts. Keep audit data for diagnosis. Revert only the release commit for frontend rollback.
