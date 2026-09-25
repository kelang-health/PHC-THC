## Cloud v2.0.116 — Admin portal performance fast path

- เปลี่ยนหน้า Admin ให้ใช้ `admin_community_fast_bundle_v2057` เป็นเส้นทางหลัก แทนการอ่าน `community_report_summary` โดยตรงตอนเปิดระบบ
- ย้ายการโหลด `volunteer_workload` ออกจาก critical path ของหน้าแรก: หน้าแรกอ่านเฉพาะจำนวน อสม. และโหลดรายละเอียด 275 แถวเมื่อเปิดเมนู “ทะเบียน อสม.” เท่านั้น
- คง fallback เดิมไว้เมื่อ Fast Bundle ใช้งานไม่ได้ เพื่อไม่ให้หน้า Admin ล้มเหลว
- ปรับ Report Refresh Queue ให้ไม่สร้าง snapshot ซ้ำ หากมี snapshot ใหม่ที่เริ่มหลังคำขอเปลี่ยนแปลงนั้นแล้ว โดยยังคงรอบตรวจทุก 5 นาที
- ไม่เปลี่ยน Auth, LINE, JHCIS, สิทธิ์ User/Staff หรือข้อมูลประชากร

## Cloud v2.0.81 — Clean municipal login redesign

- เปลี่ยนหน้า Login บน Cloud ตามภาพอ้างอิง: ส่วนหัวโลโก้เทศบาลและชื่อระบบ เวอร์ชันมุมขวา การ์ดต้อนรับสีขาว และแถบแนวคิดงานสุขภาพด้านล่าง
- ภาพอาคารเดิมเป็นภาพพื้นหลังตกแต่งเฉพาะหน้าเข้าสู่ระบบ ปรับท้องฟ้าและสีผ่าน CSS; ภาพไม่จำเป็นต่อการใช้งานฟอร์ม
- ถอน CSS Login v2.0.79/2.0.80 ที่ซ้อนกันออกจาก style.css แล้วแยกการจัดวางไว้ใน login-theme-v2081.css โดยไม่แก้รูปแบบหน้า Portal
- คงโลโก้เทศบาลของระบบเดิม รักษา DOM ฟอร์ม อสม./เจ้าหน้าที่/รหัสผ่าน และ LINE Login ทั้งสามช่องทางโดยไม่แก้ตัวจัดการ Auth
- ทดสอบเลย์เอาต์จริงทั้งมือถือและ PC ก่อนเผยแพร่ และยืนยันว่า Login ยังคงใช้งานได้เมื่อภาพตกแต่งไม่โหลด

## Cloud v2.0.80 — Unified responsive login overlay

- จัดหน้า Login ใหม่ตามภาพอ้างอิง: ภาพอาคารเป็นพื้นหลังเต็มหน้าจอ ไม่แสดงภาพเป็นแถบแยกใต้ฟอร์ม
- ผสานหัวระบบและฟอร์มเป็นการ์ดเดียวบนมือถือและเดสก์ท็อป แก้ความกว้างการ์ดบน PC
- ลดความสูงฟอร์มและจัดทางเลือก LINE สองปุ่มรองเป็นแถวเดียวบนมือถือ โดยรักษาทุกวิธีเข้าสู่ระบบและปุ่มช่วยเหลือ
- คงรูปที่ผู้ใช้ส่ง WebP 5.2 KB, มีพื้นหลังสำรองเมื่อรูปไม่โหลด และไม่แตะ Auth, LINE Login, MFA หรือ Supabase

## Cloud v2.0.79 — Branded municipal login background

- ปรับเฉพาะหน้า Login: ภาพอาคารจากไฟล์ที่ผู้ใช้ให้มา (WebP 5.2 KB) พร้อมพื้นหลังฟ้าพาสเทล การ์ดสีขาว และหัวระบบบนมือถือ
- คงฟอร์มจริง 2 โหมด (อสม./เจ้าหน้าที่), รหัสผ่าน/ปุ่มแสดงรหัส และ LINE Login เดิม ไม่สร้างปุ่มหรือเส้นทาง Auth ใหม่
- ภาพเป็น CSS decoration; กรณีภาพไม่โหลดหรือ Data Saver ยังมีพื้นหลังไล่สีและแบบฟอร์มใช้งานได้
- ไม่โหลดภาพพื้นหลังหลังเข้าสู่ระบบ และไม่แก้ Supabase, Auth, MFA, LINE, JHCIS หรือสิทธิ์ใด ๆ

