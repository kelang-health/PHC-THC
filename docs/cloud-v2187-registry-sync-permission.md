# Cloud v2.0.187 — แก้ registry sync 503

สาเหตุ: service_role ไม่มี EXECUTE ของ private.community_key(text) ซึ่งถูกเรียกจาก trigger ตอน PATCH ทะเบียนบ้าน ทำให้การซิงค์หยุดด้วย HTTP 403 จาก Supabase และ Local แสดง 503

แก้โดยให้ EXECUTE เฉพาะ service_role ของ helper เดิม ไม่เปิดสิทธิ์ anon หรือเปลี่ยน RLS และไม่เปลี่ยน SECURITY DEFINER

Local Sync Center ปรับข้อความเมื่อ guard-apply ล้มเหลวให้แสดงข้อผิดพลาดแทน “กำลังสำรองข้อมูล” และปิดปุ่มส่งจนกว่าจะตรวจข้อมูลใหม่

ทดสอบ: เรียก helper ภายใต้ service_role สำเร็จ, unit tests registry guard 10 กรณีผ่าน, UI mock 503 แสดงสาเหตุ/ปิดปุ่มและตรวจใหม่เพื่อเปิดปุ่มผ่าน
