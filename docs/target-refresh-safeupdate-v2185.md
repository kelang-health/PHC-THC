# Cloud v2.0.185 / Local target refresh repair — 22 October 2026

The target-cache rebuild now deletes using the cache's non-null primary-key columns as an explicit predicate, preserving the existing full rebuild, eligibility rules, and reconciliation of production screening results while satisfying safeupdate. No service screening history is deleted.

Local single-volunteer sync and Health-only sync queue report-summary recomputation through the existing coalescing report queue and its scheduled worker. They no longer rebuild all report scopes inside the HTTP request after population and target writes have already committed. The queue reports `queued`, not `refreshed`, and only service_role can call the new invoker RPC and its private delegate.

Local Health-only/target-refresh guards now check the exact source-PCU/HCODE keys of the active, eligible type 1/3 population against current verified Cloud houses. Missing, pending, superseded, wrong-office and blank keys still block the operation. Unrelated retired houses or incomplete JHCIS house records without active health targets no longer block target refresh merely because the total registry counts differ. The full-registry count comparison remains available separately; full-sync guards retain the original count rule. This change does not archive or invent any house, community or assignment.

Validation: Local targeted guards 38 passed; live scoped sync endpoint handler for PID 4785 returned HTTP 200 for 18 houses, with screening-history protection passing and no Auth writes. Exact health-house check covers 3,548 houses with zero missing keys. Health/state/count/target parity passes; target refresh confirms already_current. HTTP handler tests use an isolated FastAPI app with an administrative test dependency and the real sync/guard/Cloud implementations; production authentication is unchanged. Report summaries remain asynchronous, and clinical source data can continue changing during clinic operation.

Cloud v2.0.184 performance changes are preserved. Displayed release metadata/login version are advanced to v2.0.185 and verified after deployment.
