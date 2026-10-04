from __future__ import annotations

import hmac
from pathlib import Path

import httpx
from fastapi import APIRouter, Depends, Header, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from hub_app.api.dependencies import get_db
from hub_app.line.messaging import LineMessagingClient, NotificationService
from hub_app.models import LineUser, NotificationDelivery, PatientMapping
from hub_app.services.osm_vhv_bridge import bridge_stats, issue_osm_bridge_invite, validate_osm_bridge_pid

router = APIRouter(prefix="/api/v1/internal/vhv-failover", tags=["internal-vhv-failover"])
TOKEN_FILE = Path(r"D:\AppServ\private\osm-vhv-failover.token")
LINE_API = "https://api.line.me"


class ResolveBody(BaseModel):
    local_patient_refs: list[str] = Field(min_length=1, max_length=500)


class OnboardingIssueBody(BaseModel):
    pid: int = Field(ge=1)
    dry_run: bool = True
    ttl_seconds: int = Field(default=1800, ge=300, le=3600)


class PushBody(BaseModel):
    local_patient_ref: str = Field(pattern=r"^lp_[A-Za-z0-9_-]{24,80}$")
    messages: list[str] = Field(min_length=1, max_length=5)
    dedupe_key: str = Field(min_length=8, max_length=180)
    request_id: str = Field(min_length=8, max_length=64)
    dry_run: bool = False


def _assert_internal(request: Request, token: str) -> None:
    if not request.client or request.client.host not in {"127.0.0.1", "::1"}:
        raise HTTPException(403, "loopback only")
    try:
        expected = TOKEN_FILE.read_text(encoding="utf-8").strip()
    except Exception:
        raise HTTPException(503, "failover token unavailable") from None
    if len(expected) < 32 or not hmac.compare_digest(expected, str(token or "").strip()):
        raise HTTPException(403, "invalid failover token")


def _active_mapping(db: Session, local_ref: str):
    return db.execute(
        select(PatientMapping, LineUser)
        .join(LineUser, PatientMapping.line_user_id == LineUser.id)
        .where(
            PatientMapping.local_patient_key == local_ref,
            PatientMapping.mapping_status == "verified",
            LineUser.status == "active",
        )
        .order_by(PatientMapping.id.desc())
    ).first()


def _line_get(token: str, path: str, timeout: float) -> dict:
    if not token:
        raise HTTPException(503, "backup LINE OA is not configured")
    headers = {"Authorization": f"Bearer {token}"}
    try:
        response = httpx.get(f"{LINE_API}{path}", headers=headers, timeout=timeout)
    except httpx.HTTPError:
        raise HTTPException(503, "backup LINE OA is unreachable") from None
    if response.status_code >= 400:
        raise HTTPException(503, f"backup LINE OA returned HTTP {response.status_code}")
    try:
        payload = response.json()
    except ValueError:
        raise HTTPException(503, "backup LINE OA returned invalid JSON") from None
    return payload if isinstance(payload, dict) else {}


def _quota(settings) -> dict:
    info = _line_get(
        settings.line_channel_access_token,
        "/v2/bot/info",
        settings.line_request_timeout_seconds,
    )
    quota = _line_get(
        settings.line_channel_access_token,
        "/v2/bot/message/quota",
        settings.line_request_timeout_seconds,
    )
    usage = _line_get(
        settings.line_channel_access_token,
        "/v2/bot/message/quota/consumption",
        settings.line_request_timeout_seconds,
    )
    qtype = str(quota.get("type") or "")
    limit = int(quota.get("value") or 0) if qtype == "limited" else None
    used = max(0, int(usage.get("totalUsage") or 0))
    remaining = max(0, limit - used) if limit is not None else None
    pct = round((used / limit) * 100.0, 2) if limit and limit > 0 else 0.0
    return {
        "ready": bool(info.get("basicId")),
        "basic_id": str(info.get("basicId") or ""),
        "display_name": str(info.get("displayName") or "")[:120],
        "quota_type": qtype,
        "limit": limit,
        "used": used,
        "remaining": remaining,
        "usage_pct": pct,
    }


