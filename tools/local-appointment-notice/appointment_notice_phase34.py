from __future__ import annotations

import json
import math
from datetime import date, datetime
from zoneinfo import ZoneInfo

from fastapi import Depends, HTTPException
from pydantic import BaseModel, Field

from .appointment_notice_phase33 import rollout_status
from .database import Audit, PRIVATE

TZ = ZoneInfo("Asia/Bangkok")
CONFIG_FILE = PRIVATE / "appointment_notice_readiness_gate.json"

DEFAULTS = {
    "target_pct": 90,
    "operational_goal_pct": 95,
    "target_days": 14,
    "stalled_days": 3,
}


class ReadinessSettingsBody(BaseModel):
    target_pct: int = Field(default=90, ge=70, le=99)
    operational_goal_pct: int = Field(default=95, ge=80, le=100)
    target_days: int = Field(default=14, ge=3, le=60)
    stalled_days: int = Field(default=3, ge=2, le=14)


def _load_settings() -> dict:
    cfg = dict(DEFAULTS)
    if CONFIG_FILE.exists():
        try:
            raw = json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
            if isinstance(raw, dict):
                for key in DEFAULTS:
                    if key in raw:
                        cfg[key] = raw[key]
        except Exception:
            pass
    return cfg


def _save_settings(cfg: dict) -> None:
    CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
    temp = CONFIG_FILE.with_suffix(".json.tmp")
    temp.write_text(
        json.dumps(cfg, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    temp.replace(CONFIG_FILE)


def _parse_date(value: str) -> date | None:
    try:
        return datetime.strptime(str(value or ""), "%Y-%m-%d").date()
    except Exception:
        return None


def _history_stats(history: list[dict], current_dual: int, gap: int) -> dict:
    distinct = {}
    for row in history:
        d = str(row.get("date") or "")
        if d:
            distinct[d] = row
    rows = [distinct[key] for key in sorted(distinct)]
    today = datetime.now(TZ).date()

    previous = None
    for row in reversed(rows):
        d = _parse_date(row.get("date"))
        if d and d < today:
            previous = row
            break

    today_gain = None
    if previous is not None:
        today_gain = max(0, int(current_dual) - int(previous.get("dual_ready") or 0))

    avg_daily_gain = None
    eta_days = None
    if len(rows) >= 2:
        first = rows[max(0, len(rows) - 7)]
        last = rows[-1]
        d1 = _parse_date(first.get("date"))
        d2 = _parse_date(last.get("date"))
        if d1 and d2 and d2 > d1:
            delta_days = max(1, (d2 - d1).days)
            gain = max(
                0,
                int(last.get("dual_ready") or 0)
                - int(first.get("dual_ready") or 0),
            )
            avg_daily_gain = round(gain / delta_days, 2)
            if avg_daily_gain > 0 and gap > 0:
                eta_days = math.ceil(gap / avg_daily_gain)
            elif gap == 0:
                eta_days = 0

    return {
        "has_baseline": previous is not None,
        "today_gain": today_gain,
        "avg_daily_gain": avg_daily_gain,
        "eta_days": eta_days,
        "history_days": len(rows),
    }


def _community_old_dual(history: list[dict], community: str, stalled_days: int):
    today = datetime.now(TZ).date()
    candidates = []
    for snap in history:
        d = _parse_date(snap.get("date"))
        if not d or d >= today:
            continue
        age = (today - d).days
        if age < stalled_days:
            continue
        for item in snap.get("communities") or []:
            if str(item.get("community") or "") == community:
                candidates.append((d, int(item.get("dual_ready") or 0)))
                break
    if not candidates:
        return None
    candidates.sort(key=lambda x: x[0], reverse=True)
    return candidates[0][1]


def _allocate_daily_target(rows: list[dict], total_target: int) -> dict[str, int]:
    if total_target <= 0:
        return {str(row["community"]): 0 for row in rows}

    weighted = [
        row for row in rows
        if int(row.get("gap_to_target") or 0) > 0
    ]
    total_gap = sum(int(row["gap_to_target"]) for row in weighted)
    if total_gap <= 0:
        return {str(row["community"]): 0 for row in rows}

    allocation = {}
    fractions = []
    assigned = 0
    for row in weighted:
        community = str(row["community"])
        gap = int(row["gap_to_target"])
        raw = total_target * gap / total_gap
        base = min(gap, int(math.floor(raw)))
        allocation[community] = base
        assigned += base
        fractions.append((raw - base, gap, community))

    remainder = max(0, total_target - assigned)
    fractions.sort(reverse=True)
    while remainder > 0:
        moved = False
        for _, gap, community in fractions:
            if remainder <= 0:
                break
            if allocation.get(community, 0) < gap:
                allocation[community] = allocation.get(community, 0) + 1
                remainder -= 1
                moved = True
        if not moved:
            break

    for row in rows:
        allocation.setdefault(str(row["community"]), 0)
    return allocation


def acceleration_status(db) -> dict:
    cfg = _load_settings()
    rollout = rollout_status(db)
    summary = rollout.get("summary") or {}
    history = rollout.get("history") or []
    communities = rollout.get("communities") or []

    total = int(summary.get("volunteers_total") or 0)
    dual = int(summary.get("dual_ready") or 0)
    target_count = math.ceil(total * int(cfg["target_pct"]) / 100) if total else 0
    goal_count = math.ceil(total * int(cfg["operational_goal_pct"]) / 100) if total else 0
    gap_to_target = max(0, target_count - dual)
    gap_to_goal = max(0, goal_count - dual)
    daily_target = math.ceil(gap_to_target / int(cfg["target_days"])) if gap_to_target else 0

    history_stats = _history_stats(history, dual, gap_to_target)

    priority_rows = []
    for item in communities:
        community = str(item.get("community") or "")
        community_total = int(item.get("total") or 0)
        community_dual = int(item.get("dual_ready") or 0)
        community_pct = float(item.get("dual_pct") or 0)
        community_target = (
            math.ceil(community_total * int(cfg["target_pct"]) / 100)
            if community_total else 0
        )
        community_gap = max(0, community_target - community_dual)
        invited = int(item.get("invited") or 0)
        assisted = int(item.get("assisted") or 0)

        old_dual = _community_old_dual(
            history,
            community,
            int(cfg["stalled_days"]),
        )
        stalled = bool(
            old_dual is not None
            and community_gap > 0
            and community_dual <= int(old_dual)
        )

        if community_gap <= 0:
            activity = "target_reached"
        elif stalled:
            activity = "stalled"
        elif community_dual == 0 and invited == 0 and assisted == 0:
            activity = "not_started"
        elif invited or assisted:
            activity = "active"
        else:
            activity = "pending"

        if community_dual == 0 and community_gap >= 15:
            priority = "critical"
            score = 400 + community_gap
        elif community_gap >= 10 or community_pct < 25:
            priority = "high"
            score = 300 + community_gap
        elif community_gap >= 5:
            priority = "medium"
            score = 200 + community_gap
        else:
            priority = "low"
            score = 100 + community_gap

        if stalled:
            score += 50
        if activity == "not_started":
            score += 25

        priority_rows.append({
            **item,
            "target_count": community_target,
            "gap_to_target": community_gap,
            "priority": priority,
            "priority_score": score,
            "activity": activity,
            "stalled": stalled,
            "old_dual": old_dual,
        })

    allocation = _allocate_daily_target(priority_rows, daily_target)
    for row in priority_rows:
        row["daily_target"] = int(allocation.get(str(row["community"]), 0))

    priority_rows.sort(
        key=lambda row: (
            -int(row.get("priority_score") or 0),
            -int(row.get("gap_to_target") or 0),
            str(row.get("community") or ""),
        )
    )
    for idx, row in enumerate(priority_rows, start=1):
        row["rank"] = idx

    dual_pct = round((dual / total) * 100.0, 1) if total else 0.0
    if dual_pct < float(cfg["target_pct"]):
        gate_state = "closed"
        gate_condition_met = False
    elif dual_pct < float(cfg["operational_goal_pct"]):
        gate_state = "pilot_ready"
        gate_condition_met = True
    else:
        gate_state = "operational_ready"
        gate_condition_met = True

    live_feature_enabled = False
    live_allowed = bool(gate_condition_met and live_feature_enabled)

    if not gate_condition_met:
        gate_reason = (
            f"Coverage {dual_pct:.1f}% ยังต่ำกว่าเกณฑ์ "
            f"{int(cfg['target_pct'])}%"
        )
    elif not live_feature_enabled:
        gate_reason = (
            "Coverage ผ่านเกณฑ์แล้ว แต่ Live Failover "
            "ยังไม่ถูกเปิดใช้ใน Phase 3.4"
        )
    else:
        gate_reason = "Readiness Gate ผ่านและ Live Failover เปิดใช้งาน"

    today_gain = history_stats.get("today_gain")
    if today_gain is None:
        daily_status = "baseline"
    elif today_gain >= daily_target:
        daily_status = "on_track"
    else:
        daily_status = "behind"

    not_started = [
        row for row in priority_rows
        if row.get("activity") == "not_started"
        and int(row.get("gap_to_target") or 0) > 0
    ]
    stalled_rows = [
        row for row in priority_rows
        if row.get("activity") == "stalled"
    ]

    alerts = []
    if gate_state == "closed":
        alerts.append({
            "level": "critical",
            "code": "readiness_gate_closed",
            "message": (
                f"Readiness Gate ปิด: ต้องเพิ่ม dual-ready อีก "
                f"{gap_to_target} คนเพื่อถึง {int(cfg['target_pct'])}%"
            ),
        })
    if daily_status == "behind":
        alerts.append({
            "level": "warning",
            "code": "daily_target_behind",
            "message": (
                f"ความคืบหน้าวันนี้ {today_gain or 0} คน "
                f"ต่ำกว่าเป้า {daily_target} คน/วัน"
            ),
        })
    if not_started:
        names = ", ".join(str(row["community"]) for row in not_started[:5])
        suffix = f" และอีก {len(not_started)-5} ชุมชน" if len(not_started) > 5 else ""
        alerts.append({
            "level": "warning",
            "code": "communities_not_started",
            "message": f"ชุมชนยังไม่เริ่ม onboarding: {names}{suffix}",
        })
    if stalled_rows:
        names = ", ".join(str(row["community"]) for row in stalled_rows[:5])
        suffix = f" และอีก {len(stalled_rows)-5} ชุมชน" if len(stalled_rows) > 5 else ""
        alerts.append({
            "level": "warning",
            "code": "communities_stalled",
            "message": f"ชุมชนไม่เพิ่ม dual-ready ตามช่วงตรวจ: {names}{suffix}",
        })

    return {
        "generated_at": datetime.now(TZ).isoformat(timespec="seconds"),
        "config": cfg,
        "summary": {
            "volunteers_total": total,
            "dual_ready": dual,
            "dual_pct": dual_pct,
            "target_count": target_count,
            "goal_count": goal_count,
            "gap_to_target": gap_to_target,
            "gap_to_goal": gap_to_goal,
            "daily_target": daily_target,
            "target_days": int(cfg["target_days"]),
            "today_gain": history_stats.get("today_gain"),
            "avg_daily_gain": history_stats.get("avg_daily_gain"),
            "eta_days": history_stats.get("eta_days"),
            "history_days": history_stats.get("history_days"),
            "daily_status": daily_status,
            "not_started_communities": len(not_started),
            "stalled_communities": len(stalled_rows),
        },
        "gate": {
            "state": gate_state,
            "condition_met": gate_condition_met,
            "target_pct": int(cfg["target_pct"]),
            "operational_goal_pct": int(cfg["operational_goal_pct"]),
            "live_failover_feature_enabled": live_feature_enabled,
            "live_failover_allowed": live_allowed,
            "reason": gate_reason,
        },
        "alerts": alerts,
        "communities": priority_rows,
        "policy": {
            "live_send_added_in_phase34": False,
            "readiness_gate_enforced_for_future_live_failover": True,
            "dual_ready_is_verified_mapping_only": True,
            "phi_in_acceleration_dashboard": False,
        },
    }


def save_settings(db, body: ReadinessSettingsBody, actor: str) -> dict:
    if body.target_pct >= body.operational_goal_pct:
        raise HTTPException(
            422,
            "เป้า Operational ต้องสูงกว่า Readiness Gate",
        )

    cfg = body.model_dump()
    _save_settings(cfg)
    db.add(Audit(
        actor=actor,
        action="appointment_notice_readiness_settings",
        entity="appointment_notice",
        detail={
            **cfg,
            "contains_phi": False,
            "live_failover_enabled": False,
        },
    ))
    db.commit()
    return acceleration_status(db)


def install_appointment_notice_phase34(app, auth, db_session, admin):
    @app.get("/api/v1/appointment-notices/failover/acceleration")
    def phase34_acceleration(
        u=Depends(auth),
        db=Depends(db_session),
    ):
        admin(u)
        return acceleration_status(db)

    @app.post("/api/v1/appointment-notices/failover/acceleration/settings")
    def phase34_settings(
        body: ReadinessSettingsBody,
        u=Depends(auth),
        db=Depends(db_session),
    ):
        admin(u)
        return save_settings(db, body, u.username)


if not CONFIG_FILE.exists():
    _save_settings(dict(DEFAULTS))