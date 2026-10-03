# Phase 1 Local API contract

Recommended read-only endpoints:

```
GET /osm-phc/api/v1/map3d/houses?community=<optional>
GET /osm-phc/api/v1/map3d/communities
```

## houses response
Return only fields needed by the map:
```json
[
  {
    "id": "uuid-or-local-id",
    "house_no": "12/3",
    "house_id_11": "optional",
    "moo": "7",
    "community": "ชุมชนหนองห้า",
    "latitude": 18.2696,
    "longitude": 99.5071,
    "coordinate_source": "gps",
    "coordinate_status": "field_confirmed",
    "review_required": false,
    "inside_tambon": true,
    "inside_community": true,
    "updated_at": "ISO-8601"
  }
]
```

## Security
- endpoint เป็น read-only
- ต้องผ่าน session/Admin auth ของ Local เดิม
- Cloud service key อยู่เฉพาะ backend
- ห้ามส่งข้อมูลบุคคล, CID, เบอร์โทร หรือข้อมูลสุขภาพใน Phase 1
- หน้าแผนที่ไม่มี endpoint สำหรับแก้ JHCIS หรือแก้ Cloud
