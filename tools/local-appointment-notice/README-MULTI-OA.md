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


## Phase 3.3 Operational Onboarding Rollout
- Local version: 2.1.87.
- Manual tracker statuses: pending -> invited -> assisted.
- dual_ready is never manually set; it is derived from verified Primary + Backup mappings.
- Printable field kit includes the local Backup OA QR and community roster.
- Daily aggregate snapshot task: 08:00.
- Controlled Failover Drill is hard-coded dry-run only, max 2 recipients per community.
- Validation on 2026-10-04: 5 dual-ready recipients across 5 communities; drill passed 5/5, live_message_sent=false.
- OSM sent ledger remained 0 and LINE Hub sent count remained 28 during drill validation.
- Project closure rule: every completed change must report results, current status, risks/pending work, and any next development plan in the same completion report.


## Phase 3.4 Coverage Acceleration & Readiness Gate
- Local version: 2.1.88.
- Default Readiness Gate: 90%; Operational Goal: 95%.
- Default acceleration window: 14 days; stalled-community check: 3 days.
- Current validation: 276 VHV, 5 dual-ready (1.8%), 244-person gap to 90%, 258-person gap to 95%.
- Calculated onboarding target: 18 people/day for the 14-day window; community daily targets sum to 18.
- Priority ranking uses gap-to-target, current coverage, rollout activity, and stalled/not-started state.
- Current top priorities: โทกหัวช้าง, เหล่าบุญเกิด, หัวทุ่งสามัคคี, ผาลาด, กอกชุม.
- Current gate state: closed.
- Live Failover feature remains disabled and no live drill endpoint exists in Phase 3.4.
- The dashboard contains aggregate readiness data only; no CID, PID, raw LINE user ID, or message content.
