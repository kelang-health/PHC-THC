from __future__ import annotations

import json
import sqlite3
import time
import urllib.error
import urllib.request
from pathlib import Path

from fastapi import Depends, HTTPException
from pydantic import BaseModel, Field

from .database import Audit, CloudLineLink, PRIVATE, User, Volunteer, now
from .line_oa import _line_api, _setting as _line_setting

CONFIG_FILE = PRIVATE / "line_oa_failover.json"
TOKEN_FILE = Path(r"D:\AppServ\private\osm-vhv-failover.token")
PATIENT_REF_DB = Path(r"D:\AppServ\private\line-service-hub-connector-state.sqlite3")
HUB_BASE = "http://127.0.0.1:8776/api/v1/internal/vhv-failover"

DEFAULTS = {
    "enabled": True,
    "backup_enabled": True,
    "primary_basic_id": "@322ozezc",
    "backup_basic_id": "@601cnwrw",
    "warn_usage_pct": 90,
    "failover_usage_pct": 95,
    "primary_reserve": 15,
}

_STATUS_CACHE: dict[str, tuple[float, dict]] = {}


class FailoverSettingsBody(BaseModel):
    enabled: bool = True
    backup_enabled: bool = True
    warn_usage_pct: int = Field(default=90, ge=50, le=99)
    failover_usage_pct: int = Field(default=95, ge=60, le=100)
    primary_reserve: int = Field(default=15, ge=0, le=1000)


def _load_config() -> dict:
    data = {}
    if CONFIG_FILE.exists():
        try:
            raw = json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
            if isinstance(raw, dict):
                data = raw
        except Exception:
            data = {}
    cfg = dict(DEFAULTS)
    cfg.update({k: v for k, v in data.items() if k in DEFAULTS})
    return cfg


def _save_config(cfg: dict) -> None:
    CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
    temp = CONFIG_FILE.with_suffix(".json.tmp")
    temp.write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding="utf-8")
    temp.replace(CONFIG_FILE)


def _bridge_token() -> str:
    try:
        value = TOKEN_FILE.read_text(encoding="utf-8").strip()
    except Exception:
        raise HTTPException(503, "ไม่พบกุญแจเชื่อม OA สำรอง") from None
    if len(value) < 32:
        raise HTTPException(503, "กุญแจเชื่อม OA สำรองไม่พร้อม")
    return value


