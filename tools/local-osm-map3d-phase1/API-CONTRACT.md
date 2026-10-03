# Local Map 3D API Contract v2.1.77

ทุก endpoint ด้านล่างอยู่ใต้ `/api/v1` และต้องผ่าน Local authentication; ฟังก์ชัน Map 3D จำกัด Admin

## GET /map3d/houses
Query: `community` optional

คืนข้อมูลบ้านสำหรับแผนที่จาก Local household DB: id, hcode, house_no, house_id_11, moo, community, latitude, longitude, geo/coordinate status และ updated_at. Read-only.

## GET /boundary/geojson
คืน community boundary snapshot ในเครื่อง ใช้กำหนดขอบเขต/fit map และเป็น bbox อ้างอิงสำหรับโหลดอาคาร ไม่ใช้ min/max ของหมุดบ้านเพราะ legacy coordinates อาจเป็น outlier.

## GET /map3d/health/ncd
Query: `community` optional

คืน aggregate ต่อ hcode เท่านั้น: target, followup, urgent, alert, risk, due, normal, no_data, known_ncd, abnormal และ highest-priority level.
Policy: no person names, no PID/CID, no individual clinical values, no write-back.
แหล่งข้อมูลคือ existing Local Tracking Center aggregation.

## GET /map3d/buildings
Query required: `south, west, north, east`

Admin read-only proxy สำหรับ OpenStreetMap/Overpass building footprints.
- bbox จำกัดไม่เกิน 0.09 degree ต่อแกน
- Overpass fallback 2 endpoints
- memory cache 15 นาที
- disk cache 24 ชั่วโมง
- stale disk fallback สูงสุด 30 วันเมื่อ upstream ล่ม
- ไม่อ่าน/เขียน Cloud หรือ JHCIS

## GET /map3d/environment/rain
คืน metadata ของ RainViewer radar ล่าสุดและ raster tile template.
ใช้เพื่อบริบทสภาพอากาศเท่านั้น ไม่ใช่ flood forecast/hazard score.

## Client-only raster sources
- OSM base: tile.openstreetmap.org
- Satellite base: services.arcgisonline.com World Imagery
- DEM: AWS elevation-tiles-prod Terrarium
- Rain radar: tilecache.rainviewer.com

CSP ต้องอนุญาตเฉพาะ host ที่จำเป็นข้างต้น พร้อม worker-src/child-src self + blob สำหรับ MapLibre.

## Failure behavior
External tile/provider failure ต้องไม่ทำให้ Local household/boundary data หายหรือเกิด write operation. Map 3D มี background fallback และ optional overlays สามารถปิดได้.