## Cloud v2.0.78 — Community list paging, search, and natural sorting

- แบ่งหน้า Staff Community Workspace: อสม. 10 คน/หน้า, บ้านทั้งหมด/ไม่มี อสม./ต้องตรวจ 15 หลัง/หน้า
- ค้นหา อสม. ด้วยชื่อ–นามสกุล และบ้านด้วยบ้านเลขที่/HCODE พร้อมเรียงชื่อไทยหรือบ้านเลขที่แบบตัวเลขตามธรรมชาติ
- Render เฉพาะการ์ดหน้าปัจจุบัน เก็บเงื่อนไขค้นหาและหน้าเดิมเมื่อสลับเมนูและเปิด/ปิดรายละเอียดบ้าน
- รวมกับ Phase 3 population lazy RPC: ไม่เรียก RPC เพิ่มเมื่อกดถัดไปหรือค้นหา
- ไม่เปลี่ยนสิทธิ์ของ Staff/User, Auth, LINE Login, JHCIS หรือการมอบหมายบ้าน

## Cloud v2.0.77 — Phase 5 Training Completeness Dashboard

- เพิ่มหน้าสรุปประวัติการอบรมในเมนู “ผลงาน” แบบกดเปิดเพื่อโหลดเฉพาะเมื่อใช้งานจริง สำหรับ Admin, Staff และ User ตาม RLS เดิม
- แสดงจำนวน อสม. ที่มีข้อมูลอบรม จำนวนรายการ ชั่วโมงรวม และตารางแยกชุมชนตามสิทธิ์ของผู้ใช้ โดยไม่นับกิจกรรมที่ยกเลิก
- ดึงข้อมูล Cloud แบบอ่านอย่างเดียวจาก volunteers และ volunteer_training_history; ไม่แตะ Auth/LINE Login/JHCIS/การมอบหมายบ้าน
- ตรวจสอบข้อมูลต้นทาง Phase 5: Local มีผู้เข้าร่วมอบรม 71 รายการ Cloud มี 71 รายการ เทียบ PID และ event_id ตรงกัน; ข้อมูลบันทึกจริงมีเพียง 1 กิจกรรม
- เพิ่ม regression test ของ dashboard เพื่อยืนยันการรวมผล การไม่รั่วข้ามชุมชน การไม่นับกิจกรรมยกเลิก และไม่ใช้การดึงประวัติรายคนแบบ N+1
## Cloud v2.0.76 — Phase 4 Field Acceptance and Training Visibility

- ลดความสูง Bottom Navigation บนมือถือจาก 68px เป็น 60px พร้อมลด padding/icon เล็กน้อย เพื่อคืนพื้นที่เนื้อหาโดยยังคง Safe Area และปุ่ม 5 เมนู
- ทำให้ปุ่ม “ประวัติการอบรม” มองเห็นได้ชัดในหน้า “ผลงาน” ของ Staff/User และให้หน้า “บ้าน” ของ User ระบุ “โปรไฟล์ / การอบรม” ชัดเจนแม้หน้าจอ 390px
- ตรวจสอบฐานจริงว่าบัญชี User/Staff เชื่อม volunteer_pid ครบตามบัญชี active; ประวัติอบรมจะแสดงจาก volunteer_training_profile และแสดง “ยังไม่มีประวัติ” เมื่อไม่มีข้อมูลจริง
- เพิ่ม Phase 4 browser acceptance test ตรวจความสูงเมนู, overflow, 5 เมนู และ training shortcut ที่ 390px
- ยืนยัน JHCIS ยังคง read-only, ไม่แก้ Auth/LINE Login และไม่เปลี่ยน volunteer_pid
## Cloud v2.0.75 — Phase 3 Population Reconciliation and Mobile Validation

