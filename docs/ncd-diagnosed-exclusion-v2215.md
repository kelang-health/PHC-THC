# Cloud v2.0.162 — Exclude diagnosed patients from confirmation follow-up

Home BP confirmation work now requires `not health_persons.has_ht`; DTX/FPG confirmation work requires `not health_persons.has_dm`. Existing field measurements no longer override the disease exclusion. The same conditions apply to the Cloud worklist and the service-only local report. Saving uses the shared case eligibility function and rejects excluded cases with `CASE_NOT_ALLOWED`.

All existing field results remain stored. This change does not alter clinical thresholds, fiscal-year rules, person scope, community rules, or function grants. Disease exclusions remain specific to each disease.

Verified against Production using a transaction that rolls back every test change: eligible cases with field history appear; after simulating the corresponding diagnosis they disappear from the worklist and report, additional saves are rejected, and the existing history remains. Both BP and DTX passed before and after applying the migration. Initial field-history count was zero.

Release: meta phc-release and the login version are both 2.0.162. The config and NCD module URLs are refreshed for this release.
