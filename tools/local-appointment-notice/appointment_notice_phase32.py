from __future__ import annotations

import argparse
import json
import math
from datetime import datetime, timedelta
from pathlib import Path
from urllib.parse import quote
from zoneinfo import ZoneInfo

from fastapi import Depends, HTTPException
from pydantic import BaseModel, Field

from .appointment_notice_preview import build_preview
from .appointment_notice_phase2 import _community_recipients, _sent_case_ids, _vhv_groups
from .boundary_quality import normalize_community
from .database import (
    AppointmentNoticeDelivery,
    Audit,
    CloudLineLink,
    PRIVATE,
    Session,
    User,
    Volunteer,
    now,
)
from .line_oa_failover import backup_refs_for_volunteers, public_status, route_groups

TZ = ZoneInfo("Asia/Bangkok")
AUTO_CONFIG_FILE = PRIVATE / "appointment_notice_auto.json"
PREFLIGHT_FILE = PRIVATE / "appointment_notice_preflight.json"
BACKUP_BASIC_ID = "@601cnwrw"
ADD_FRIEND_URL = "https://line.me/R/ti/p/" + quote(BACKUP_BASIC_ID, safe="")
REGISTER_CHAT_URL = (
    "https://line.me/R/oaMessage/"
    + quote(BACKUP_BASIC_ID, safe="")
    + "/?"
    + quote("ลงทะเบียน", safe="")
)
QR_ASSET = "/assets/line-oa-backup-addfriend.png?v=2.1.85"


class ForecastDateBody(BaseModel):
    target_date: str = Field(min_length=10, max_length=10)


def _auto_config() -> dict:
    defaults = {
        "enabled": True,
        "send_vhv": True,
        "send_community": True,
        "community_target": "both",
        "primary_reserve": 15,
    }
    if AUTO_CONFIG_FILE.exists():
        try:
            raw = json.loads(AUTO_CONFIG_FILE.read_text(encoding="utf-8"))
            if isinstance(raw, dict):
                defaults.update(raw)
        except Exception:
            pass
    return defaults


def _primary_linked_ids(db) -> set[int]:
    rows = db.query(CloudLineLink).filter(
        CloudLineLink.active.is_(True),
        CloudLineLink.profile_active.is_(True),
        CloudLineLink.volunteer_id.isnot(None),
    ).all()
    return {int(row.volunteer_id) for row in rows if row.volunteer_id}


def coverage_detail(db, *, community: str = "", search: str = "") -> dict:
    volunteers = db.query(Volunteer).all()
    ids = [int(v.id) for v in volunteers]
    primary = _primary_linked_ids(db)
    backup = backup_refs_for_volunteers(db, ids)
    staff_users = db.query(User).filter(
        User.role == "staff",
        User.active.is_(True),
        User.volunteer_id.isnot(None),
    ).all()
    staff_ids = {int(u.volunteer_id) for u in staff_users if u.volunteer_id}

    community_norm = normalize_community(community) if community else ""
    search_norm = str(search or "").strip().casefold()

    all_rows = []
    for volunteer in volunteers:
        vid = int(volunteer.id)
        comm = str(volunteer.community or "").strip()
        if community_norm and normalize_community(comm) != community_norm:
            continue
        name = str(volunteer.name or volunteer.full_name or "").strip()
        if search_norm and search_norm not in name.casefold() and search_norm not in comm.casefold():
            continue
        p = vid in primary
        b = vid in backup
        if p and b:
            state = "dual_ready"
        elif p:
            state = "primary_only"
        elif b:
            state = "backup_only"
        else:
            state = "not_linked"
        all_rows.append({
            "volunteer_id": vid,
            "name": name,
            "community": comm,
            "moo": str(volunteer.moo or ""),
            "is_staff": vid in staff_ids,
            "primary_ready": p,
            "backup_ready": b,
            "dual_ready": p and b,
            "status": state,
        })

    community_groups: dict[str, dict] = {}
    for volunteer in volunteers:
        vid = int(volunteer.id)
        comm = str(volunteer.community or "").strip() or "ไม่ระบุชุมชน"
        group = community_groups.setdefault(comm, {
            "community": comm,
            "total": 0,
            "primary_ready": 0,
            "backup_ready": 0,
            "dual_ready": 0,
            "staff_total": 0,
            "staff_dual_ready": 0,
        })
        group["total"] += 1
        if vid in primary:
            group["primary_ready"] += 1
        if vid in backup:
            group["backup_ready"] += 1
        if vid in primary and vid in backup:
            group["dual_ready"] += 1
        if vid in staff_ids:
            group["staff_total"] += 1
            if vid in primary and vid in backup:
                group["staff_dual_ready"] += 1

    for group in community_groups.values():
        total = int(group["total"] or 0)
        group["dual_pct"] = round((group["dual_ready"] / total) * 100.0, 1) if total else 0.0
        group["gap"] = max(0, total - int(group["dual_ready"]))

    total = len(volunteers)
    primary_count = len(primary & set(ids))
    backup_count = len(set(backup) & set(ids))
    dual = len(primary & set(backup))
    target90 = math.ceil(total * 0.90) if total else 0
    target95 = math.ceil(total * 0.95) if total else 0
    staff_total = len(staff_ids)
    staff_dual = len(staff_ids & primary & set(backup))

    return {
        "summary": {
            "volunteers_total": total,
            "primary_ready": primary_count,
            "backup_ready": backup_count,
            "dual_ready": dual,
            "dual_pct": round((dual / total) * 100.0, 1) if total else 0.0,
            "gap_to_90": max(0, target90 - dual),
            "gap_to_95": max(0, target95 - dual),
            "target_90": target90,
            "target_95": target95,
            "staff_total": staff_total,
            "staff_dual_ready": staff_dual,
        },
        "communities": sorted(
            community_groups.values(),
            key=lambda x: (normalize_community(x["community"]), x["community"]),
        ),
        "rows": sorted(
            all_rows,
            key=lambda x: (normalize_community(x["community"]), x["name"], x["volunteer_id"]),
        ),
        "onboarding": {
            "backup_basic_id": BACKUP_BASIC_ID,
            "add_friend_url": ADD_FRIEND_URL,
            "register_chat_url": REGISTER_CHAT_URL,
            "qr_asset": QR_ASSET,
            "steps": [
                "เพิ่มเพื่อน LINE OA สำรอง",
                "เปิดแชตแล้วส่งคำว่า ลงทะเบียน",
                "เปิดลิงก์ใช้ครั้งเดียวที่ LINE ส่งกลับ",
                "ยืนยันเลขประชาชนและวันเกิด แล้วตรวจชื่อก่อนยืนยัน",
                "กลับมาหน้านี้และกดรีเฟรช จนสถานะ Backup เป็นพร้อม",
            ],
        },
    }


