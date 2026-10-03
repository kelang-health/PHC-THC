from __future__ import annotations

import time

from .tracking_center_v2145 import _latest_jhcis_ncd_results

RANK = {"urgent": 1, "alert": 2, "risk": 3, "due": 4, "no_data": 5, "normal": 6}
_ROW_CACHE = {'at': 0.0, 'rows': []}
ROW_CACHE_SECONDS = 300

LABEL = {
    "urgent": "เร่งด่วน",
    "alert": "ต้องตรวจยืนยัน",
    "risk": "ติดตามความเสี่ยง/โรคเดิม",
    "due": "คัดกรองคงค้าง",
    "no_data": "ยังไม่มีผล",
    "normal": "ไม่พบสัญญาณติดตาม",
}


def build_ncd_house_layer(db, community: str = "") -> dict:
    now = time.time()
    if _ROW_CACHE['rows'] and now - float(_ROW_CACHE['at'] or 0) < ROW_CACHE_SECONDS:
        rows = _ROW_CACHE['rows']
    else:
        rows = _latest_jhcis_ncd_results(db)
        _ROW_CACHE['rows'] = rows
        _ROW_CACHE['at'] = now
    community = str(community or "").strip()
    if community:
        rows = [r for r in rows if str(r.get("community") or "") == community]

    groups = {}
    for row in rows:
        hcode = str(row.get("hcode") or "").strip()
        if not hcode:
            continue
        item = groups.setdefault(hcode, {
            "hcode": hcode,
            "community": str(row.get("community") or ""),
            "house_no": str(row.get("house_no") or ""),
            "target": 0,
            "followup": 0,
            "urgent": 0,
            "alert": 0,
            "risk": 0,
            "due": 0,
            "normal": 0,
            "no_data": 0,
            "known_ncd": 0,
            "abnormal": 0,
            "level": "normal",
            "_rank": 99,
        })
        item["target"] += 1
        if row.get("needs_followup"):
            item["followup"] += 1
        group = str(row.get("followup_group") or "no_data")
        if group in ("urgent", "alert", "risk", "due", "normal", "no_data"):
            item[group] += 1
        if row.get("known_ncd"):
            item["known_ncd"] += 1
        if row.get("abnormal"):
            item["abnormal"] += 1
        rank = RANK.get(group, 99)
        if rank < item["_rank"]:
            item["_rank"] = rank
            item["level"] = group

    items = []
    for item in groups.values():
        item.pop("_rank", None)
        item["label"] = LABEL.get(item["level"], item["level"])
        items.append(item)
    items.sort(key=lambda x: (RANK.get(x["level"], 99), -x["followup"], x["hcode"]))

    summary = {
        "people": len(rows),
        "houses": len(items),
        "followup_people": sum(x["followup"] for x in items),
        "risk_houses": sum(1 for x in items if x["level"] in ("urgent", "alert", "risk")),
        "due_houses": sum(1 for x in items if x["level"] == "due"),
        "urgent_houses": sum(1 for x in items if x["level"] == "urgent"),
        "alert_houses": sum(1 for x in items if x["level"] == "alert"),
    }
    return {
        "summary": summary,
        "items": items,
        "policy": {
            "granularity": "household aggregate only",
            "person_names": False,
            "clinical_values": False,
            "source": "Local Tracking Center aggregation",
            "write_back": False,
        },
    }