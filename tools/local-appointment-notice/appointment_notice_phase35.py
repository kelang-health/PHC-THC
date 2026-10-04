from __future__ import annotations

import json
import uuid
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from fastapi import Depends, HTTPException
from pydantic import BaseModel, Field

from .appointment_notice_phase2 import _line_identity
from .appointment_notice_phase33 import RolloutUpdateBody, update_rollout
from .database import Audit, CloudLineLink, PRIVATE, Volunteer
from .line_oa import LineAPIError, _line_api, _setting as _line_setting
from .line_oa_failover import _hub_json, backup_refs_for_volunteers, primary_status

TZ = ZoneInfo("Asia/Bangkok")
HISTORY_FILE = PRIVATE / "appointment_notice_osm_bridge_invites.json"
MAX_BATCH = 50
RESEND_HOURS = 12


class BridgeInviteBody(BaseModel):
    volunteer_ids: list[int] = Field(min_length=1, max_length=MAX_BATCH)
    dry_run: bool = True
    allow_resend: bool = False


def _read_history() -> dict[str, dict]:
    if not HISTORY_FILE.exists():
        return {}
    try:
        raw = json.loads(HISTORY_FILE.read_text(encoding="utf-8"))
        return raw if isinstance(raw, dict) else {}
    except Exception:
        return {}


