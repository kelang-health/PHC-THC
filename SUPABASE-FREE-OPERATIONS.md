# Supabase Free — แนวทางปฏิบัติและผลปรับปรุง

วันที่ 7 ตุลาคม 2569 — บัญชียังเป็น Pro ตามข้อมูลผู้ใช้ งานนี้ปรับระบบให้ไม่พึ่งฟีเจอร์ Pro ไม่ได้เปลี่ยนแพ็กเกจ Billing

## สิ่งที่ดำเนินการ

- kelang-health: ปรับ 49 ฟังก์ชันให้ปฏิเสธ NULL ในเงื่อนไขบทบาท โดยคงสิทธิ์ service_role ของงาน backend ที่ระบุไว้
- med-device-sharing: จำกัด SELECT ของ raw_data ใน 8 ตารางรายงานสำหรับ anon/authenticated; เก็บข้อมูลต้นทางเดิมไว้ ไม่ลบข้อมูล
- hp_import_records อ่านได้เฉพาะ HP ADMIN; hp_settings ให้สาธารณะอ่านเฉพาะหมวดรายงาน และให้ HP ADMIN อ่านหมวดภายใน
- Hospital Profile 1.29 เลือกเฉพาะคอลัมน์ที่จำเป็นทั้งการอ่านและผลตอบกลับการบันทึก เผยแพร่ GitHub Pages แล้ว
- เพิ่ม covering index ให้ foreign key ที่ Advisors ระบุ 31 รายการใน kelang-health และ 2 รายการใน med-device-sharing
- เพิ่ม Primary key ของ health_screening_target_cache_v2030 โดยใช้ unique index เดิม หลังตรวจไม่มี key ซ้ำ/NULL ไม่เพิ่มคอลัมน์และไม่สร้าง index ซ้ำ
- ไม่เปลี่ยนตาราง backend ที่ตั้งใจปิดด้วย RLS ไม่มี policy และไม่เปลี่ยนสิทธิ์รูปสาธารณะที่ตั้งใจเผยแพร่
- ไม่แก้ข้อมูล JHCIS ไม่ส่ง LINE และไม่สร้างบริการ/โครงการที่คิดค่าบริการเพิ่ม

## การทดสอบ

- ทดสอบบทบาท authenticated ที่ไม่มี profile: ถูกปฏิเสธครบ 49 ฟังก์ชัน ใน transaction แบบ read-only แล้ว rollback
- ทดสอบ Admin อ่าน preview ได้ และ user/staff อ่าน preview ไม่ได้
- API จริง: รายงาน 14 ตารางไม่มีข้อผิดพลาด; raw_data ถูกปฏิเสธทั้ง 8 ตาราง
- HP ADMIN ยังอ่านข้อมูลนำเข้าได้; บัญชีไม่มี assignment อ่านข้อมูลนำเข้าไม่ได้
- เจ้าของรูปอ่านรูปตนเองได้ แต่ไม่ได้รูปผู้อื่น; ไม่มี profile จัดการ/อ่านรูปไม่ได้
- anon ไม่อ่านหลักฐานยืม ไฟล์สำรอง และบุคลากรที่ไม่เผยแพร่ในกรณีที่ทดสอบ
- npm test ผ่าน 74 tests; build ผ่าน; เว็บที่เผยแพร่ผ่าน 31 UI checks ไม่มี page error หรือ overflow
- หลัง migration Advisors ไม่เหลือ unindexed_foreign_keys และ no_primary_key

## ข้อจำกัด Free ที่ใช้วางแผน

อ้างอิง https://supabase.com/pricing และ https://supabase.com/docs/guides/platform/backups

- Database 500 MB ต่อโครงการ; ขนาดที่ตรวจประมาณ 119 MB และ 20 MB ยังต่ำกว่าเพดาน ขนาดจริงควรดู Dashboard เพิ่ม
- File storage 1 GB; metadata ของไฟล์รวมสองโครงการประมาณ 48 MB ยังต่ำกว่าเพดาน
- Egress 5 GB และ cached egress 5 GB; 50,000 MAU — ยังไม่ได้ยืนยันการใช้งานรายเดือนจริง
- Free จำกัด 2 active projects และอาจพักโครงการหลังไม่มีการใช้งาน 1 สัปดาห์ ไม่ใช้การยิงคำขอจำลองเพื่อเลี่ยงการพัก
- ไม่มี automatic database backup/PITR/branching; ไม่พึ่ง Leaked password protection ซึ่งเป็น Pro ขึ้นไป
- ใช้นโยบายรหัสผ่านขั้นต่ำที่ Free รองรับ และ MFA ของ Supabase สำหรับบัญชีสำคัญตามความพร้อมของแอป ห้ามถือว่าการซ่อนปุ่มในเว็บแทนการตรวจสิทธิ์ที่ฐานข้อมูลได้