- ตรวจสอบข้อมูลบ้านไม่มี อสม. เทียบกับ JHCIS แบบอ่านอย่างเดียว โดยคงนิยามประชากรในงานบริการและไม่เปิดเผยข้อมูล Type 2/4 หรือผู้จำหน่ายเป็นประชากรปัจจุบัน
- ลด critical path หน้า “สรุปชุมชน”: โหลดบ้านก่อน และดึงจำนวนสมาชิกเมื่อเปิดเมนูบ้าน/บ้านไม่มี อสม./อสม. เท่านั้น
- ใช้ shared single-flight สำหรับจำนวนสมาชิก จำกัดการ render ซ้ำเมื่อกดเมนูเร็ว และแสดงสถานะกำลังโหลด/ข้อผิดพลาด
- แสดงคำอธิบายชัดเจนเมื่อสมาชิกในงานบริการเป็น 0 คน และแสดงข้อผิดพลาดหากโมดูลรายละเอียดบ้านยังไม่พร้อม
- เพิ่ม regression browser test สำหรับหน้าจอจำลอง 320–1024 px, เมนูครบตาม role, card list และ UI render benchmark
- คง Auth, LINE Login, JHCIS read-only และไม่แก้ไขการมอบหมายบ้านใน Cloud
## Cloud v2.0.74 — Phase 2 Mobile Community Completion

- ปรับ Bottom Navigation เป็นโครงสร้างเดียว ใช้ SVG icon จริง ชื่อสั้นบนมือถือ และรองรับ iPhone Safe Area
- เปลี่ยน “ตรวจข้อมูล” และ “ทะเบียน อสม.” ใน Community Workspace จากตารางเลื่อนแนวนอนเป็น Mobile Card List
- บ้านไม่มี อสม. ใช้ชุดข้อมูลบ้านเดียวกับบ้านปกติและผสานจำนวนสมาชิกจาก community_household_cards_v1841 ด้วย UUID ของบ้าน
- เพิ่มปุ่มเปิดบ้าน/สมาชิกจากการ์ดชุมชน โดยคงสิทธิ์ Staff/User และไม่เปลี่ยน volunteer_pid
- จำกัดชุมชนอื่นในหมู่เดียวกันเป็นดูอย่างเดียว และไม่เปิดรายละเอียดประชากรเกินสิทธิ์
- เพิ่ม community-workspace-v2074.mjs เป็น presentation helper เพื่อลดการซ้ำของ DOM/render logic
## Cloud v2.0.59 — Phase 2I Navigation & Session Resilience

- ผูกเมนู Portal กับ URL `?view=...`; การกดเมนูสร้าง browser history และ Back/Forward คืนหน้าที่ถูกต้องโดยไม่ reload ทั้งระบบ
- Refresh/BFCache คืนหน้าล่าสุดเฉพาะเมนูที่ role ปัจจุบันมีสิทธิ์; ถ้า URL ขอหน้าที่ไม่มีสิทธิ์จะกลับ `overview` และแก้ URL ให้ตรง
- Logout ล้าง navigation state กลับ `overview` เพื่อไม่พาสิทธิ์/หน้าจอของ session ก่อนหน้าไปยังการเข้าสู่ระบบครั้งถัดไป
- เพิ่ม shared single-flight session refresh และ proactive refresh เมื่อ token ใกล้หมดอายุ
- เมื่อ bootstrap โปรไฟล์พบ 401/JWT expiry จะ refresh session และ retry การเปิด Portal เพียง 1 ครั้ง; permission error จริงยังคงแสดง ACCESS ERROR
- รองรับ `TOKEN_REFRESHED`, `popstate` และ `pageshow` เพื่อให้ session/navigation เสถียรบน mobile browser และ browser Back/Forward cache

## Cloud v2.0.45 — Telegram Security & New House Alerts

