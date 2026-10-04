from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path
from uuid import uuid4
from zoneinfo import ZoneInfo

from fastapi import Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import Boolean, Column, Integer, String, Text

from .appointment_notice_preview import build_preview
from .appointment_notice_phase2 import (
    AppointmentNoticeSendBody,
    execute_send,
    validate_send,
)
from .database import Audit, Base, PortableJSON, PRIVATE, Session, engine, now
from .line_oa_failover import primary_status, backup_status

TZ = ZoneInfo("Asia/Bangkok")
CONFIG_FILE = PRIVATE / "appointment_notice_auto.json"
TASK_NAME = "OSM-PHC Appointment D-1 Reminder"
RUNNER = Path(r"D:\AppServ\www\osm-phc\scripts\run_appointment_notice_phase3.ps1")
DEFAULTS = {
    "enabled": True,
    "schedule_time": "17:30",
    "send_vhv": True,
    "send_community": True,
    "community_target": "both",
    "max_late_minutes": 240,
    "batch_size": 180,
}


class AppointmentNoticeAutoRun(Base):
    __tablename__ = "phc_appointment_notice_auto_runs"
    id = Column(Integer, primary_key=True)
    run_key = Column(String(96), unique=True, nullable=False, index=True)
    run_id = Column(String(36), nullable=False, index=True)
    target_date = Column(String(10), nullable=False, index=True)
    trigger = Column(String(30), nullable=False, index=True)
    status = Column(String(40), nullable=False, index=True)
    dry_run = Column(Boolean, default=False, nullable=False)
    summary = Column(PortableJSON, default=dict)
    error_code = Column(String(100), default="")
    error_message = Column(Text, default="")
    started_at = Column(String(50), default=now, nullable=False, index=True)
    finished_at = Column(String(50), nullable=True)


class AutoSettingsBody(BaseModel):
    enabled: bool = True
    schedule_time: str = Field(pattern=r"^(?:[01]\d|2[0-3]):[0-5]\d$")
    send_vhv: bool = True
    send_community: bool = True
    community_target: str = Field(default="both", pattern=r"^(chair|staff|both)$")
    max_late_minutes: int = Field(default=240, ge=30, le=720)
    batch_size: int = Field(default=180, ge=25, le=200)


def _load_config() -> dict:
    data = {}
    if CONFIG_FILE.exists():
        try:
            raw = json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
            if isinstance(raw, dict):
                data = raw
        except Exception:
            data = {}
    merged = dict(DEFAULTS)
    merged.update({k: v for k, v in data.items() if k in DEFAULTS})
    return merged


def _save_config(config: dict) -> None:
    CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
    temp = CONFIG_FILE.with_suffix(".json.tmp")
    temp.write_text(json.dumps(config, ensure_ascii=False, indent=2), encoding="utf-8")
    temp.replace(CONFIG_FILE)


def _task_state() -> dict:
    try:
        result = subprocess.run(
            ["schtasks.exe", "/Query", "/TN", TASK_NAME, "/FO", "LIST", "/V"],
            capture_output=True,
            text=True,
            timeout=10,
            encoding="utf-8",
            errors="replace",
        )
        return {
            "installed": result.returncode == 0,
            "raw_status": "ready" if result.returncode == 0 else "missing",
        }
    except Exception:
        return {"installed": False, "raw_status": "unknown"}


def _sync_task(config: dict) -> dict:
    if not _task_state().get("installed"):
        raise HTTPException(503, "Windows Task สำหรับ Auto D-1 ยังไม่ได้ติดตั้ง")
    time_value = str(config["schedule_time"])
    args = ["schtasks.exe", "/Change", "/TN", TASK_NAME, "/ST", time_value]
    args.append("/ENABLE" if config["enabled"] else "/DISABLE")
    result = subprocess.run(
        args,
        capture_output=True,
        text=True,
        timeout=15,
        encoding="utf-8",
        errors="replace",
    )
    if result.returncode != 0:
        raise HTTPException(503, "ปรับเวลา Windows Task ไม่สำเร็จ")
    return _task_state()


def _chunks(items: list[str], size: int):
    for pos in range(0, len(items), size):
        yield items[pos:pos + size]