## สำรองข้อมูลโดยไม่ใช้ Pro

ไฟล์และเครื่องมืออยู่ภายนอก web root:

- D:/AppServ/private/supabase-free-backups — encrypted PostgreSQL custom archives, encrypted data/Storage archives และ manifests
- D:/AppServ/private/tools/run_supabase_free_backup.ps1 — สั่ง backup ทั้งสองโครงการและตรวจ archive
- D:/AppServ/private/tools/backup_native.py — pg_dump ที่ snapshot สอดคล้องกันภายในฐานข้อมูล
- D:/AppServ/private/tools/backup_free.py — ข้อมูลตาราง/โครงสร้างประกอบและ Storage พร้อมตรวจ hash/จำนวนแถว; ใช้สำเนาไฟล์เดิมเมื่อ metadata ไม่เปลี่ยนเพื่อลด egress
- D:/AppServ/private/tools/verify_native.py — ถอดรหัส ตรวจ SHA-256 และให้ pg_restore อ่านทุกส่วนของ archive โดยไม่เขียนฐานข้อมูล

เรียกด้วย PowerShell:

    & 'D:/AppServ/private/tools/run_supabase_free_backup.ps1'

เครื่องมือต้องใช้ Python environment เดิม, Node/npx, Supabase CLI 2.120.0 และบัญชี CLI ที่ล็อกอินมีสิทธิ์โครงการ ไม่มี Docker หรือค่าใช้จ่าย backup addon

กุญแจ recovery.key จำเป็นต่อการถอดรหัส จัดเก็บสำเนากุญแจแยกจากไฟล์ backup ในที่ปลอดภัย จำกัด ACL ของโฟลเดอร์ backup เฉพาะผู้ใช้ปัจจุบันและ SYSTEM

สำรองเมื่อมีข้อมูลใหม่และอย่างน้อยก่อนปรับระบบ; ถ้าใช้ทุกวันให้รันทุกวันเมื่อเครื่องเปิดอยู่ เครื่องมือยังไม่ได้ตั้งงานอัตโนมัติและไม่ลบ backup เก่าอัตโนมัติ เก็บสำเนานอกเครื่องด้วย การเก็บในดิสก์เครื่องเดียวไม่ใช่ disaster recovery

## การกู้คืนและสิ่งที่ยังค้าง

- ตรวจถอดรหัส/hash/จำนวนแถวและอ่าน archive แล้ว แต่ยังไม่ทดสอบ restore เข้าฐานข้อมูลใหม่จริง
- PostgreSQL archive ครอบคลุม schema แอปที่ระบุ พร้อม auth/storage/cron/migrations; ไม่ได้สำรอง secret/config ของ Dashboard หรือ source ของ Edge Functions ผ่าน pg_dump ให้เก็บ source/config ที่ควบคุมเวอร์ชันแยกด้วย
- ไฟล์ Storage ต้องกู้คืนจาก archive ไฟล์แยก; database dump มีเพียง metadata ของไฟล์
- Database snapshot กับการดาวน์โหลด Storage ไม่ใช่ snapshot เดียวกัน หากมีการแก้ไฟล์ระหว่าง backup ต้องตรวจความสอดคล้อง
- การ restore จริงควรทำบน Supabase/Postgres สภาพแวดล้อมแยกที่มี extensions/roles/schema ที่ตรงกัน ห้ามลอง restore ทับ production เพื่อพิสูจน์ว่า backup ใช้ได้
- ยังไม่ยืนยัน MAU/egress, paid addons และ Billing ก่อน downgrade ให้ดู Organization Billing/Usage ตรวจ 2 active projects และ addons แล้วอ่านผลกระทบบนหน้าลดแพ็กเกจ
- คำเตือน SECURITY DEFINER 149 รายการยังอยู่ เพราะ RPC ใช้สิทธิ์เจ้าของฟังก์ชัน การแก้ NULL ไม่ทำให้ชนิดฟังก์ชันเปลี่ยน ยังไม่ได้รับรองฟังก์ชันทั้ง 149 รายการว่าปลอดภัยครบทุกเส้นทาง
- คำเตือน RLS ไม่มี policy 27/28 ตาราง และ unused index ยังอยู่ตามการใช้งาน backend/สถิติ อย่าลบ index ใหม่ทันทีเพราะยังไม่มีสถิติใช้งาน
- งานนี้ไม่ได้เปลี่ยนแพ็กเกจจริงและไม่รับรองว่าไม่มีบิลค้างจากรอบ Pro เดิม
