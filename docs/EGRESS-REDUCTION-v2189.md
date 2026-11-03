# Cloud v2.0.189 — scoped exports and care-list pages

Excel export now asks for datasets, service-date range and optional detailed fields before any dataset request. Current work items are explicitly not service-date filtered so incomplete tasks remain visible. Dashboard summaries and community/VHV progress remain available from the already-loaded dashboard, and are labelled as covering that dashboard's original reporting period.

Only selected datasets are read, with explicit column lists and stable 500-row pagination. Service timestamps use inclusive start/exclusive next-day end in Asia/Bangkok. Full detail retains the existing clinical/reference fields, including JSON domain details when selected. Scope changes or a closed export dialog cancel subsequent reads and prevent a mixed-scope workbook.

Special-care lists use `care_special_people_page_v2189` to join houses/persons in PostgreSQL and return display fields only. The UI shows 30 rows and uses one additional sentinel row for the next-page button. Search is applied before pagination across the allowed scope. There is no fallback that downloads the entire population.

The RPC is STABLE, SECURITY INVOKER, has an empty search_path, checks the active profile and applies caller RLS on both tables. It preserves the existing verified/non-superseded house and active/service-eligible person conditions. It makes no registry, screening-target or history changes. PUBLIC/anon cannot execute it. The migration version matches the applied production version: `20261103041223`.

Validation:

- `node tests/egress-export-v2189.cjs`: chosen datasets, columns, dates/timezone, scope, pagination and cancellation.
- `node tests/egress-ui-v2189.cjs`: mobile export produces selected sheets only; summary-only has no dataset reads; care pages 30+2; search resets offset; HTML text escaping; no page errors.
- `tests/care-special-pagination-v2189.py`: isolated synthetic PostgreSQL fixture on localhost:55438; 18 role/scope/group parity cases plus search/pagination and denied anonymous/inactive/missing/null-role access.
- Production read-only parity check: 3 roles, 15 group/scope cases, 214 matching rows across cases; no personal values printed or production data changed.
- Existing report UI, release-graph and house-loading regression checks passed. Migration integrity passed with 268 migrations.
- Security advisor categories/counts unchanged after the additive RPC migration; no new advisor ERROR.

These checks verify request reduction and behavior, not a percentage reduction in monthly Egress. Usage must be measured after release. The Pro subscription and Billing were not changed.