- แจ้งผู้ดูแลผ่าน Telegram เมื่อมีการเพิ่มบ้านเลขที่ใหม่จากระบบภาคสนาม โดยส่งเฉพาะบ้านเลขที่ หมู่ และชุมชนสำหรับตรวจสอบ
- เปลี่ยนการเข้าสู่ระบบด้วยรหัสผ่านให้ผ่าน Edge Function ที่ไม่บันทึกรหัสผ่าน และแจ้ง Telegram เมื่อบัญชี Cloud กรอกรหัสผิดตั้งแต่ครั้งที่ 3 ภายใน 10 นาที
- เก็บตัวนับความปลอดภัยเป็น HMAC เท่านั้น ไม่เก็บชื่อเข้าสู่ระบบหรือ IP แบบอ่านกลับได้ และล้างตัวนับเมื่อเข้าสู่ระบบสำเร็จ

## Cloud v2.0.44 — Work Page Deferred Profile Assets

- ให้หน้า “ผลงาน” แสดง report snapshot และ assignment summary ก่อนข้อมูลโปรไฟล์ อสม. ที่ไม่จำเป็นต่อการตัดสินใจหลัก
- เลื่อน `volunteer_registry_profiles_v2` ออกจาก critical navigation path ของหน้า Work สำหรับ user/staff เมื่อยังไม่มี cache
- โหลดรูป อสม. จาก Storage เมื่อเปิดโปรไฟล์ หรือหลังหน้า Work ว่างจากงานหลักแล้ว; signed URL ยังคง cache 25 นาที
- ยกเลิก deferred profile/photo request อัตโนมัติเมื่อผู้ใช้ออกจากหน้า Work เพื่อลด request ที่ไม่จำเป็น
- จัด cache key ของ config/auth/LINE/app ให้เป็น release เดียวกันเพื่อลดการใช้โมดูลค้างจากรุ่นก่อน

## Cloud v2.0.43 — Household Residence & Member Workflow

- Staff เห็นปุ่มเพิ่มบ้านและใช้โควตาจาก `house_add_quota` ตามสิทธิ์จริง
- แยกสถานะสมาชิกบ้านเป็น ติดต่อไม่ได้ / ออกจากพื้นที่ / แจ้งย้ายทะเบียน โดยไม่ลบสมาชิกออกจากทะเบียนบ้านทันที
- เพิ่มสมาชิกใหม่ด้วยข้อมูลขั้นต่ำ CID 13 หลัก + ชื่อ + นามสกุล + วันเกิด พร้อมตรวจ checksum และป้องกันสร้างคนซ้ำ
- คำขอสมาชิกใหม่รอ Staff/Admin ตรวจ; เมื่อจับคู่ JHCIS สำเร็จจะแสดง `source_pcucode + PID` แทนการใช้ CID เป็นตัวระบุงานประจำ
- ใช้ migration `20260915060000_household_residence_member_v2043.sql`; JHCIS ยังคง read-only
- ปรับเลข Release หน้า Cloud และ cache key หลักเป็น v2.0.43

## Cloud v2.0.33 — Stabilization & Validation

- เตือนก่อนคัดกรองซ้ำ โดยแยกกรณีมีผลของวันนี้ และบันทึกเป็นประวัติรายการใหม่เสมอ
- Staff สลับดู “ของฉัน / ราย อสม. / ชุมชนของฉัน” โดยเซิร์ฟเวอร์ตรวจว่า อสม. อยู่ในชุมชนเดียวกัน
- แยกผู้รับผิดชอบ, Staff ดูแลแทน และคิวไม่ทราบชุมชนสำหรับ Admin พร้อมสาเหตุที่ตรวจสอบได้
- แบ่งรายการคัดกรองและรายการงานครั้งละ 50 ราย ยกเลิกคำขอเก่าเมื่อเปลี่ยนตัวกรอง และคง snapshot สำหรับ Dashboard
- เพิ่มดัชนีเฉพาะเส้นทางค้นหาชุมชนจากผล EXPLAIN โดยไม่เขียนกลับ JHCIS และไม่เปลี่ยนผู้รับผิดชอบอัตโนมัติ

