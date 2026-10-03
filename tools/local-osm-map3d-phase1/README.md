# Local OSM-PHC — Map 3D v2.1.77

โมดูลแผนที่สุขภาพสำหรับ Local OSM-PHC เท่านั้น หน้าแผนที่เป็น Admin read-only และไม่มีคำสั่งเขียน Cloud หรือ JHCIS

## ฟังก์ชันที่ติดตั้ง
- 2D / 3D พร้อม MapLibre GL ที่เก็บไฟล์ library ไว้ใน Local
- แผนที่ฐาน OpenStreetMap และ Esri World Imagery
- บ้านจาก Local OSM-PHC, clustering, ค้นบ้านเลขที่/HCODE/HID และเปิดข้อมูลบ้านเดิม
- polygon 16 ชุมชนจาก Local boundary snapshot
- OSM building footprint แบบ 3D extrusion; โหลดเฉพาะชุมชนที่เลือก
- building cache: memory 15 นาที, disk 24 ชั่วโมง และ stale fallback สูงสุด 30 วันเมื่อ Overpass ใช้ไม่ได้
- ชั้นงาน NCD แบบ aggregate ระดับบ้านเท่านั้น ไม่มีชื่อบุคคลหรือค่าความดัน/น้ำตาลรายบุคคล
- DEM terrain + hillshade แบบเปิด/ปิด
- RainViewer radar แบบเปิด/ปิด ใช้เป็นบริบทสภาพอากาศ ไม่ใช่การพยากรณ์น้ำท่วม
- responsive toolbar สำหรับ desktop/mobile

## Data flow
Browser -> Local FastAPI -> Local household database / Local Tracking Center / Local boundary snapshot

แหล่งภายนอกที่ใช้เฉพาะการแสดงผล:
- OpenStreetMap raster tiles
- Esri World Imagery raster tiles
- OpenStreetMap Overpass building footprints
- AWS Terrarium elevation tiles
- RainViewer radar tiles

ไม่มี Supabase service-role key ใน browser และหน้า Map 3D ไม่เพิ่ม Cloud write path

## Privacy
ชั้น NCD ส่งเฉพาะ aggregate ต่อ HCODE เช่นจำนวนกลุ่มเป้าหมาย จำนวนต้องติดตาม และระดับงานสูงสุดของบ้าน ไม่ส่งชื่อ PID/CID หรือค่าทางคลินิกรายบุคคลไปยังหน้าแผนที่

## Fail-safe
ถ้า OSM/Esri/DEM/RainViewer/Overpass ใช้ไม่ได้ ข้อมูลบ้านและขอบเขต Local ยังคงอยู่บนแผนที่ โดยมีพื้นหลัง fallback; ฟังก์ชัน external overlay ถูกออกแบบให้ล้มแยกจากข้อมูล Local

## Validation snapshot
- Local houses with coordinates: 4,276
- NCD aggregate: 6,181 persons -> 3,314 households
- OSM building test in ชุมชนกอกชุม: 106 footprints
- Building cache verified network -> disk after memory clear
- DEM, RainViewer radar and Esri imagery test tiles returned HTTP 200
- Unauthenticated Map 3D endpoints return HTTP 401

## Deliberately not implemented
ยังไม่สร้างคะแนนหรือสี “เสี่ยงน้ำท่วม” จาก DEM + เรดาร์ฝน เพราะข้อมูลสองชนิดนี้ไม่เพียงพอสำหรับ hazard classification ที่น่าเชื่อถือ ต้องเพิ่ม authoritative flood/hazard layer ก่อน