def _unsent_vhv_groups(db, preview: dict) -> list[dict]:
    groups, _ = _vhv_groups(db, list(preview.get("rows") or []))
    output = []
    for group in groups:
        case_ids = [str(row.get("case_id") or "") for row in group.get("rows") or []]
        sent = _sent_case_ids(db, "vhv", int(group["volunteer_id"]), case_ids)
        if any(case_id and case_id not in sent for case_id in case_ids):
            output.append({
                "volunteer_id": int(group["volunteer_id"]),
                "name": str(group.get("name") or ""),
                "target_kind": "vhv",
            })
    return output


def _unsent_community_groups(db, preview: dict, target: str) -> list[dict]:
    output = []
    rows = list(preview.get("rows") or [])
    communities = sorted({
        str(row.get("community") or "").strip()
        for row in rows
        if str(row.get("community") or "").strip()
    })
    for community in communities:
        recipients, _ = _community_recipients(db, preview, community, target)
        community_rows = [
            row for row in rows
            if normalize_community(row.get("community")) == normalize_community(community)
        ]
        case_ids = [str(row.get("case_id") or "") for row in community_rows]
        for recipient in recipients:
            sent = _sent_case_ids(
                db,
                "community",
                int(recipient["volunteer_id"]),
                case_ids,
            )
            if any(case_id and case_id not in sent for case_id in case_ids):
                output.append({
                    "volunteer_id": int(recipient["volunteer_id"]),
                    "name": str(recipient.get("name") or ""),
                    "target_kind": str(recipient.get("target_kind") or "community"),
                    "community": community,
                })
    return output


def forecast(db, *, target_date: str | None = None) -> dict:
    if target_date:
        try:
            target = datetime.strptime(target_date, "%Y-%m-%d").date()
        except ValueError:
            raise HTTPException(422, "target_date ต้องเป็น YYYY-MM-DD") from None
    else:
        target = (datetime.now(TZ) + timedelta(days=1)).date()

    preview = build_preview(db, from_date=target.isoformat(), to_date=target.isoformat())
    cfg = _auto_config()
    groups: list[dict] = []
    vhv_groups = _unsent_vhv_groups(db, preview) if cfg.get("send_vhv") else []
    community_groups = (
        _unsent_community_groups(
            db,
            preview,
            str(cfg.get("community_target") or "both"),
        )
        if cfg.get("send_community")
        else []
    )
    groups.extend(vhv_groups)
    groups.extend(community_groups)

    routing = route_groups(db, groups) if groups else {
        "state": "primary",
        "primary": public_status(db).get("primary") or {},
        "backup": public_status(db).get("backup") or {},
        "primary_groups": 0,
        "backup_groups": 0,
        "blocked_groups": 0,
        "backup_ready_groups": 0,
        "decisions": [],
    }

    status = public_status(db)
    coverage = status.get("coverage") or {}
    total = int(coverage.get("volunteers_total") or 0)
    dual_ready = int(coverage.get("dual_ready_volunteers") or coverage.get("backup_ready_volunteers") or 0)
    coverage_pct = round((dual_ready / total) * 100.0, 1) if total else 0.0

    blocked = int(routing.get("blocked_groups") or 0)
    route_state = str(routing.get("state") or "primary")
    if blocked > 0:
        risk = "critical"
        message = f"มี {blocked} กลุ่มผู้รับที่โควตา/Backup mapping ไม่พร้อม"
    elif route_state in {"failover", "warning"}:
        risk = "warning"
        message = "โควตา OA หลักเข้าเขตเตือน/เริ่มใช้ OA สำรอง"
    else:
        risk = "ok"
        message = "โควตาสำหรับนัดพรุ่งนี้เพียงพอตาม routing ปัจจุบัน"

    target90 = math.ceil(total * 0.90) if total else 0
    onboarding_gap = max(0, target90 - dual_ready)

    return {
        "generated_at": datetime.now(TZ).isoformat(timespec="seconds"),
        "target_date": target.isoformat(),
        "appointments": int((preview.get("summary") or {}).get("appointments") or 0),
        "people": int((preview.get("summary") or {}).get("people") or 0),
        "houses": int((preview.get("summary") or {}).get("houses") or 0),
        "projected_groups": len(groups),
        "vhv_groups": len(vhv_groups),
        "community_groups": len(community_groups),
        "primary_groups": int(routing.get("primary_groups") or 0),
        "backup_groups": int(routing.get("backup_groups") or 0),
        "blocked_groups": blocked,
        "backup_ready_groups": int(routing.get("backup_ready_groups") or 0),
        "routing_state": route_state,
        "risk": risk,
        "message": message,
        "primary": routing.get("primary") or {},
        "backup": routing.get("backup") or {},
        "coverage": {
            "dual_ready": dual_ready,
            "total": total,
            "dual_pct": coverage_pct,
            "target_90": target90,
            "gap_to_90": onboarding_gap,
        },
        "auto_enabled": bool(cfg.get("enabled", True)),
        "send_vhv": bool(cfg.get("send_vhv", True)),
        "send_community": bool(cfg.get("send_community", True)),
        "community_target": str(cfg.get("community_target") or "both"),
    }