## Cloud v2.0.31 — Fast report snapshots
- Dashboard และศูนย์ติดตามงานอ่านผลสรุปจาก snapshot ตามสิทธิ์ แทนการ `count/sum` สดทุกครั้ง
- สร้างข้อมูลรุ่นใหม่แล้วสลับใช้งานแบบ atomic จึงไม่มีช่วงตารางว่างระหว่างประมวลผล
- อัปเดตอัตโนมัติภายใน 5 นาทีเมื่อข้อมูลเปลี่ยน และประมวลผลเต็มเวลา 00:05 น. (เวลาไทย)
- เพิ่มปุ่มประมวลผลตัวเลขสรุปสำหรับ Admin พร้อมเวลาอ้างอิงบนหน้าจอ
- ใช้ Auth/PID/บ้านชุดเดิม, RLS แยกขอบเขต user/staff/admin และ JHCIS ยังเป็น read-only

## Cloud v2.0.30 — Concurrent field stability
- เป้าหมายคัดกรองภาคสนามอ่านจาก denormalized cache ผ่าน explicit-scope RPC แทน nested RLS view
- User bootstrap ลด request ที่ไม่จำเป็น และงานสุขภาพไม่โหลด Dashboard summary พร้อมรายชื่อ
- History/หลังบันทึกถูก stagger เพื่อลด concurrent spike; timeout ของ target RPC retry แบบ jitter จำกัดครั้ง
- Cloud sync และ Admin target changes refresh target cache อัตโนมัติ

## v2.0.29
- Warn before opening an NCD screening when the person already has a recorded screening date.
- Show the latest screening date in Thai format and ask whether the user wants to screen again.
- Cancelling the warning keeps the prior result intact and does not open a new NCD form; elderly same-day flow to 9 domains remains unaffected.

## v2.0.27
- Health now opens the precomputed target list by default on every entry; User/Staff cannot fall through to the unrestricted all-population filter.
- Care Dashboard age-group shortcuts use the Admin-enabled target worklist instead of bypassing target configuration.
- With default settings, people under 35 stay hidden until Admin explicitly enables their age group.

## v2.0.26
- Population target aligned to JHCIS typelive 1/3 + nation 99.
- Default field list uses precomputed age 35+ targets for fast mobile response.
- Admin can enable/disable 0-5, 6-14 and 15-34 target groups; age 35+ remains always enabled.
- Added slim target worklist to avoid heavy history joins on first load.

## v2.0.25
- กำหนดนิยามประชากร operational กลางของระบบเป็น JHCIS `person.typelive` = 1 หรือ 3 เท่านั้น
- ปรับ Health Worklist, NCD base eligibility, Field Work และ Screening Plan ให้ใช้ฐานประชากรเดียวกัน
- ล้าง Screening Plan ของ type อื่นและ pre-compute ใหม่เฉพาะ type 1/3; การตรวจสอบสถานะอยู่จริงยังเป็นชั้น review แยก
- ปรับ Local Health Sync ให้รอบถัดไปคงนิยาม type 1/3 และไม่เพิ่มเงื่อนไขสัญชาติ/หมู่บ้านเข้าในตัวหารประชากรโดยอัตโนมัติ

## v2.0.24
- ปรับหน้าคัดกรองผู้สูงอายุ 9 ด้านบน iPhone ให้ทุกส่วนอยู่ภายในกรอบจอ ไม่เกิด horizontal overflow
- เปลี่ยนปุ่มขั้นตอน 1–9 บนมือถือเป็น grid 5+4 พร้อมบังคับข้อความ กล่องคำถาม และปุ่ม ก่อนหน้า/ถัดไป ให้ย่อและขึ้นบรรทัดใน viewport
- ปรับหน้าเลือกประชากรคัดกรองให้โหลดรายชื่อเป้าหมายก่อน โดยไม่รอสรุป Dashboard และประวัติการคัดกรอง
- ย้ายข้อมูลสรุปและประวัติให้โหลดตามหลังแบบ background เพื่อลดเวลารอก่อนเริ่มงานภาคสนาม

