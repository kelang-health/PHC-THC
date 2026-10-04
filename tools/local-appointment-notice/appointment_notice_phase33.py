from __future__ import annotations

import argparse
import json
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from fastapi import Depends, HTTPException
from pydantic import BaseModel, Field

from .appointment_notice_phase32 import coverage_detail
from .database import Audit, PRIVATE, Session, now
from .line_oa_failover import backup_push, backup_refs_for_volunteers, backup_status

TZ = ZoneInfo("Asia/Bangkok")
TRACKER_FILE = PRIVATE / "appointment_notice_onboarding_tracker.json"
HISTORY_FILE = PRIVATE / "appointment_notice_onboarding_history.json"


class RolloutUpdateBody(BaseModel):
    volunteer_id: int = Field(ge=1)
    status: str = Field(pattern=r"^(pending|invited|assisted)$")


class DrillBody(BaseModel):
    volunteer_ids: list[int] = Field(min_length=1, max_length=20)


def _read_json(path: Path, default):
    if not path.exists():
        return default
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value
    except Exception:
        return default


def _write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(
        json.dumps(value, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    temp.replace(path)


def _tracker() -> dict[str, dict]:
    raw = _read_json(TRACKER_FILE, {})
    return raw if isinstance(raw, dict) else {}


def _history() -> list[dict]:
    raw = _read_json(HISTORY_FILE, [])
    return raw if isinstance(raw, list) else []


def rollout_status(db, *, community: str = "") -> dict:
    coverage = coverage_detail(db, community=community)
    tracker = _tracker()
    today = datetime.now(TZ).date().isoformat()

    rows = []
    counters = {
        "pending": 0,
        "invited": 0,
        "assisted": 0,
        "dual_ready": 0,
        "today_touched": 0,
    }
    for row in coverage.get("rows") or []:
        vid = int(row["volunteer_id"])
        tracked = tracker.get(str(vid)) or {}
        if row.get("dual_ready"):
            effective = "dual_ready"
        else:
            effective = str(tracked.get("status") or "pending")
            if effective not in {"pending", "invited", "assisted"}:
                effective = "pending"
        counters[effective] = counters.get(effective, 0) + 1
        updated_at = str(tracked.get("updated_at") or "")
        if updated_at.startswith(today):
            counters["today_touched"] += 1
        rows.append({
            **row,
            "rollout_status": effective,
            "last_action_at": updated_at,
        })

    communities: dict[str, dict] = {}
    for row in rows:
        name = str(row.get("community") or "ไม่ระบุชุมชน")
        group = communities.setdefault(name, {
            "community": name,
            "total": 0,
            "pending": 0,
            "invited": 0,
            "assisted": 0,
            "dual_ready": 0,
        })
        group["total"] += 1
        group[row["rollout_status"]] += 1

    for group in communities.values():
        total = int(group["total"] or 0)
        group["dual_pct"] = round(
            (int(group["dual_ready"]) / total) * 100.0, 1
        ) if total else 0.0
        group["remaining"] = max(0, total - int(group["dual_ready"]))

    history = _history()
    return {
        "generated_at": datetime.now(TZ).isoformat(timespec="seconds"),
        "summary": {
            **coverage.get("summary", {}),
            **counters,
        },
        "communities": sorted(
            communities.values(),
            key=lambda x: (-int(x["remaining"]), x["community"]),
        ),
        "rows": rows,
        "history": history[-31:],
        "onboarding": coverage.get("onboarding") or {},
        "rules": {
            "dual_ready_is_automatic": True,
            "manual_statuses": ["pending", "invited", "assisted"],
            "max_drill_per_community": 2,
            "drill_is_dry_run_only": True,
        },
    }


def update_rollout(db, body: RolloutUpdateBody, actor: str) -> dict:
    coverage = coverage_detail(db)
    match = next(
        (
            row for row in coverage.get("rows") or []
            if int(row.get("volunteer_id") or 0) == int(body.volunteer_id)
        ),
        None,
    )
    if match is None:
        raise HTTPException(404, "ไม่พบ อสม. ในทะเบียน Local")

    tracker = _tracker()
    if match.get("dual_ready"):
        tracker.pop(str(body.volunteer_id), None)
        _write_json(TRACKER_FILE, tracker)
        return {
            "status": "dual_ready",
            "volunteer_id": int(body.volunteer_id),
            "message": "รายนี้พร้อมทั้ง 2 OA จาก mapping จริงแล้ว",
        }

    tracker[str(body.volunteer_id)] = {
        "status": body.status,
        "updated_at": datetime.now(TZ).isoformat(timespec="seconds"),
        "actor": str(actor or "")[:100],
    }
    _write_json(TRACKER_FILE, tracker)

    db.add(Audit(
        actor=actor,
        action="appointment_notice_onboarding_status",
        entity="volunteer",
        detail={
            "volunteer_id": int(body.volunteer_id),
            "status": body.status,
            "community": str(match.get("community") or "")[:191],
            "contains_cid": False,
            "contains_line_user_id": False,
        },
    ))
    db.commit()
    return {
        "status": body.status,
        "volunteer_id": int(body.volunteer_id),
        "updated_at": tracker[str(body.volunteer_id)]["updated_at"],
    }


def record_daily_snapshot(db, *, actor: str = "system:onboarding-snapshot") -> dict:
    data = rollout_status(db)
    summary = data.get("summary") or {}
    date_key = datetime.now(TZ).date().isoformat()
    entry = {
        "date": date_key,
        "recorded_at": datetime.now(TZ).isoformat(timespec="seconds"),
        "volunteers_total": int(summary.get("volunteers_total") or 0),
        "dual_ready": int(summary.get("dual_ready") or 0),
        "dual_pct": float(summary.get("dual_pct") or 0),
        "pending": int(summary.get("pending") or 0),
        "invited": int(summary.get("invited") or 0),
        "assisted": int(summary.get("assisted") or 0),
        "gap_to_90": int(summary.get("gap_to_90") or 0),
        "gap_to_95": int(summary.get("gap_to_95") or 0),
        "communities": [
            {
                "community": str(row.get("community") or "")[:191],
                "total": int(row.get("total") or 0),
                "dual_ready": int(row.get("dual_ready") or 0),
                "dual_pct": float(row.get("dual_pct") or 0),
                "remaining": int(row.get("remaining") or 0),
            }
            for row in data.get("communities") or []
        ],
    }

    history = _history()
    history = [row for row in history if str(row.get("date")) != date_key]
    history.append(entry)
    history = sorted(history, key=lambda x: str(x.get("date") or ""))[-180:]
    _write_json(HISTORY_FILE, history)

    db.add(Audit(
        actor=actor,
        action="appointment_notice_onboarding_snapshot",
        entity="appointment_notice",
        detail={
            "date": date_key,
            "dual_ready": entry["dual_ready"],
            "dual_pct": entry["dual_pct"],
            "gap_to_90": entry["gap_to_90"],
            "contains_phi": False,
        },
    ))
    db.commit()
    return entry


def controlled_drill(db, body: DrillBody, actor: str) -> dict:
    requested = []
    seen = set()
    for raw in body.volunteer_ids:
        vid = int(raw)
        if vid not in seen:
            requested.append(vid)
            seen.add(vid)

    coverage = coverage_detail(db)
    by_id = {
        int(row["volunteer_id"]): row
        for row in coverage.get("rows") or []
    }
    selected = []
    community_counts: dict[str, int] = {}
    for vid in requested:
        row = by_id.get(vid)
        if row is None:
            raise HTTPException(404, f"ไม่พบ อสม. ID {vid}")
        if not row.get("dual_ready"):
            raise HTTPException(
                409,
                f"{row.get('name') or 'อสม.'} ยังไม่พร้อมทั้ง Primary + Backup",
            )
        community = str(row.get("community") or "ไม่ระบุชุมชน")
        community_counts[community] = community_counts.get(community, 0) + 1
        if community_counts[community] > 2:
            raise HTTPException(
                422,
                f"Controlled drill จำกัดไม่เกิน 2 คนต่อชุมชน: {community}",
            )
        selected.append(row)

    backup = backup_status(force=True)
    if not backup.get("ready"):
        raise HTTPException(503, "OA สำรองไม่พร้อมสำหรับ dry-run")

    refs = backup_refs_for_volunteers(db, requested)
    results = []
    passed = 0
    for row in selected:
        vid = int(row["volunteer_id"])
        ref = refs.get(vid)
        if not ref:
            results.append({
                "volunteer_id": vid,
                "name": str(row.get("name") or ""),
                "community": str(row.get("community") or ""),
                "status": "failed",
                "reason": "backup_mapping_not_ready",
            })
            continue
        try:
            response = backup_push(
                local_patient_ref=ref,
                messages=["CONTROLLED FAILOVER DRILL - DRY RUN ONLY"],
                dedupe_key=f"phase33:drill:{vid}:{datetime.now(TZ).date().isoformat()}",
                request_id=f"p33-{vid}-{datetime.now(TZ).strftime('%H%M%S')}",
                dry_run=True,
            )
            ok = str(response.get("status") or "") == "ready"
        except HTTPException as exc:
            ok = False
            response = {"reason": f"http_{exc.status_code}"}
        if ok:
            passed += 1
        results.append({
            "volunteer_id": vid,
            "name": str(row.get("name") or ""),
            "community": str(row.get("community") or ""),
            "status": "passed" if ok else "failed",
            "reason": "" if ok else str(response.get("reason") or "dry_run_failed"),
            "backup_basic_id": str(response.get("basic_id") or backup.get("basic_id") or ""),
        })

    db.add(Audit(
        actor=actor,
        action="appointment_notice_controlled_failover_drill",
        entity="appointment_notice",
        detail={
            "selected_count": len(selected),
            "passed": passed,
            "failed": len(selected) - passed,
            "community_count": len(community_counts),
            "dry_run": True,
            "live_message_sent": False,
            "contains_line_user_id": False,
            "contains_cid": False,
        },
    ))
    db.commit()

    return {
        "status": "passed" if passed == len(selected) else "partial",
        "dry_run": True,
        "live_message_sent": False,
        "selected_count": len(selected),
        "passed": passed,
        "failed": len(selected) - passed,
        "backup_basic_id": str(backup.get("basic_id") or ""),
        "results": results,
    }


def install_appointment_notice_phase33(app, auth, db_session, admin):
    @app.get("/api/v1/appointment-notices/failover/rollout")
    def phase33_rollout(
        community: str = "",
        u=Depends(auth),
        db=Depends(db_session),
    ):
        admin(u)
        return rollout_status(db, community=community[:191])

    @app.post("/api/v1/appointment-notices/failover/rollout/status")
    def phase33_rollout_update(
        body: RolloutUpdateBody,
        u=Depends(auth),
        db=Depends(db_session),
    ):
        admin(u)
        return update_rollout(db, body, u.username)

    @app.post("/api/v1/appointment-notices/failover/rollout/snapshot")
    def phase33_snapshot(u=Depends(auth), db=Depends(db_session)):
        admin(u)
        return record_daily_snapshot(db, actor=u.username)

    @app.post("/api/v1/appointment-notices/failover/drill")
    def phase33_drill(
        body: DrillBody,
        u=Depends(auth),
        db=Depends(db_session),
    ):
        admin(u)
        return controlled_drill(db, body, u.username)


def _cli() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--snapshot", action="store_true")
    args = parser.parse_args()
    if not args.snapshot:
        parser.error("--snapshot is required")
    db = Session()
    try:
        result = record_daily_snapshot(db)
        print(json.dumps(result, ensure_ascii=False))
        return 0
    finally:
        db.close()


if __name__ == "__main__":
    raise SystemExit(_cli())