# Appointment Notice Multi-OA v2.1.84

Production snapshot for Local OSM-PHC appointment reminders.

## Architecture
- Primary VHV OA: @322ozezc. Recipient identity comes from Local phc_cloud_line_links.
- Backup OA: @601cnwrw. OSM-PHC never stores its access token or raw LINE user IDs.
- Backup dispatch uses a loopback-only LINE Service Hub bridge and an opaque local_patient_ref.
- A backup recipient is eligible only when the Service Hub mapping is verified/active and its local patient reference resolves to the same JHCIS PID as the Local Volunteer.
- Manual Phase 2 and Auto D-1 Phase 3 use the same quota-aware routing and the same OSM delivery ledger.

## Policy defaults
- quota warning: 90%
- start failover: 95%
- primary reserve: 15 recipient groups
- route also fails over when projected groups + reserve exceed Primary remaining quota
- an explicit Primary HTTP 429 may fall back to Backup for verified recipients
- ambiguous network failures never cross-OA retry, reducing duplicate risk
- no guessing of LINE identities across OAs

## Privacy
OSM-PHC stores provider_slot and OA basic ID in the delivery ledger, but not backup raw LINE user IDs, backup access tokens, CID, diagnosis, or message content.

## Validation snapshot 2026-10-04
- Primary: 300 monthly limit, 0 used, 300 remaining
- Backup: 15,000 monthly limit, 1,678 used, 13,322 remaining
- Backup-ready: 6/276 VHV and 1/15 Staff
- simulated Primary exhausted: backup-ready VHV routed to Backup; unmapped VHV blocked
- Backup push dry-run succeeded; OSM sent ledger stayed 0 and Hub sent count did not increase