## v2.0.23
- เพิ่ม Screening Plan แบบ pre-compute เพื่อเตรียมกลุ่มอายุและ route ของประชากรไว้ก่อนใช้งานภาคสนาม
- แตะรายชื่อแล้วเปิดแบบคัดกรองจาก worklist ที่เตรียมไว้ทันที โดยไม่สร้าง screening session เพียงเพราะเปิดดู
- สร้าง session แบบ lazy เฉพาะเมื่อเริ่มบันทึก Growth/DSPM/2Q/ผู้สูงอายุ 9 ด้าน และคง server validation ตอนบันทึก
- หลัง Health Sync จะ refresh แผนคัดกรองทั้งชุดหนึ่งครั้ง พร้อม index สำหรับ same-day NCD เพื่อรองรับผู้ใช้พร้อมกันจำนวนมาก

## v2.0.22
- จำกัดข้อความ/ปุ่มโหมดทดสอบและการรีเซ็ตรายบุคคลให้ Admin เท่านั้น ทั้ง UI และฐานข้อมูล
- แยก NCD save ออกจาก post-save dashboard refresh: บันทึกสำเร็จแล้วจะไม่แสดง timeout จากรายงานเป็นข้อผิดพลาดการบันทึก
- รีเฟรชรายชื่อ/ประวัติ/สรุปแบบเบื้องหลังทีละงาน ลด query พร้อมกันหลังบันทึก
- เพิ่มดัชนี health audit และ recent NCD สำหรับเส้นทางบันทึก/รีเฟรชที่พบบ่อย

## v2.0.21
- ซ่อม View health_person_worklist_active_v1847 ให้มี has_cvd/cvd_population_eligible และ reload PostgREST schema
- ปรับ Health worklist fallback ให้เลือกคอลัมน์ตาม View รุ่นจริง ไม่เกิด column does not exist ซ้ำ
- fallback เฉพาะ schema/relation errors เพื่อไม่ซ่อน network หรือ permission errors
- อัปเดต footer/version note ให้ตรงกับ Cloud รุ่นปัจจุบัน

## v2.0.20
- Add a single Staff-only performance scope selector: “ผลงานของฉัน” and “ผลงานชุมชน”.
- Synchronize the selected scope across health performance, field-work reporting, and the overview care dashboard.
- Keep User fixed to self scope and Admin fixed to all permitted areas; RLS permissions are unchanged.
- Remove the duplicate Staff scope selector inside the field-work reporting block.

## v2.0.19
- Move the health-area summary from the Health menu into the renamed “ผลงาน” menu.
- Make Health open directly at population selection and the screening worklist.
- After a successful NCD save, close the form, refresh the worklist, scroll to the remaining people, and focus the next screening action.
- Keep risk/urgent feedback visible above the worklist while avoiding a blocking post-save dialog during field work.

## v2.0.18
- Compact the mobile LINE login area so buttons stay balanced and labels do not wrap awkwardly.
- Shorten the three LINE choices to “เปิดแอป LINE”, “LINE ผ่านเว็บ”, and “LINE เดิม (LINE OA)”.
- Reduce duplicated guidance and spacing while preserving OAuth, web fallback, legacy LINE OA, and normal login behavior.
- Keep all three LINE methods available without changing authentication logic.

## v2.0.17
- Add an explicit “ใช้ระบบ LINE เดิม” option alongside LINE app and LINE web login.
- Preserve the existing LINE OA LOGIN-code flow as a user-selectable fallback, not only an automatic emergency fallback.
- Safely switch from prepared OAuth UI to the legacy LINE OA flow without leaving a stale OAuth browser state.
- Keep normal username/password login unchanged.

## v2.0.16
- Improve iOS Safari guidance when LINE Universal Link does not hand off to the LINE app.
- Make the web-login fallback more explicit: “ใช้ LINE ผ่านเว็บแทน (หากแอปไม่เปิด)”.
- Keep Android/PC flows and existing OAuth fallback behavior unchanged.

## v2.0.15
- Harden LINE Login across iOS, Android, LINE in-app browser, and common external/in-app browsers.
- Keep the primary user-tap authorization link for Universal Links / App Links; do not use JavaScript redirect for app handoff.
- Add a mobile "use LINE on the web" fallback using disable_auto_login=true for environments where app handoff or auto login fails.
- Detect common constrained in-app browsers and show Safari/Chrome guidance without blocking login.
- Recreate a fresh OAuth transaction after cancel, browser failure, expired browser state, or session-claim failure.
- Keep normal username/password login and LINE OA LOGIN-code fallback available.

