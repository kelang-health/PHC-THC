# Changelog

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
