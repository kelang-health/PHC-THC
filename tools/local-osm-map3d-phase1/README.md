# Local OSM-PHC — Map 3D Phase 1

แพ็กเกจเตรียมติดตั้งสำหรับ Local OSM-PHC โดยไม่แก้ Cloud production และไม่เปิด service-role key ใน browser

## Phase 1
- 2D / 3D camera mode
- บ้านจากพิกัด Cloud/Local connector
- clustering เพื่อรองรับหลายพันหลัง
- สีสถานะพิกัด: ยืนยันภาคสนาม / รอตรวจ / ผิดแนวเขต / พิกัดเดิม
- แสดงบ้านเลขที่เมื่อซูมใกล้
- polygon ชุมชน
- ค้นบ้านเลขที่ / HID / ชุมชน
- คลิกหมุดแล้วเปิดข้อมูลบ้านผ่าน callback ของระบบ Local

## Data provider contract
```js
const provider = {
  async getHouses({ community }) {
    // return [{id,house_no,house_id_11,moo,community,latitude,longitude,
    // coordinate_source,coordinate_status,review_required,inside_tambon,
    // inside_community,updated_at}]
  },
  async getCommunities() {
    // return [{id,name,moo,geometry_geojson}]
  }
}
```

Local backend ต้องเป็นผู้เชื่อม Cloud/Supabase; ห้ามฝัง service-role key ใน JavaScript ฝั่ง browser

## Integration
```html
<link rel="stylesheet" href="/osm-phc/assets/map3d-phase1.css">
<div class="prb-map3d-shell">
  <div class="prb-map3d-toolbar">...</div>
  <div class="prb-map3d-stage"><div id="prb-map3d" class="prb-map3d-map"></div></div>
</div>
<script type="module">
import { initPRBMap3D } from '/osm-phc/assets/map3d-phase1.mjs';
const app = await initPRBMap3D({
  container:'prb-map3d',
  provider,
  onOpenHouse:(id)=>openLocalHouse(id)
});
</script>
```

## Local deployment checklist
1. สำรองไฟล์ Local เดิม
2. คัดลอก JS/CSS เข้า assets
3. เพิ่มเมนู “แผนที่สุขภาพ 3 มิติ”
4. เชื่อม Local API provider
5. ทดสอบ 2D/3D, filter ชุมชน, search, popup, เปิดข้อมูลบ้าน
6. ทดสอบกับข้อมูล 4,000+ หลังและมือถือ
7. ยืนยันว่าไม่มีการเขียน JHCIS/Cloud จากหน้าแผนที่ใน Phase 1

หมายเหตุ: อาคาร 3D แบบ extrusion จะเชื่อมในขั้นติดตั้ง Local เมื่อยืนยันแหล่ง building footprints/cached OSM ของเครื่องจริง เพื่อไม่ให้พึ่ง public Overpass API แบบไม่ควบคุมใน production