## v2.0.14
- Improve smartphone LINE Login: pre-create the OAuth transaction, then let the user tap the LINE authorization link directly so iOS Universal Links / Android App Links can open the installed LINE app when supported.
- Remove JavaScript redirect to the LINE authorization URL from the normal login path.
- Keep PC LINE Login/QR, normal username/password login, and LINE OA device-code fallback unchanged.

## v2.0.13
- Add Admin LINE Login readiness/settings panel without exposing Channel Secret to the browser.
- Report presence-only status for LINE Login Channel ID/Secret and the callback URL.
- Keep normal login and LINE OA LOGIN-code fallback while one-tap OAuth is not configured.
- Allow the known production app origin to reach the fallback flow even before APP_BASE_URL is stored as an Edge Secret.

## v2.0.12
- Add one-tap LINE Login through LINE Login OAuth/OpenID Connect for users already linked to OSM-PHC.
- Keep Supabase Auth/profile as the authorization source; LINE identity only maps to an existing active user_line_links record.
- Use a short-lived state/nonce/browser-secret exchange; raw LINE user ID never returns to the browser.
- Keep the existing LINE OA LOGIN code flow as an automatic fallback until LINE Login channel credentials are configured.

## v2.0.11
- Restore defensive previous NCD screening fallback so JHCIS/J-Report previous measurements remain visible when the worklist projection is missing them.
- Keep the previous-body reuse action for height, weight and waist only; BP/glucose are never auto-reused.
- Move NCD save action to the physical end of the form (non-sticky) to stop covering mobile working space.
- Disable NCD save until all required measurement/behavior fields are complete; 2Q remains optional.


## v2.0.10
- Fix Operation Center panel scope: “ศูนย์ปฏิบัติการ” is now mounted inside the `ผลงาน/ติดตาม` (`work`) panel only.
- Prevent the Operation Center from leaking across overview/community/volunteer/health tabs by keeping it as a child of the hidden work panel.
- Refresh Operation Center actions when opening `ผลงาน/ติดตาม`; LINE-link guidance now points back to that menu.


## v2.0.9
- Final mobile UI polish before closing field-test phase: keep five bottom-nav labels readable without shrinking below the elder-friendly target.
- Render Field Work & Reporting tables as labeled cards on narrow screens while preserving desktop tables.
- Standardize user-facing LINE wording to “LINE OA ของหน่วยงาน”.
- Raise remaining small touch targets and make elderly 1–9 wizard tabs horizontally scrollable at 48px targets on narrow screens.


## v2.0.8
- Treat every OSM-PHC screening recorded before 2026-10-01 as test-mode work and exclude it from production performance after go-live.
- Show per-person test-reset controls across every age-screening route and the NCD form; preserve JHCIS/J-Report/3Doctor history.
- Archive reset test rows and audit every reset; add an Admin bulk reset preview/action before go-live only.
- Allow pre-go-live test NCD results to unlock same-day elderly 9-domain testing.

## v2.0.7
- Replace the generic elderly 9-domain Normal/Observation form with a mobile 1–9 Community Screening wizard for VHV/Staff/Admin.
- Derive risk server-side from Mini-Cog, TUG/fall history, nutrition, vision, Finger rub, 2Q plus, urinary, ADL and oral-health inputs; VHV no longer chooses risk status directly.
- Auto-create Staff/Admin follow-up for risk results, with red priority for the 2Q-plus suicide-risk item; screening notifications remain in-app and do not use Telegram.
- Preserve per-domain save/resume and a final 9-domain summary.

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
- เพิ่ม LINE Login แบบรหัสใช้ครั้งเดียว 3 นาที สำหรับบัญชีที่เชื่อม LINE OA ของหน่วยงาน ไว้แล้ว; Supabase Auth/RLS ยังคงเป็นแหล่งยืนยันตัวตนหลัก
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
