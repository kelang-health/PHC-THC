from __future__ import annotations

import math
from datetime import datetime
from zoneinfo import ZoneInfo

from fastapi import Depends

from .appointment_notice_phase35 import (
    RESEND_HOURS,
    _read_history,
    _recent_invite,
    bridge_status,
)
from .appointment_notice_preview import _load_config
from .database import User

TZ = ZoneInfo("Asia/Bangkok")


def _dt(value: str):
    try:
        stamp = datetime.fromisoformat(str(value or ""))
        if stamp.tzinfo is None:
            stamp = stamp.replace(tzinfo=TZ)
        return stamp
    except Exception:
        return None


def _conversion_state(row: dict, history: dict[str, dict]) -> str:
    if row.get("backup_ready"):
        return "dual_ready"

    volunteer_id = int(row.get("volunteer_id") or 0)
    item = history.get(str(volunteer_id)) or {}
    if item.get("sent_at"):
        expires = _dt(item.get("expires_at"))
        now = datetime.now(TZ)
        if expires and expires > now:
            return "invited_active"
        if _recent_invite(history, volunteer_id):
            return "expired_wait"
        return "resend_ready"

    if row.get("bridge_sendable"):
        return "ready_to_invite"
    if row.get("status") == "fallback_registration":
        return "fallback_registration"
    return "primary_link_unusable"


def _role_summary(rows: list[dict], *, target_pct: int) -> dict:
    total = len(rows)
    dual = sum(1 for row in rows if row.get("backup_ready"))
    primary = sum(1 for row in rows if row.get("primary_ready"))
    ready = sum(1 for row in rows if row.get("conversion_state") == "ready_to_invite")
    invited = sum(1 for row in rows if row.get("conversion_state") == "invited_active")
    expired_wait = sum(1 for row in rows if row.get("conversion_state") == "expired_wait")
    resend = sum(1 for row in rows if row.get("conversion_state") == "resend_ready")
    fallback = sum(1 for row in rows if row.get("conversion_state") == "fallback_registration")
    unusable = sum(1 for row in rows if row.get("conversion_state") == "primary_link_unusable")
    target_count = math.ceil(total * target_pct / 100) if total else 0
    return {
        "total": total,
        "primary_ready": primary,
        "dual_ready": dual,
        "dual_pct": round((dual / total) * 100.0, 1) if total else 0.0,
        "target_pct": target_pct,
        "target_count": target_count,
        "gap_to_target": max(0, target_count - dual),
        "ready_to_invite": ready,
        "invited_active": invited,
        "expired_wait": expired_wait,
        "resend_ready": resend,
        "fallback_registration": fallback,
        "primary_link_unusable": unusable,
    }


def staff_first_status(db) -> dict:
    base = bridge_status(db)
    history = _read_history()

    staff_ids = {
        int(user.volunteer_id)
        for user in db.query(User).filter(
            User.role == "staff",
            User.active.is_(True),
            User.volunteer_id.isnot(None),
        ).all()
        if user.volunteer_id
    }

    config = _load_config()
    chair_ids = {
        int(value)
        for value in (config.get("chairs") or {}).values()
        if str(value or "").isdigit() and int(value) > 0
    }

    rows = []
    for source in base.get("rows") or []:
        row = dict(source)
        vid = int(row.get("volunteer_id") or 0)
        is_staff = vid in staff_ids
        is_chair = vid in chair_ids
        if is_staff:
            role_group = "staff"
            priority_rank = 0
        elif is_chair:
            role_group = "chair"
            priority_rank = 1
        else:
            role_group = "vhv"
            priority_rank = 2

        conversion_state = _conversion_state(row, history)
        row.update({
            "is_staff": is_staff,
            "is_chair": is_chair,
            "role_group": role_group,
            "conversion_state": conversion_state,
            "priority_rank": priority_rank,
        })
        rows.append(row)

    staff_rows = [row for row in rows if row.get("is_staff")]
    chair_rows = [row for row in rows if row.get("is_chair")]
    general_rows = [
        row for row in rows
        if not row.get("is_staff") and not row.get("is_chair")
    ]

    role_summary = {
        "staff": _role_summary(staff_rows, target_pct=100),
        "chair": _role_summary(chair_rows, target_pct=100),
        "vhv": _role_summary(general_rows, target_pct=90),
        "all": _role_summary(rows, target_pct=90),
    }

    staff_priority_ids = [
        int(row["volunteer_id"])
        for row in sorted(
            staff_rows,
            key=lambda row: (
                0 if row.get("conversion_state") in {"ready_to_invite", "resend_ready"} else 1,
                str(row.get("community") or ""),
                str(row.get("name") or ""),
            ),
        )
        if row.get("conversion_state") in {"ready_to_invite", "resend_ready"}
    ]

    rows.sort(
        key=lambda row: (
            int(row.get("priority_rank") or 0),
            0 if row.get("conversion_state") in {"ready_to_invite", "resend_ready"} else 1,
            str(row.get("community") or ""),
            str(row.get("name") or ""),
        )
    )

    conversion_totals = {}
    for key in (
        "ready_to_invite",
        "invited_active",
        "expired_wait",
        "resend_ready",
        "dual_ready",
        "fallback_registration",
        "primary_link_unusable",
    ):
        conversion_totals[key] = sum(
            1 for row in rows if row.get("conversion_state") == key
        )

    return {
        **base,
        "role_summary": role_summary,
        "conversion_totals": conversion_totals,
        "staff_first": {
            "enabled": True,
            "default_role_filter": "staff",
            "staff_priority_ids": staff_priority_ids,
            "staff_priority_count": len(staff_priority_ids),
            "staff_target_pct": 100,
            "chair_target_pct": 100,
            "vhv_target_pct": 90,
            "chair_source": "explicit_config_only",
            "chair_count": len(chair_ids),
            "auto_send": False,
            "max_batch": int((base.get("policy") or {}).get("max_batch") or 50),
            "resend_hours": RESEND_HOURS,
        },
        "rows": rows,
    }


def install_appointment_notice_phase36(app, auth, db_session, admin):
    @app.get("/api/v1/appointment-notices/failover/staff-first")
    def phase36_staff_first(
        u=Depends(auth),
        db=Depends(db_session),
    ):
        admin(u)
        return staff_first_status(db)