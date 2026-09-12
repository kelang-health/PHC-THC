
## v2.0.6
- DSPM remains a simple 5-domain preliminary screen for VHV; abnormal results create staff/admin follow-up automatically and appear in reporting.
- Added admin-controlled optional 15–34 screening campaign with start/end dates and NCD / mental-health toggles.
- Campaign work is excluded from primary Operational Task Completion. NCD campaign is limited to adults 18–34; mental-health 2Q is available 15–34.
## 2.0.5 - 2026-09-12
- Add appointment response controls for linked Admin/Staff/VHV accounts: accept, decline, acknowledge.
- Show the saved appointment response on the overview using the existing Supabase Auth/RLS scope.
- Complete messaging E2E workflow validation for LINE/Telegram transport and privacy guard.

## 2.0.4 - 2026-09-12
- Add version-locked Department of Health child growth/nutrition interpretation from the JHCIS/HDC operational reference tables.
- 0–5 years: W/A + H/A + W/H; 6–14 years: H/A + W/H using the DOH 6–19 B.E.2564 reference.
- Keep raw weight/height plus reference version and structured nutrition result for audit/history; do not replace the current DOH reference with BMI-for-age.
- Include interpreted growth fields in Cloud → Local Excel export.

## 2.0.3 - 2026-09-12
- Replace blocking native alerts after child growth/development saves with non-blocking auto-dismiss confirmation.
- Keep clinically relevant development result visible inline after save.
- Child nutrition remains raw-only until an approved growth reference dataset is installed.

# v2.0.2 — 2026-09-12

- Compact mobile bottom navigation into one 5-item row.
- Add one-tap copy button for `LINK XXXXXXXX` when linking LINE accounts.
- Keep the existing 10-minute account-link code lifetime and LINE Login 3-minute approval lifetime unchanged.

# Changelog

## 2.0.1 — 2026-09-12

- เพิ่มการเชื่อม LINE สำหรับบัญชี admin โดยใช้ workflow เดียวกับ user/staff
- เพิ่ม LINE Login แบบรหัสใช้ครั้งเดียว 3 นาที สำหรับบัญชีที่เชื่อม NCD OA ไว้แล้ว; Supabase Auth/RLS ยังคงเป็นแหล่งยืนยันตัวตนหลัก
- เพิ่ม LINE webhook รองรับ `LOGIN XXXXXXXX` และคง `LINK XXXXXXXX` สำหรับเชื่อมบัญชี
- เพิ่ม LINE dispatch worker อัตโนมัติทุก 5 นาที และ health check สำหรับ Channel access token/Webhook
- ไม่เก็บ LINE user ID ดิบใน browser และไม่ใช้ LINE user ID เป็นรหัสผ่าน

## 2.0.0 — 2026-09-12

- เพิ่ม Field Work & Reporting Center สำหรับ user / staff / admin พร้อม drill-down งานจากภาพรวม → ชุมชน → อสม. → รายบุคคล
- เพิ่ม Unified Work View ครอบคลุม Growth, Child Development, NCD และ Elderly 9 domains พร้อมสถานะ due / partial / complete
- แยก Operational Task Completion ออกจาก Follow-up Closure เพื่อไม่ลดคะแนน อสม. ที่พบความเสี่ยงมาก
- เพิ่มงานติดตาม open / in_progress / done พร้อม resolution note และ Audit log
- เพิ่มส่งออก Excel หลายชีตจาก Cloud ตามขอบเขตสิทธิ์ โดยไม่ส่งออก CID, HN, เบอร์โทร, ที่อยู่ หรือ LINE ID
- เพิ่ม export views สำหรับ Local Reporting เพื่อใช้ Cloud → Local รายงานโดยไม่เขียนกลับ JHCIS

## 1.9.0 — 2026-09-12

- เพิ่ม workflow “แจ้งเพิ่มสมาชิกบ้าน” พร้อม validation ฝั่ง browser + RPC, Thai CID checksum, masked display, encrypted storage, keyed hash, duplicate checks, Admin review และ audit trail
- เพิ่ม Notification Center กลาง และ Telegram Admin outbox; ไม่มี Bot Token/secret ใน frontend
- เพิ่ม LINE account linkage ด้วย one-time code, signed webhook, individual/broadcast queue, custom groups, appointment support และ delivery status
- เพิ่ม age-based screening route: 0–5 Growth + Development, 6–14 Growth, 15–34 reserved, 35–59 NCD, 60+ NCD ก่อน Elderly 9 domains
- เพิ่ม Growth history โดยเก็บค่าดิบก่อน; ยังไม่ตีความภาวะโภชนาการจนกว่าจะติดตั้ง reference tables ที่อนุมัติ
- เพิ่ม developmental screening 5 domains แบบ Normal / Observation / Not assessed และ follow-up เมื่อพบข้อสังเกต
- เพิ่ม Elderly 9-domain screening แบบ partial save / resume และ follow-up worklist
- เพิ่ม Admin Action Center summary สำหรับ member requests, LINE และ notifications
- รักษา JHCIS เป็น read-only source; pending member request ไม่ถูกนับใน population/KPI
- ปรับ Cloud UI version เป็น 1.9.0 และเพิ่ม mobile-first controls

### Required server configuration

- Telegram: `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ADMIN_CHAT_IDS`, `APP_BASE_URL`
- LINE: `LINE_CHANNEL_SECRET`, `LINE_CHANNEL_ACCESS_TOKEN`, `APP_BASE_URL`
- Supabase Edge Functions use server-provided `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`; service-role key must never be exposed in frontend
