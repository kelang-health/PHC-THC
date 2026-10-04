from __future__ import annotations

import hashlib
import os
import re
import secrets
import sqlite3
from datetime import UTC, datetime, timedelta
from pathlib import Path
from urllib.parse import quote

from sqlalchemy import select
from sqlalchemy.orm import Session

from hub_app.models import LineUser, PatientMapping

STATE_PATH = Path(
    os.getenv(
        "LINE_HUB_OSM_BRIDGE_STATE",
        r"D:\AppServ\private\line-service-hub-osm-bridge.sqlite3",
    )
)
BACKUP_BASIC_ID = "@601cnwrw"
TOKEN_RE = re.compile(r"^[A-Za-z0-9_-]{32,120}$")
COMMAND_RE = re.compile(
    r"^\s*เชื่อม(?:\s+oa)?\s*สำรอง\s+([A-Za-z0-9_-]{32,120})\s*$",
    re.IGNORECASE,
)


def utcnow() -> datetime:
    return datetime.now(UTC)


def _connect() -> sqlite3.Connection:
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(str(STATE_PATH), timeout=5)
    db.row_factory = sqlite3.Row
    db.execute(
        """
        CREATE TABLE IF NOT EXISTS osm_bridge_invites (
            token_hash TEXT PRIMARY KEY,
            local_patient_ref TEXT NOT NULL,
            created_at TEXT NOT NULL,
            expires_at TEXT NOT NULL,
            used_at TEXT,
            source TEXT NOT NULL DEFAULT 'osm_primary'
        )
        """
    )
    db.execute(
        "CREATE INDEX IF NOT EXISTS osm_bridge_invites_ref_idx "
        "ON osm_bridge_invites(local_patient_ref)"
    )
    db.execute(
        "CREATE INDEX IF NOT EXISTS osm_bridge_invites_exp_idx "
        "ON osm_bridge_invites(expires_at)"
    )
    db.commit()
    return db


def _hash_token(raw: str) -> str:
    return hashlib.sha256(str(raw).encode("utf-8")).hexdigest()


def parse_bridge_command(text: str) -> str:
    match = COMMAND_RE.fullmatch(str(text or "").strip())
    return match.group(1) if match else ""


def _deep_link(token: str) -> str:
    text = f"เชื่อมสำรอง {token}"
    return (
        "https://line.me/R/oaMessage/"
        + quote(BACKUP_BASIC_ID, safe="")
        + "/?"
        + quote(text, safe="")
    )


def issue_osm_bridge_invite(*, gateway, pid: int, ttl_seconds: int = 1800) -> dict:
    pid = int(pid)
    if pid < 1:
        raise ValueError("invalid pid")
    ttl_seconds = max(300, min(int(ttl_seconds), 3600))
    local_ref = str(gateway.patient_ref(pid=pid) or "").strip()
    if not local_ref.startswith("lp_"):
        raise ValueError("patient reference unavailable")

    token = secrets.token_urlsafe(32)
    token_hash = _hash_token(token)
    now = utcnow()
    expires = now + timedelta(seconds=ttl_seconds)

    with _connect() as db:
        # Keep one active invitation per patient reference.
        db.execute(
            "UPDATE osm_bridge_invites SET used_at=? "
            "WHERE local_patient_ref=? AND used_at IS NULL",
            (now.isoformat(), local_ref),
        )
        db.execute(
            "INSERT INTO osm_bridge_invites("
            "token_hash,local_patient_ref,created_at,expires_at,used_at,source"
            ") VALUES(?,?,?,?,NULL,'osm_primary')",
            (
                token_hash,
                local_ref,
                now.isoformat(),
                expires.isoformat(),
            ),
        )
        db.commit()

    return {
        "status": "issued",
        "claim_url": _deep_link(token),
        "expires_at": expires.isoformat(),
        "backup_basic_id": BACKUP_BASIC_ID,
    }


def validate_osm_bridge_pid(*, gateway, pid: int) -> dict:
    pid = int(pid)
    if pid < 1:
        raise ValueError("invalid pid")
    local_ref = str(gateway.patient_ref(pid=pid) or "").strip()
    if not local_ref.startswith("lp_"):
        raise ValueError("patient reference unavailable")
    return {
        "status": "ready",
        "backup_basic_id": BACKUP_BASIC_ID,
    }


def _invite_row(raw_token: str):
    token = str(raw_token or "").strip()
    if not TOKEN_RE.fullmatch(token):
        return None
    with _connect() as db:
        row = db.execute(
            "SELECT token_hash,local_patient_ref,created_at,expires_at,used_at "
            "FROM osm_bridge_invites WHERE token_hash=?",
            (_hash_token(token),),
        ).fetchone()
        return dict(row) if row is not None else None


def _mark_used(raw_token: str) -> None:
    now = utcnow().isoformat()
    with _connect() as db:
        db.execute(
            "UPDATE osm_bridge_invites SET used_at=? WHERE token_hash=?",
            (now, _hash_token(raw_token)),
        )
        db.commit()


def claim_osm_bridge_invite(
    db: Session,
    *,
    line_user_db_id: int,
    raw_token: str,
) -> dict:
    row = _invite_row(raw_token)
    if row is None:
        return {"status": "unavailable"}

    if row.get("used_at"):
        return {"status": "unavailable"}

    try:
        expires = datetime.fromisoformat(str(row.get("expires_at") or ""))
    except ValueError:
        return {"status": "unavailable"}
    if expires.tzinfo is None:
        expires = expires.replace(tzinfo=UTC)
    if expires <= utcnow():
        return {"status": "expired"}

    local_ref = str(row.get("local_patient_ref") or "").strip()
    if not local_ref.startswith("lp_"):
        return {"status": "unavailable"}

    user = db.get(LineUser, int(line_user_db_id))
    if user is None or user.status != "active":
        return {"status": "unavailable"}

    same_ref = list(
        db.scalars(
            select(PatientMapping).where(
                PatientMapping.local_patient_key == local_ref,
                PatientMapping.mapping_status == "verified",
            )
        ).all()
    )
    for mapping in same_ref:
        if int(mapping.line_user_id) != int(user.id):
            return {"status": "conflict_ref_in_use"}

    current = list(
        db.scalars(
            select(PatientMapping).where(
                PatientMapping.line_user_id == int(user.id),
                PatientMapping.mapping_status == "verified",
            )
        ).all()
    )
    if current:
        if any(str(item.local_patient_key) == local_ref for item in current):
            _mark_used(raw_token)
            return {"status": "already_ready"}
        return {"status": "conflict_user_mapped"}

    mapping = PatientMapping(
        line_user_id=int(user.id),
        local_patient_key=local_ref,
        mapping_status="verified",
        verified_at=utcnow(),
        verified_method="osm_primary_bridge",
    )
    db.add(mapping)
    db.commit()
    _mark_used(raw_token)
    return {"status": "linked"}


def bridge_stats() -> dict:
    now = utcnow()
    with _connect() as db:
        rows = db.execute(
            "SELECT expires_at,used_at FROM osm_bridge_invites"
        ).fetchall()
    total = len(rows)
    used = sum(1 for row in rows if row["used_at"])
    active = 0
    expired = 0
    for row in rows:
        if row["used_at"]:
            continue
        try:
            exp = datetime.fromisoformat(str(row["expires_at"]))
            if exp.tzinfo is None:
                exp = exp.replace(tzinfo=UTC)
        except ValueError:
            expired += 1
            continue
        if exp > now:
            active += 1
        else:
            expired += 1
    return {
        "total": total,
        "active": active,
        "used": used,
        "expired": expired,
    }