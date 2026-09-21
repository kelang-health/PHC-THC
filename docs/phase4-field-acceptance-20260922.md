# Phase 4 — Field Acceptance & Data Quality (22 ก.ย. 2569)

## ขอบเขตตรวจรับ
- Staff/User mobile navigation และพื้นที่เนื้อหาบนหน้าจอ 390px
- การมองเห็นประวัติการอบรมของบัญชี User/Staff
- การคงสิทธิ์เดิม, JHCIS read-only และ population reconciliation จาก Phase 3
- Performance regression ของ Community Workspace และ Mobile Card renderer

## ผลตรวจรับ UI
- ภาพ iPhone จริงจากผู้ใช้ยืนยันว่า v2.0.75 ใช้งานเมนู 5 รายการได้ แต่แถบล่างสูงเกินจำเป็น
- v2.0.76 ลดปุ่มจาก 68px เหลือ 60px และแถบรวมเหลือ 71px ใน viewport 390px (ไม่รวม native safe-area)
- Browser acceptance ผ่านที่ 320, 375, 390, 430, 768 และ 1024px โดยไม่เกิด horizontal overflow
- Staff/User มี 5 เมนู; Admin มี 5 เมนูตาม role เดิม

## ประวัติการอบรม
- แหล่งข้อมูลคือ RPC volunteer_training_profile(source_pid) จาก volunteer_training_history
- User/Staff active ที่ตรวจใน Cloud มี volunteer_pid เชื่อมทะเบียนครบ
- หน้า “ผลงาน” แสดง “ประวัติการอบรม ▾” ชัดเจนสำหรับ User/Staff
- หน้า “บ้าน” ของ User แสดง “โปรไฟล์ / การอบรม ▾”
- หากไม่มีประวัติจริง ระบบแสดง “ยังไม่มีประวัติการอบรม” โดยไม่สร้างข้อมูลจำลอง

## Data Quality / Performance
- บ้านไม่มี อสม. 5 หลังในชุมชนหนองวัวเฒ่ายังคงใช้เกณฑ์ประชากรบริการเดียวกับบ้านปกติ
- ไม่เปลี่ยน typelive, dischargetype, volunteer_pid หรือข้อมูล JHCIS
- Community summary โหลดบ้านก่อน; population RPC โหลดแบบ lazy เมื่อเปิด บ้าน/บ้านไม่มี อสม./อสม.
- Renderer benchmark: บ้าน 126 หลังประมาณ 2.8–3.1ms, อสม. 20 คนประมาณ 0.8–0.9ms ใน Chrome headless ของเครื่องทดสอบ

## Acceptance
- Static/syntax checks: PASS
- Phase 3 regression: PASS
- Phase 4 mobile acceptance: PASS
- Production release target: Cloud v2.0.76