def _safe_preflight_payload(result: dict) -> dict:
    return {
        key: result.get(key)
        for key in (
            "generated_at", "target_date", "appointments", "people", "houses",
            "projected_groups", "vhv_groups", "community_groups",
            "primary_groups", "backup_groups", "blocked_groups",
            "backup_ready_groups", "routing_state", "risk", "message",
            "coverage", "auto_enabled", "send_vhv", "send_community",
            "community_target",
        )
    } | {
        "primary": {
            k: (result.get("primary") or {}).get(k)
            for k in ("basic_id", "limit", "used", "remaining", "usage_pct", "ready")
        },
        "backup": {
            k: (result.get("backup") or {}).get(k)
            for k in ("basic_id", "limit", "used", "remaining", "usage_pct", "ready")
        },
    }


def save_preflight(db, *, actor: str = "system:preflight") -> dict:
    result = forecast(db)
    payload = _safe_preflight_payload(result)
    PREFLIGHT_FILE.parent.mkdir(parents=True, exist_ok=True)
    temp = PREFLIGHT_FILE.with_suffix(".json.tmp")
    temp.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    temp.replace(PREFLIGHT_FILE)
    db.add(Audit(
        actor=actor,
        action="appointment_notice_preflight",
        entity="appointment_notice",
        detail={
            "target_date": payload["target_date"],
            "risk": payload["risk"],
            "projected_groups": payload["projected_groups"],
            "primary_groups": payload["primary_groups"],
            "backup_groups": payload["backup_groups"],
            "blocked_groups": payload["blocked_groups"],
            "coverage_pct": (payload.get("coverage") or {}).get("dual_pct"),
            "contains_phi": False,
        },
    ))
    db.commit()
    return payload


def preflight_status() -> dict:
    if not PREFLIGHT_FILE.exists():
        return {"available": False}
    try:
        data = json.loads(PREFLIGHT_FILE.read_text(encoding="utf-8"))
    except Exception:
        return {"available": False}
    return {"available": True, **data} if isinstance(data, dict) else {"available": False}


def install_appointment_notice_phase32(app, auth, db_session, admin):
    @app.get("/api/v1/appointment-notices/failover/coverage")
    def phase32_coverage(
        community: str = "",
        search: str = "",
        u=Depends(auth),
        db=Depends(db_session),
    ):
        admin(u)
        return coverage_detail(db, community=community[:191], search=search[:100])

    @app.get("/api/v1/appointment-notices/failover/forecast")
    def phase32_forecast(
        target_date: str = "",
        u=Depends(auth),
        db=Depends(db_session),
    ):
        admin(u)
        return forecast(db, target_date=target_date or None)

    @app.get("/api/v1/appointment-notices/failover/preflight")
    def phase32_preflight_status(u=Depends(auth)):
        admin(u)
        return preflight_status()

    @app.post("/api/v1/appointment-notices/failover/preflight")
    def phase32_preflight_run(u=Depends(auth), db=Depends(db_session)):
        admin(u)
        return save_preflight(db, actor=u.username)


def _cli() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--preflight", action="store_true")
    args = parser.parse_args()
    if not args.preflight:
        parser.error("--preflight is required")
    db = Session()
    try:
        result = save_preflight(db)
        print(json.dumps(result, ensure_ascii=False))
        return 0
    finally:
        db.close()


if __name__ == "__main__":
    raise SystemExit(_cli())