def _run_row(db, *, run_key: str, target_date: str, trigger: str, dry_run: bool):
    row = db.query(AppointmentNoticeAutoRun).filter(
        AppointmentNoticeAutoRun.run_key == run_key
    ).first()
    if row is None:
        row = AppointmentNoticeAutoRun(
            run_key=run_key,
            run_id=str(uuid4()),
            target_date=target_date,
            trigger=trigger,
            status="running",
            dry_run=dry_run,
            summary={},
            started_at=now(),
        )
        db.add(row)
        db.commit()
    else:
        row.run_id = str(uuid4())
        row.trigger = trigger
        row.status = "running"
        row.dry_run = dry_run
        row.summary = {}
        row.error_code = ""
        row.error_message = ""
        row.started_at = now()
        row.finished_at = None
        db.commit()
    return row


def _finish(db, row, *, status: str, summary: dict, error_code: str = "", error_message: str = ""):
    row.status = status
    row.summary = summary
    row.error_code = error_code[:100]
    row.error_message = error_message[:1000]
    row.finished_at = now()
    db.commit()


def _time_guard(config: dict, current: datetime) -> tuple[bool, str]:
    hour, minute = [int(x) for x in str(config["schedule_time"]).split(":")]
    scheduled = current.replace(hour=hour, minute=minute, second=0, microsecond=0)
    if current < scheduled:
        return False, "before_schedule"
    late_minutes = int((current - scheduled).total_seconds() // 60)
    if late_minutes > int(config["max_late_minutes"]):
        return False, "late_window_exceeded"
    return True, ""


def _body(*, preview: dict, case_ids: list[str], channel: str,
          community: str = "", target: str = "both", validate_only: bool = False):
    return AppointmentNoticeSendBody(
        from_date=preview["from_date"],
        to_date=preview["to_date"],
        case_ids=case_ids,
        channel=channel,
        community=community,
        filter_community="",
        filter_volunteer_id=0,
        recipient_target=target,
        policy="new_only",
        preview_token=preview["preview_token"],
        send_nonce=str(uuid4()),
        validate_only=validate_only,
    )


def run_auto(*, trigger: str = "scheduler", dry_run: bool = False,
             ignore_time_window: bool = False) -> dict:
    config = _load_config()
    current = datetime.now(TZ)
    target = (current.date() + timedelta(days=1)).isoformat()

    with Session() as db:
        if trigger == "scheduler" and not config["enabled"]:
            return {"status": "disabled", "target_date": target}

        if trigger == "scheduler" and not ignore_time_window:
            allowed, reason = _time_guard(config, current)
            if not allowed:
                return {"status": "skipped", "reason": reason, "target_date": target}

        run_key = (
            f"d1:{target}" if not dry_run
            else f"dry:{target}:{uuid4()}"
        )
        previous = db.query(AppointmentNoticeAutoRun).filter(
            AppointmentNoticeAutoRun.run_key == run_key
        ).first()
        if previous and previous.status in {"sent", "nothing_to_send"} and not dry_run:
            return {
                "status": "already_completed",
                "target_date": target,
                "run_id": previous.run_id,
                "summary": previous.summary or {},
            }

        row = _run_row(
            db, run_key=run_key, target_date=target, trigger=trigger, dry_run=dry_run
        )

        summary = {
            "target_date": target,
            "appointments": 0,
            "people": 0,
            "houses": 0,
            "vhv_ready_cases": 0,
            "no_line_cases": 0,
            "unassigned_cases": 0,
            "vhv_batches": 0,
            "vhv_sent_groups": 0,
            "vhv_failed_groups": 0,
            "community_batches": 0,
            "community_sent_groups": 0,
            "community_failed_groups": 0,
            "communities_with_appointments": 0,
            "communities_without_ready_recipient": 0,
            "duplicate_cases_skipped": 0,
            "primary_groups": 0,
            "backup_groups": 0,
            "blocked_groups": 0,
        }

        try:
            primary_oa = primary_status(db, force=True)
            backup_oa = backup_status(force=True)
            summary["oa_ready"] = bool(primary_oa.get("ready") or backup_oa.get("ready"))
            summary["oa_basic_id"] = str(primary_oa.get("basic_id") or "")
            summary["backup_oa_basic_id"] = str(backup_oa.get("basic_id") or "")
            summary["primary_quota_remaining"] = primary_oa.get("remaining")
            summary["backup_quota_remaining"] = backup_oa.get("remaining")
            if not summary["oa_ready"]:
                _finish(
                    db, row, status="failed", summary=summary,
                    error_code="oa_not_ready",
                    error_message="ทั้ง LINE OA หลักและ OA สำรองไม่พร้อม",
                )
                return {"status": "failed", "reason": "oa_not_ready", "summary": summary}

            preview = build_preview(db, from_date=target, to_date=target)
            ps = preview.get("summary") or {}
            summary.update({
                "appointments": int(ps.get("appointments") or 0),
                "people": int(ps.get("people") or 0),
                "houses": int(ps.get("houses") or 0),
                "vhv_ready_cases": int(ps.get("line_ready_cases") or 0),
                "no_line_cases": int(ps.get("no_line_cases") or 0),
                "unassigned_cases": int(ps.get("unassigned_cases") or 0),
                "communities_with_appointments": len(preview.get("communities") or []),
            })

            if not preview.get("rows"):
                _finish(db, row, status="nothing_to_send", summary=summary)
                return {"status": "nothing_to_send", "summary": summary}

            batch_size = int(config["batch_size"])

            if config["send_vhv"]:
                ready_ids = [
                    str(item["case_id"])
                    for item in preview["rows"]
                    if item.get("assignment_status") == "ready"
                ]
                for case_ids in _chunks(ready_ids, batch_size):
                    if not case_ids:
                        continue
                    body = _body(
                        preview=preview, case_ids=case_ids, channel="vhv",
                        validate_only=dry_run,
                    )
                    result = validate_send(db, body) if dry_run else execute_send(
                        db, body, actor="system:auto-d1"
                    )
                    summary["vhv_batches"] += 1
                    summary["duplicate_cases_skipped"] += int(result.get("duplicate_deliveries") or 0)
                    if dry_run:
                        summary["vhv_sent_groups"] += len([
                            x for x in (result.get("recipients") or [])
                            if x.get("status") == "ready"
                        ])
                        summary["primary_groups"] += int(result.get("primary_groups") or 0)
                        summary["backup_groups"] += int(result.get("backup_groups") or 0)
                        summary["blocked_groups"] += int(result.get("blocked_groups") or 0)
                    else:
                        summary["vhv_sent_groups"] += int(result.get("sent_groups") or 0)
                        summary["vhv_failed_groups"] += int(result.get("failed_groups") or 0)
                        summary["primary_groups"] += int(result.get("primary_sent_groups") or 0)
                        summary["backup_groups"] += int(result.get("backup_sent_groups") or 0)
                        summary["blocked_groups"] += int(result.get("blocked_groups") or 0)

            if config["send_community"]:
                community_names = sorted({
                    str(item.get("community") or "").strip()
                    for item in preview["rows"]
                    if str(item.get("community") or "").strip()
                })

                for community in community_names:
                    community_preview = build_preview(
                        db, from_date=target, to_date=target, community=community
                    )
                    ids = [str(item["case_id"]) for item in community_preview.get("rows") or []]
                    community_had_recipient = False
                    for case_ids in _chunks(ids, batch_size):
                        body = _body(
                            preview=community_preview,
                            case_ids=case_ids,
                            channel="community",
                            community=community,
                            target=str(config["community_target"]),
                            validate_only=dry_run,
                        )
                        try:
                            result = validate_send(db, body) if dry_run else execute_send(
                                db, body, actor="system:auto-d1"
                            )
                        except HTTPException as exc:
                            if int(exc.status_code) in {409, 422}:
                                summary["community_failed_groups"] += 1
                                continue
                            raise
                        summary["community_batches"] += 1
                        if dry_run:
                            ready = [
                                x for x in (result.get("recipients") or [])
                                if x.get("status") == "ready"
                            ]
                            if ready:
                                community_had_recipient = True
                            summary["community_sent_groups"] += len(ready)
                            summary["primary_groups"] += int(result.get("primary_groups") or 0)
                            summary["backup_groups"] += int(result.get("backup_groups") or 0)
                            summary["blocked_groups"] += int(result.get("blocked_groups") or 0)
                        else:
                            sent = int(result.get("sent_groups") or 0)
                            if sent:
                                community_had_recipient = True
                            summary["community_sent_groups"] += sent
                            summary["community_failed_groups"] += int(result.get("failed_groups") or 0)
                            summary["primary_groups"] += int(result.get("primary_sent_groups") or 0)
                            summary["backup_groups"] += int(result.get("backup_sent_groups") or 0)
                            summary["blocked_groups"] += int(result.get("blocked_groups") or 0)
                    if not community_had_recipient:
                        summary["communities_without_ready_recipient"] += 1

            if dry_run:
                status = "validated"
            elif summary["vhv_failed_groups"] or summary["community_failed_groups"]:
                status = "partial" if (
                    summary["vhv_sent_groups"] or summary["community_sent_groups"]
                ) else "failed"
            elif summary["vhv_sent_groups"] or summary["community_sent_groups"]:
                status = "sent"
            else:
                status = "nothing_to_send"

            _finish(db, row, status=status, summary=summary)
            db.add(Audit(
                actor="system:auto-d1" if trigger == "scheduler" else "admin:auto-d1-test",
                action="appointment_notice_auto_d1",
                entity="appointment_notice",
                detail={
                    "run_id": row.run_id,
                    "target_date": target,
                    "status": status,
                    "dry_run": dry_run,
                    "summary": summary,
                    "message_content_logged": False,
                    "raw_line_id_logged": False,
                },
            ))
            db.commit()
            return {"status": status, "run_id": row.run_id, "summary": summary}
        except Exception as exc:
            _finish(
                db, row, status="failed", summary=summary,
                error_code=type(exc).__name__,
                error_message=str(exc),
            )
            return {
                "status": "failed",
                "run_id": row.run_id,
                "error_code": type(exc).__name__,
                "error": str(exc)[:500],
                "summary": summary,
            }


def status(db) -> dict:
    config = _load_config()
    runs = db.query(AppointmentNoticeAutoRun).order_by(
        AppointmentNoticeAutoRun.id.desc()
    ).limit(10).all()
    return {
        "phase": 3,
        "mode": "auto_d1",
        "config": config,
        "task": _task_state(),
        "last_runs": [{
            "run_id": item.run_id,
            "target_date": item.target_date,
            "trigger": item.trigger,
            "status": item.status,
            "dry_run": bool(item.dry_run),
            "summary": item.summary or {},
            "error_code": item.error_code or "",
            "started_at": item.started_at,
            "finished_at": item.finished_at,
        } for item in runs],
    }


def save_settings(db, body: AutoSettingsBody, actor: str) -> dict:
    config = body.model_dump()
    if not config["send_vhv"] and not config["send_community"]:
        raise HTTPException(422, "ต้องเปิดอย่างน้อย 1 ช่องทาง: อสม. หรือสรุปชุมชน")
    _save_config(config)
    task = _sync_task(config)
    db.add(Audit(
        actor=actor,
        action="appointment_notice_auto_settings",
        entity="appointment_notice",
        detail={
            **config,
            "phase": 3,
            "raw_line_id_logged": False,
        },
    ))
    db.commit()
    return {"config": config, "task": task}


def install_appointment_notice_phase3(app, auth, db_session, admin):
    AppointmentNoticeAutoRun.__table__.create(bind=engine, checkfirst=True)

    @app.get("/api/v1/appointment-notices/auto/status")
    def appointment_notice_auto_status(
        u=Depends(auth), db=Depends(db_session),
    ):
        admin(u)
        return status(db)

    @app.post("/api/v1/appointment-notices/auto/settings")
    def appointment_notice_auto_settings(
        body: AutoSettingsBody, u=Depends(auth), db=Depends(db_session),
    ):
        admin(u)
        return save_settings(db, body, u.username)

    @app.post("/api/v1/appointment-notices/auto/dry-run")
    def appointment_notice_auto_dry_run(
        u=Depends(auth),
    ):
        admin(u)
        return run_auto(trigger="admin_dry_run", dry_run=True, ignore_time_window=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scheduled", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    result = run_auto(
        trigger="scheduler" if args.scheduled else "cli",
        dry_run=bool(args.dry_run),
        ignore_time_window=bool(args.dry_run),
    )
    print(json.dumps(result, ensure_ascii=False, default=str))
    return 0 if result.get("status") not in {"failed", "partial"} else 2


AppointmentNoticeAutoRun.__table__.create(bind=engine, checkfirst=True)
if not CONFIG_FILE.exists():
    _save_config(dict(DEFAULTS))


if __name__ == "__main__":
    sys.exit(main())