@router.get("/status")
def failover_status(
    request: Request,
    x_vhv_failover_token: str = Header(default=""),
):
    _assert_internal(request, x_vhv_failover_token)
    return _quota(request.app.state.settings)


@router.post("/resolve")
def failover_resolve(
    body: ResolveBody,
    request: Request,
    x_vhv_failover_token: str = Header(default=""),
    db: Session = Depends(get_db),
):
    _assert_internal(request, x_vhv_failover_token)
    refs = []
    seen = set()
    for ref in body.local_patient_refs:
        ref = str(ref or "").strip()
        if ref.startswith("lp_") and ref not in seen:
            refs.append(ref)
            seen.add(ref)
    if not refs:
        return {"ready_refs": [], "ready_count": 0}
    rows = db.execute(
        select(PatientMapping.local_patient_key)
        .join(LineUser, PatientMapping.line_user_id == LineUser.id)
        .where(
            PatientMapping.local_patient_key.in_(refs),
            PatientMapping.mapping_status == "verified",
            LineUser.status == "active",
        )
    ).all()
    ready = sorted({str(row[0]) for row in rows})
    return {"ready_refs": ready, "ready_count": len(ready)}


@router.get("/onboarding/status")
def onboarding_status(
    request: Request,
    x_vhv_failover_token: str = Header(default=""),
):
    _assert_internal(request, x_vhv_failover_token)
    return {
        "status": "ok",
        "backup_basic_id": "@601cnwrw",
        "bridge": bridge_stats(),
    }


@router.post("/onboarding/issue")
def onboarding_issue(
    body: OnboardingIssueBody,
    request: Request,
    x_vhv_failover_token: str = Header(default=""),
):
    _assert_internal(request, x_vhv_failover_token)
    gateway = request.app.state.appointment_gateway
    try:
        if body.dry_run:
            result = validate_osm_bridge_pid(gateway=gateway, pid=int(body.pid))
        else:
            result = issue_osm_bridge_invite(
                gateway=gateway,
                pid=int(body.pid),
                ttl_seconds=int(body.ttl_seconds),
            )
    except Exception:
        raise HTTPException(503, "cannot prepare OSM primary bridge invite") from None
    return result


@router.post("/push")
def failover_push(
    body: PushBody,
    request: Request,
    x_vhv_failover_token: str = Header(default=""),
    db: Session = Depends(get_db),
):
    _assert_internal(request, x_vhv_failover_token)
    mapped = _active_mapping(db, body.local_patient_ref)
    if mapped is None:
        raise HTTPException(404, "verified backup recipient not found")
    patient_mapping, line_user = mapped

    quota = _quota(request.app.state.settings)
    if not quota.get("ready"):
        raise HTTPException(503, "backup LINE OA is not ready")
    if quota.get("remaining") is not None and int(quota["remaining"]) < 1:
        raise HTTPException(429, "backup LINE quota exhausted")

    existing = db.scalar(
        select(NotificationDelivery).where(NotificationDelivery.dedupe_key == body.dedupe_key)
    )
    if body.dry_run:
        return {
            "status": "ready",
            "duplicate": bool(existing and existing.status == "sent"),
            "basic_id": quota.get("basic_id"),
        }

    messages = [{"type": "text", "text": str(text)[:5000]} for text in body.messages if str(text)]
    if not messages:
        raise HTTPException(422, "no message content")

    notifier = NotificationService(
        db,
        LineMessagingClient(
            request.app.state.settings.line_channel_access_token,
            timeout_seconds=request.app.state.settings.line_request_timeout_seconds,
        ),
    )
    try:
        delivery = notifier.push(
            to=line_user.line_user_id,
            messages=messages,
            request_id=body.request_id,
            line_user_id=line_user.id,
            dedupe_key=body.dedupe_key,
        )
    except Exception:
        raise HTTPException(502, "backup LINE push failed") from None

    return {
        "status": delivery.status,
        "delivery_id": int(delivery.id),
        "duplicate": bool(existing and existing.status == "sent"),
        "basic_id": quota.get("basic_id"),
    }