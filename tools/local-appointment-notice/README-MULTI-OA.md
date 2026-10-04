# Appointment Notice Multi-OA v2.1.85

Production snapshot for Local OSM-PHC appointment reminders.

## Phase 3.2
- Backup Coverage Onboarding dashboard by community and individual VHV.
- Primary / Backup / dual-ready status without exposing CID, PID or raw LINE user IDs.
- Targets: 90% minimum and 95% operational goal.
- Static local QR for Backup OA add-friend flow.
- Official LINE URL schemes:
  - Add friend: https://line.me/R/ti/p/%40601cnwrw
  - Open OA chat with prefilled "ลงทะเบียน" message.
- Registration reuses the existing LINE Service Hub identity flow:
  add friend -> send "ลงทะเบียน" -> one-time identity link -> CID + birth date verification -> verified mapping.
- Read-only quota forecast for tomorrow's D-1 notifications.
- Preflight task at 16:30, Auto D-1 remains at 17:30.
- Preflight persists aggregate risk only; no PHI.
- Primary reserve is enforced as a hard reserve while failover routing is active.

## Multi-OA architecture
- Primary VHV OA: @322ozezc. Recipient identity comes from Local phc_cloud_line_links.
- Backup OA: @601cnwrw. OSM-PHC never stores its access token or raw LINE user IDs.
- Backup dispatch uses a loopback-only LINE Service Hub bridge and an opaque local_patient_ref.
- Backup eligibility requires a verified/active Service Hub mapping resolving to the same JHCIS PID as the Local Volunteer.
- Manual Phase 2 and Auto D-1 Phase 3 use the same quota-aware routing and OSM delivery ledger.

## Default policy
- quota warning: 90%
- start failover: 95%
- hard Primary reserve: 15 recipient groups
- projected groups + reserve can trigger failover before the monthly quota is exhausted
- explicit Primary HTTP 429 may fall back to Backup for verified recipients
- ambiguous network failures never cross-OA retry
- no guessing of LINE identities across OAs

## Validation 2026-10-04
- Total VHV: 276
- Primary-ready: 211
- Backup-ready: 6
- Dual-ready: 5 (1.8%)
- 90% target: 249, gap 244
- 95% target: 263, gap 258
- Staff dual-ready: 1/15
- simulated remaining Primary quota 20 with reserve 15 and 10 recipient groups:
  5 routed Primary + 5 routed Backup, 0 blocked
- No live LINE message was sent during Phase 3.2 validation.