def _write_history(value: dict[str, dict]) -> None:
    HISTORY_FILE.parent.mkdir(parents=True, exist_ok=True)
    temp = HISTORY_FILE.with_suffix(".json.tmp")
    temp.write_text(
        json.dumps(value, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    temp.replace(HISTORY_FILE)


def _active_primary_links(db) -> dict[int, CloudLineLink]:
    rows = db.query(CloudLineLink).filter(
        CloudLineLink.active.is_(True),
        CloudLineLink.profile_active.is_(True),
        CloudLineLink.volunteer_id.isnot(None),
    ).all()
    return {
        int(row.volunteer_id): row
        for row in rows
        if row.volunteer_id
    }


def _recent_invite(history: dict[str, dict], volunteer_id: int) -> bool:
    item = history.get(str(volunteer_id)) or {}
    value = str(item.get("sent_at") or "")
    if not value:
        return False
    try:
        stamp = datetime.fromisoformat(value)
        if stamp.tzinfo is None:
            stamp = stamp.replace(tzinfo=TZ)
    except ValueError:
        return False
    return stamp >= datetime.now(TZ) - timedelta(hours=RESEND_HOURS)


def bridge_status(db, *, community: str = "", search: str = "") -> dict:
    volunteers = db.query(Volunteer).all()
    by_id = {int(v.id): v for v in volunteers}
    ids = list(by_id)
    primary = _active_primary_links(db)
    backup = backup_refs_for_volunteers(db, ids)
    history = _read_history()

    community_filter = str(community or "").strip()
    search_filter = str(search or "").strip().casefold()

    counts = {
        "volunteers_total": len(volunteers),
        "primary_ready": 0,
        "dual_ready": 0,
        "osm_bridge_ready": 0,
        "fallback_registration": 0,
        "primary_link_unusable": 0,
        "recently_invited": 0,
    }
    rows = []

    for vid, volunteer in by_id.items():
        link = primary.get(vid)
        primary_ready = bool(link)
        backup_ready = vid in backup
        line_user_id = _line_identity(link) if link else ""
        sendable_primary = bool(primary_ready and line_user_id)
        pid = int(volunteer.jhcis_pid or 0)
        if primary_ready:
            counts["primary_ready"] += 1
        if primary_ready and backup_ready:
            status = "dual_ready"
            counts["dual_ready"] += 1
        elif primary_ready and sendable_primary and pid > 0:
            status = "osm_bridge_ready"
            counts["osm_bridge_ready"] += 1
        elif primary_ready:
            status = "primary_link_unusable"
            counts["primary_link_unusable"] += 1
        else:
            status = "fallback_registration"
            counts["fallback_registration"] += 1

        recent = _recent_invite(history, vid)
        if recent:
            counts["recently_invited"] += 1

        row = {
            "volunteer_id": vid,
            "name": str(volunteer.name or volunteer.full_name or ""),
            "community": str(volunteer.community or ""),
            "moo": str(volunteer.moo or ""),
            "primary_ready": primary_ready,
            "backup_ready": backup_ready,
            "status": status,
            "bridge_sendable": status == "osm_bridge_ready",
            "recently_invited": recent,
            "last_invited_at": str((history.get(str(vid)) or {}).get("sent_at") or ""),
        }
        if community_filter and row["community"] != community_filter:
            continue
        if search_filter and (
            search_filter not in row["name"].casefold()
            and search_filter not in row["community"].casefold()
        ):
            continue
        rows.append(row)

    total = max(1, counts["volunteers_total"])
    counts["primary_pct"] = round(
        counts["primary_ready"] / total * 100.0, 1
    )
    counts["bridge_path_pct"] = round(
        (counts["dual_ready"] + counts["osm_bridge_ready"]) / total * 100.0, 1
    )
    primary_quota = primary_status(db, force=True)
    try:
        hub_bridge = _hub_json("GET", "/onboarding/status")
    except HTTPException as exc:
        hub_bridge = {"status": "unavailable", "error": f"http_{exc.status_code}"}
    communities = sorted({
        str(v.community or "")
        for v in volunteers
        if str(v.community or "")
    })

    return {
        "summary": counts,
        "primary_quota": primary_quota,
        "hub_bridge": hub_bridge,
        "policy": {
            "preferred_route": "osm_primary_bridge",
            "fallback_route": "full_registration",
            "max_batch": MAX_BATCH,
            "resend_hours": RESEND_HOURS,
            "raw_backup_line_id_in_osm": False,
            "cid_birthdate_required_for_osm_bridge": False,
            "live_send_requires_admin_action": True,
        },
        "communities": communities,
        "rows": sorted(
            rows,
            key=lambda x: (
                0 if x["status"] == "osm_bridge_ready" else 1,
                x["community"],
                x["name"],
            ),
        ),
    }


def _candidate(db, volunteer_id: int):
    volunteer = db.get(Volunteer, int(volunteer_id))
    if volunteer is None:
        raise HTTPException(404, "ไม่พบ อสม.")
    link = db.query(CloudLineLink).filter(
        CloudLineLink.volunteer_id == int(volunteer_id),
        CloudLineLink.active.is_(True),
        CloudLineLink.profile_active.is_(True),
    ).first()
    if link is None:
        raise HTTPException(409, "ยังไม่ได้เชื่อม LINE OA ของ OSM")
    line_user_id = _line_identity(link)
    if not line_user_id:
        raise HTTPException(409, "ข้อมูล LINE OA เดิมไม่พร้อมส่ง")
    pid = int(volunteer.jhcis_pid or 0)
    if pid < 1:
        raise HTTPException(409, "ไม่พบ JHCIS PID ของ อสม.")
    if int(volunteer_id) in backup_refs_for_volunteers(db, [int(volunteer_id)]):
        raise HTTPException(409, "รายนี้พร้อม OA สำรองแล้ว")
    return volunteer, link, line_user_id, pid


def _invite_message(claim_url: str) -> dict:
    return {
        "type": "template",
        "altText": "เชื่อม LINE OA สำรองสำหรับการแจ้งเตือนนัดหมาย",
        "template": {
            "type": "buttons",
            "title": "พระบาท พลัส",
            "text": (
                "เชื่อม OA สำรองจากบัญชี อสม. เดิม "
                "ไม่ต้องกรอกเลขประชาชนหรือวันเกิดซ้ำ"
            ),
            "actions": [
                {
                    "type": "uri",
                    "label": "เชื่อม OA สำรอง",
                    "uri": str(claim_url),
                }
            ],
        },
    }


def invite_via_primary(db, body: BridgeInviteBody, *, actor: str) -> dict:
    ids = []
    seen = set()
    for raw in body.volunteer_ids:
        vid = int(raw)
        if vid > 0 and vid not in seen:
            ids.append(vid)
            seen.add(vid)
    if not ids:
        raise HTTPException(422, "ไม่มีรายการที่เลือก")
    if len(ids) > MAX_BATCH:
        raise HTTPException(422, f"ส่งได้ไม่เกิน {MAX_BATCH} คนต่อครั้ง")

    history = _read_history()
    primary = primary_status(db, force=True)
    if not primary.get("ready"):
        raise HTTPException(503, "OA หลักไม่พร้อม")
    if not body.dry_run and primary.get("remaining") is not None:
        remaining = int(primary.get("remaining") or 0)
        if remaining < len(ids) + 15:
            raise HTTPException(
                409,
                "โควตา OA หลักเหลือไม่พอสำหรับชุดนี้พร้อม reserve 15 ข้อความ",
            )

    prepared = []
    failed = []
    for vid in ids:
        try:
            volunteer, link, line_user_id, pid = _candidate(db, vid)
            if _recent_invite(history, vid) and not body.allow_resend:
                raise HTTPException(
                    409,
                    f"เพิ่งส่งคำเชิญภายใน {RESEND_HOURS} ชั่วโมง",
                )
            bridge = _hub_json(
                "POST",
                "/onboarding/issue",
                {
                    "pid": pid,
                    "dry_run": bool(body.dry_run),
                    "ttl_seconds": 1800,
                },
                timeout=15,
            )
            if body.dry_run:
                if str(bridge.get("status") or "") != "ready":
                    raise HTTPException(503, "Hub bridge ไม่พร้อม")
            else:
                claim_url = str(bridge.get("claim_url") or "")
                if not claim_url.startswith("https://line.me/"):
                    raise HTTPException(503, "ไม่ได้รับ claim URL")
            prepared.append({
                "volunteer_id": vid,
                "name": str(volunteer.name or volunteer.full_name or ""),
                "community": str(volunteer.community or ""),
                "line_user_id": line_user_id,
                "claim_url": str(bridge.get("claim_url") or ""),
                "expires_at": str(bridge.get("expires_at") or ""),
            })
        except HTTPException as exc:
            failed.append({
                "volunteer_id": vid,
                "status": "blocked",
                "reason": str(exc.detail),
            })

    if body.dry_run:
        return {
            "status": "validated" if prepared else "blocked",
            "dry_run": True,
            "selected": len(ids),
            "ready": len(prepared),
            "blocked": len(failed),
            "sent": 0,
            "primary_basic_id": str(primary.get("basic_id") or ""),
            "primary_remaining": primary.get("remaining"),
            "results": [
                {
                    "volunteer_id": x["volunteer_id"],
                    "name": x["name"],
                    "community": x["community"],
                    "status": "ready",
                }
                for x in prepared
            ] + failed,
        }

    setting = _line_setting(db)
    sent = 0
    send_failed = 0
    results = []
    for item in prepared:
        try:
            result = _line_api(
                setting,
                "POST",
                "/v2/bot/message/push",
                body={
                    "to": item["line_user_id"],
                    "messages": [_invite_message(item["claim_url"])],
                },
                retry_key=f"osm-bridge-{uuid.uuid4()}",
            )
            sent += 1
            stamp = datetime.now(TZ).isoformat(timespec="seconds")
            history[str(item["volunteer_id"])] = {
                "sent_at": stamp,
                "expires_at": item["expires_at"],
                "community": item["community"],
            }
            try:
                update_rollout(
                    db,
                    RolloutUpdateBody(
                        volunteer_id=int(item["volunteer_id"]),
                        status="invited",
                    ),
                    actor,
                )
            except Exception:
                pass
            results.append({
                "volunteer_id": item["volunteer_id"],
                "name": item["name"],
                "community": item["community"],
                "status": "sent",
                "duplicate": bool((result or {}).get("duplicate")),
            })
        except LineAPIError as exc:
            send_failed += 1
            results.append({
                "volunteer_id": item["volunteer_id"],
                "name": item["name"],
                "community": item["community"],
                "status": "failed",
                "reason": f"line_http_{int(exc.status or 0)}",
            })
        except Exception:
            send_failed += 1
            results.append({
                "volunteer_id": item["volunteer_id"],
                "name": item["name"],
                "community": item["community"],
                "status": "failed",
                "reason": "line_send_failed",
            })

    _write_history(history)
    db.add(Audit(
        actor=actor,
        action="osm_primary_bridge_invite_batch",
        entity="appointment_notice",
        detail={
            "selected": len(ids),
            "prepared": len(prepared),
            "sent": sent,
            "send_failed": send_failed,
            "blocked": len(failed),
            "primary_basic_id": str(primary.get("basic_id") or ""),
            "raw_line_id_logged": False,
            "claim_token_logged": False,
            "contains_cid": False,
        },
    ))
    db.commit()
    return {
        "status": "sent" if sent and not send_failed else ("partial" if sent else "failed"),
        "dry_run": False,
        "selected": len(ids),
        "ready": len(prepared),
        "blocked": len(failed),
        "sent": sent,
        "send_failed": send_failed,
        "primary_basic_id": str(primary.get("basic_id") or ""),
        "results": results + failed,
    }


def install_appointment_notice_phase35(app, auth, db_session, admin):
    @app.get("/api/v1/appointment-notices/failover/osm-bridge")
    def phase35_status(
        community: str = "",
        search: str = "",
        u=Depends(auth),
        db=Depends(db_session),
    ):
        admin(u)
        return bridge_status(
            db,
            community=community[:191],
            search=search[:100],
        )

    @app.post("/api/v1/appointment-notices/failover/osm-bridge/invite")
    def phase35_invite(
        body: BridgeInviteBody,
        u=Depends(auth),
        db=Depends(db_session),
    ):
        admin(u)
        return invite_via_primary(db, body, actor=u.username)