def _hub_json(method: str, path: str, body: dict | None = None, timeout: int = 12) -> dict:
    payload = None
    headers = {"X-VHV-Failover-Token": _bridge_token()}
    if body is not None:
        payload = json.dumps(body, ensure_ascii=False).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(
        HUB_BASE + path,
        data=payload,
        headers=headers,
        method=method.upper(),
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            data = json.loads(response.read().decode("utf-8"))
            return data if isinstance(data, dict) else {}
    except urllib.error.HTTPError as exc:
        detail = ""
        try:
            payload = json.loads(exc.read().decode("utf-8"))
            detail = str(payload.get("detail") or "")
        except Exception:
            detail = ""
        raise HTTPException(int(exc.code or 502), detail or f"OA สำรองตอบ HTTP {exc.code}") from None
    except Exception:
        raise HTTPException(503, "ติดต่อ LINE Service Hub สำหรับ OA สำรองไม่สำเร็จ") from None


def _quota_shape(*, ready: bool, basic_id: str, display_name: str,
                 quota_type: str, limit, used: int, remaining, error: str = "") -> dict:
    pct = round((used / limit) * 100.0, 2) if isinstance(limit, int) and limit > 0 else 0.0
    return {
        "ready": bool(ready),
        "basic_id": str(basic_id or ""),
        "display_name": str(display_name or "")[:120],
        "quota_type": str(quota_type or ""),
        "limit": limit if isinstance(limit, int) else None,
        "used": max(0, int(used or 0)),
        "remaining": max(0, int(remaining)) if isinstance(remaining, int) else None,
        "usage_pct": pct,
        "error": str(error or "")[:120],
    }


def primary_status(db, *, force: bool = False) -> dict:
    key = "primary"
    cached = _STATUS_CACHE.get(key)
    if cached and not force and time.time() - cached[0] < 30:
        return cached[1]
    cfg = _load_config()
    row = _line_setting(db)
    expected = str(cfg.get("primary_basic_id") or "").strip()
    try:
        info = _line_api(row, "GET", "/v2/bot/info")
        quota = _line_api(row, "GET", "/v2/bot/message/quota")
        usage = _line_api(row, "GET", "/v2/bot/message/quota/consumption")
        actual = str(info.get("basicId") or "")
        qtype = str(quota.get("type") or "")
        limit = int(quota.get("value") or 0) if qtype == "limited" else None
        used = max(0, int(usage.get("totalUsage") or 0))
        remaining = max(0, limit - used) if limit is not None else None
        result = _quota_shape(
            ready=bool(actual and (not expected or actual == expected)),
            basic_id=actual or expected,
            display_name=str(info.get("displayName") or ""),
            quota_type=qtype,
            limit=limit,
            used=used,
            remaining=remaining,
            error="" if not expected or actual == expected else "basic_id_mismatch",
        )
    except Exception as exc:
        result = _quota_shape(
            ready=False,
            basic_id=expected,
            display_name="",
            quota_type="",
            limit=None,
            used=0,
            remaining=None,
            error=type(exc).__name__,
        )
    _STATUS_CACHE[key] = (time.time(), result)
    return result


def backup_status(*, force: bool = False) -> dict:
    key = "backup"
    cached = _STATUS_CACHE.get(key)
    if cached and not force and time.time() - cached[0] < 30:
        return cached[1]
    cfg = _load_config()
    expected = str(cfg.get("backup_basic_id") or "").strip()
    try:
        result = _hub_json("GET", "/status")
        actual = str(result.get("basic_id") or "")
        result["ready"] = bool(
            result.get("ready") and actual and (not expected or actual == expected)
        )
        if expected and actual != expected:
            result["error"] = "basic_id_mismatch"
    except HTTPException as exc:
        result = _quota_shape(
            ready=False,
            basic_id=expected,
            display_name="",
            quota_type="",
            limit=None,
            used=0,
            remaining=None,
            error=f"http_{exc.status_code}",
        )
    _STATUS_CACHE[key] = (time.time(), result)
    return result


def _refs_for_pids(pids: list[int]) -> dict[int, str]:
    ids = sorted({int(pid) for pid in pids if int(pid or 0) > 0})
    if not ids or not PATIENT_REF_DB.exists():
        return {}
    placeholders = ",".join("?" for _ in ids)
    uri = f"file:{PATIENT_REF_DB.as_posix()}?mode=ro"
    try:
        conn = sqlite3.connect(uri, uri=True, timeout=3)
        rows = conn.execute(
            f"SELECT pid, local_patient_ref FROM patient_refs "
            f"WHERE is_active=1 AND pid IN ({placeholders})",
            ids,
        ).fetchall()
        conn.close()
    except Exception:
        return {}
    return {int(pid): str(ref) for pid, ref in rows if str(ref).startswith("lp_")}


def backup_refs_for_volunteers(db, volunteer_ids: list[int]) -> dict[int, str]:
    ids = sorted({int(v) for v in volunteer_ids if int(v or 0) > 0})
    if not ids:
        return {}
    volunteers = db.query(Volunteer).filter(Volunteer.id.in_(ids)).all()
    pid_by_vid = {
        int(v.id): int(v.jhcis_pid)
        for v in volunteers
        if v.jhcis_pid and int(v.jhcis_pid) > 0
    }
    ref_by_pid = _refs_for_pids(list(pid_by_vid.values()))
    candidate = {
        vid: ref_by_pid[pid]
        for vid, pid in pid_by_vid.items()
        if pid in ref_by_pid
    }
    if not candidate:
        return {}
    try:
        resolved = _hub_json(
            "POST",
            "/resolve",
            {"local_patient_refs": list(candidate.values())},
        )
    except HTTPException:
        return {}
    ready = {str(x) for x in (resolved.get("ready_refs") or [])}
    return {vid: ref for vid, ref in candidate.items() if ref in ready}


def backup_push(*, local_patient_ref: str, messages: list[str],
                dedupe_key: str, request_id: str, dry_run: bool = False) -> dict:
    return _hub_json(
        "POST",
        "/push",
        {
            "local_patient_ref": local_patient_ref,
            "messages": [str(x) for x in messages][:5],
            "dedupe_key": ("osm:" + str(dedupe_key))[:180],
            "request_id": str(request_id)[:64],
            "dry_run": bool(dry_run),
        },
        timeout=15,
    )


def _state(primary: dict, cfg: dict, projected_groups: int = 0) -> str:
    if not primary.get("ready"):
        return "primary_unavailable"
    if primary.get("remaining") is not None and int(primary["remaining"]) <= 0:
        return "primary_exhausted"
    pct = float(primary.get("usage_pct") or 0)
    if pct >= float(cfg.get("failover_usage_pct") or 95):
        return "failover"
    if primary.get("remaining") is not None:
        reserve = max(0, int(cfg.get("primary_reserve") or 0))
        if int(primary["remaining"]) < int(projected_groups) + reserve:
            return "failover"
    if pct >= float(cfg.get("warn_usage_pct") or 90):
        return "warning"
    return "primary"


def route_groups(db, groups: list[dict]) -> dict:
    cfg = _load_config()
    primary = primary_status(db, force=True)
    backup = backup_status(force=True) if cfg.get("enabled") and cfg.get("backup_enabled") else {
        "ready": False, "basic_id": str(cfg.get("backup_basic_id") or ""), "remaining": None,
        "used": 0, "limit": None, "usage_pct": 0.0, "error": "disabled",
    }
    ids = [int(g.get("volunteer_id") or 0) for g in groups]
    backup_refs = (
        backup_refs_for_volunteers(db, ids)
        if cfg.get("enabled") and cfg.get("backup_enabled") and backup.get("ready")
        else {}
    )
    state = _state(primary, cfg, len(groups))
    decisions = []
    primary_slots = (
        int(primary.get("remaining") or 0)
        if primary.get("remaining") is not None
        else 10 ** 9
    ) if primary.get("ready") else 0
    backup_slots = (
        int(backup.get("remaining") or 0)
        if backup.get("remaining") is not None
        else 10 ** 9
    ) if backup.get("ready") else 0

    for group in groups:
        vid = int(group.get("volunteer_id") or 0)
        bref = backup_refs.get(vid)
        backup_candidate = bool(
            bref and backup.get("ready") and backup_slots > 0
        )
        prefer_backup = bool(
            cfg.get("enabled")
            and state in {"failover", "primary_exhausted", "primary_unavailable"}
            and backup_candidate
        )

        if not cfg.get("enabled"):
            if primary_slots > 0:
                provider, reason = "primary", "failover_disabled"
                primary_slots -= 1
            else:
                provider, reason = "none", "primary_quota_unavailable"
        elif prefer_backup:
            provider, reason = "backup", state
            backup_slots -= 1
        elif primary_slots > 0:
            provider, reason = "primary", "primary_available"
            primary_slots -= 1
        elif backup_candidate:
            provider, reason = "backup", "primary_capacity_exhausted"
            backup_slots -= 1
        else:
            provider, reason = "none", "no_provider_capacity"

        decisions.append({
            "volunteer_id": vid,
            "provider": provider,
            "reason": reason,
            "backup_ref": bref or "",
            "backup_ready": bool(bref),
        })
    return {
        "config": cfg,
        "state": state,
        "primary": primary,
        "backup": backup,
        "decisions": decisions,
        "backup_ready_groups": sum(1 for x in decisions if x["backup_ready"]),
        "primary_groups": sum(1 for x in decisions if x["provider"] == "primary"),
        "backup_groups": sum(1 for x in decisions if x["provider"] == "backup"),
        "blocked_groups": sum(1 for x in decisions if x["provider"] == "none"),
    }


def coverage(db) -> dict:
    volunteers = db.query(Volunteer).all()
    volunteer_ids = [int(v.id) for v in volunteers]
    mapped = backup_refs_for_volunteers(db, volunteer_ids)
    staff = db.query(User).filter(User.role == "staff", User.active.is_(True)).all()
    staff_ready = sum(
        1 for user in staff
        if user.volunteer_id and int(user.volunteer_id) in mapped
    )
    primary_links = db.query(CloudLineLink).filter(
        CloudLineLink.active.is_(True),
        CloudLineLink.profile_active.is_(True),
    ).all()
    return {
        "volunteers_total": len(volunteers),
        "primary_linked_volunteers": len({
            int(x.volunteer_id) for x in primary_links if x.volunteer_id
        }),
        "backup_ready_volunteers": len(mapped),
        "backup_not_ready_volunteers": max(0, len(volunteers) - len(mapped)),
        "staff_total": len(staff),
        "backup_ready_staff": staff_ready,
    }


def public_status(db) -> dict:
    cfg = _load_config()
    primary = primary_status(db, force=True)
    backup = backup_status(force=True) if cfg.get("backup_enabled") else {
        "ready": False, "basic_id": str(cfg.get("backup_basic_id") or ""), "error": "disabled",
        "limit": None, "used": 0, "remaining": None, "usage_pct": 0.0,
    }
    cov = coverage(db)
    state = _state(primary, cfg, 0)
    return {
        "enabled": bool(cfg.get("enabled")),
        "backup_enabled": bool(cfg.get("backup_enabled")),
        "state": state,
        "config": cfg,
        "primary": primary,
        "backup": backup,
        "coverage": cov,
        "policy": {
            "cross_oa_dedupe": True,
            "backup_requires_verified_pid_mapping": True,
            "raw_line_id_exposed": False,
            "backup_token_stored_in_osm": False,
        },
    }


def save_settings(db, body: FailoverSettingsBody, actor: str) -> dict:
    if body.warn_usage_pct >= body.failover_usage_pct:
        raise HTTPException(422, "ค่าเตือนต้องต่ำกว่าค่าเริ่ม failover")
    cfg = _load_config()
    cfg.update(body.model_dump())
    _save_config(cfg)
    _STATUS_CACHE.clear()
    db.add(Audit(
        actor=actor,
        action="line_oa_failover_settings",
        entity="appointment_notice",
        detail={
            "enabled": cfg["enabled"],
            "backup_enabled": cfg["backup_enabled"],
            "warn_usage_pct": cfg["warn_usage_pct"],
            "failover_usage_pct": cfg["failover_usage_pct"],
            "primary_reserve": cfg["primary_reserve"],
            "raw_line_id_logged": False,
        },
    ))
    db.commit()
    return public_status(db)


def install_line_oa_failover(app, auth, db_session, admin):
    @app.get("/api/v1/appointment-notices/failover/status")
    def failover_status_endpoint(u=Depends(auth), db=Depends(db_session)):
        admin(u)
        return public_status(db)

    @app.post("/api/v1/appointment-notices/failover/settings")
    def failover_settings_endpoint(
        body: FailoverSettingsBody, u=Depends(auth), db=Depends(db_session),
    ):
        admin(u)
        return save_settings(db, body, u.username)


if not CONFIG_FILE.exists():
    _save_config(dict(DEFAULTS))