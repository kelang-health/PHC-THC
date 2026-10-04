from __future__ import annotations

import hashlib
import json
from datetime import UTC, datetime, timedelta
from typing import Any
from urllib.parse import urlsplit, urlunsplit, parse_qsl, urlencode

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from hub_app.core.config import Settings
from hub_app.line.messaging import LineMessagingClient, NotificationService
from hub_app.line.menu import build_identity_link_message, build_linked_account_message, build_main_menu_message, is_identity_link_request, is_main_menu_request
from hub_app.models import LineUser, PatientMapping, Service, WebhookEvent
from hub_app.services.identity_link import issue_identity_link
from hub_app.services.osm_vhv_bridge import claim_osm_bridge_invite, parse_bridge_command
from hub_app.modules.equipment_lookup import (
    EquipmentLookupClient,
    format_equipment_reply,
    normalize_equipment_code,
)


KNOWN_EVENT_TYPES = {
    "follow",
    "unfollow",
    "message",
    "postback",
    "join",
    "leave",
    "memberJoined",
    "memberLeft",
    "unsend",
    "videoPlayComplete",
}


def utcnow() -> datetime:
    return datetime.now(UTC)


def _aware(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    return value if value.tzinfo is not None else value.replace(tzinfo=UTC)


def event_hash(event: dict[str, Any]) -> str:
    webhook_event_id = str(event.get("webhookEventId") or "").strip()
    if webhook_event_id:
        material = f"line:webhookEventId:{webhook_event_id}".encode("utf-8")
    else:
        canonical = json.dumps(event, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        material = f"line:event:{canonical}".encode("utf-8")
    return hashlib.sha256(material).hexdigest()


def claim_event(
    db: Session,
    event: dict[str, Any],
    *,
    reclaim_after_seconds: int = 30,
) -> tuple[WebhookEvent | None, bool]:
    """Persistently claim an event and allow failed/stale claims to be retried.

    The raw webhook payload is intentionally not stored. If a process stops after a claim,
    LINE retry supplies the payload again; a stale queued/processing claim can then be reclaimed.
    """
    digest = event_hash(event)
    now = utcnow()
    existing = db.get(WebhookEvent, digest)
    if existing is not None:
        received_at = _aware(existing.received_at)
        stale = bool(
            existing.status in {"queued", "processing"}
            and received_at is not None
            and received_at <= now - timedelta(seconds=reclaim_after_seconds)
        )
        if existing.status == "failed" or stale:
            existing.status = "queued"
            existing.received_at = now
            existing.processed_at = None
            db.commit()
            return existing, True
        return existing, False

    row = WebhookEvent(
        event_hash=digest,
        event_type=str(event.get("type") or "unknown")[:50],
        status="queued",
        received_at=now,
    )
    db.add(row)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        return db.get(WebhookEvent, digest), False
    return row, True


def _source_user_id(event: dict[str, Any]) -> str:
    source = event.get("source")
    if not isinstance(source, dict):
        return ""
    return str(source.get("userId") or "").strip()


def _upsert_line_user(db: Session, event: dict[str, Any]) -> LineUser | None:
    line_user_id = _source_user_id(event)
    if not line_user_id:
        return None

    user = db.scalar(select(LineUser).where(LineUser.line_user_id == line_user_id))
    event_type = str(event.get("type") or "")
    now = utcnow()
    if user is None:
        user = LineUser(
            line_user_id=line_user_id,
            display_name="",
            picture_url="",
            status="unfollowed" if event_type == "unfollow" else "active",
            last_seen_at=now,
        )
        db.add(user)
        db.flush()
    else:
        if event_type == "unfollow":
            user.status = "unfollowed"
        elif event_type in {"follow", "message", "postback"}:
            user.status = "active"
        user.last_seen_at = now
    return user


def _has_single_verified_mapping(db: Session, line_user_db_id: int) -> bool:
    rows = list(
        db.scalars(
            select(PatientMapping.id).where(
                PatientMapping.line_user_id == line_user_db_id,
                PatientMapping.mapping_status == "verified",
            )
        ).all()
    )
    return len(rows) == 1


def _reply_equipment_lookup(
    db: Session,
    *,
    event: dict[str, Any],
    user: LineUser | None,
    digest: str,
    settings: Settings,
    equipment_transport=None,
    line_transport=None,
    deferred: bool = False,
) -> bool:
    if not settings.equipment_lookup_enabled or str(event.get("type") or "") != "message":
        return False
    message = event.get("message")
    if not isinstance(message, dict) or str(message.get("type") or "") != "text":
        return False
    code = normalize_equipment_code(str(message.get("text") or ""))
    if not code:
        return False
    reply_token = str(event.get("replyToken") or "").strip()
    if deferred:
        if user is None or not user.line_user_id:
            return False
    elif not reply_token:
        return False

    profile = EquipmentLookupClient(
        settings.equipment_lookup_api_url,
        timeout_seconds=settings.equipment_lookup_timeout_seconds,
        transport=equipment_transport,
    ).lookup(code)
    text = format_equipment_reply(code, profile)

    service = db.scalar(select(Service).where(Service.service_code == "EQUIPMENT"))
    line_client = LineMessagingClient(
        settings.line_channel_access_token,
        timeout_seconds=settings.line_request_timeout_seconds,
        transport=line_transport,
    )
    notifier = NotificationService(db, line_client)
    if deferred:
        notifier.push(
            to=user.line_user_id,
            messages=[{"type": "text", "text": text}],
            request_id=digest,
            line_user_id=user.id,
            service_id=service.id if service is not None else None,
            dedupe_key=f"equipment:deferred:{digest}",
        )
    else:
        notifier.reply(
            reply_token=reply_token,
            messages=[{"type": "text", "text": text}],
            request_id=digest,
            line_user_id=user.id if user is not None else None,
            service_id=service.id if service is not None else None,
            dedupe_key=f"equipment:{digest}",
        )
    return True


def _reply_main_menu(
    db: Session,
    *,
    event: dict[str, Any],
    user: LineUser | None,
    digest: str,
    settings: Settings,
    line_transport=None,
    deferred: bool = False,
) -> bool:
    if not settings.line_main_menu_enabled:
        return False

    event_type = str(event.get("type") or "")
    if event_type not in {"follow", "message"}:
        return False
    if event_type == "message":
        message = event.get("message")
        if (not isinstance(message, dict) or str(message.get("type") or "") != "text"
                or not is_main_menu_request(str(message.get("text") or ""))):
            return False

    reply_token = str(event.get("replyToken") or "").strip()
    if deferred:
        if user is None or not user.line_user_id:
            return False
    elif not reply_token:
        return False

    line_client = LineMessagingClient(
        settings.line_channel_access_token,
        timeout_seconds=settings.line_request_timeout_seconds,
        transport=line_transport,
    )
    message_payload = build_main_menu_message(
        portal_url=settings.line_portal_url,
        equipment_url=settings.line_equipment_url,
    )
    notifier = NotificationService(db, line_client)
    if deferred:
        notifier.push(
            to=user.line_user_id,
            messages=[message_payload],
            request_id=digest,
            line_user_id=user.id,
            dedupe_key=f"main-menu:deferred:{digest}",
        )
    else:
        notifier.reply(
            reply_token=reply_token,
            messages=[message_payload],
            request_id=digest,
            line_user_id=user.id if user is not None else None,
            dedupe_key=f"main-menu:{digest}",
        )
    return True


def _reply_osm_bridge_claim(
    db: Session,
    *,
    event: dict[str, Any],
    user: LineUser | None,
    digest: str,
    settings: Settings,
    line_transport=None,
    deferred: bool = False,
) -> bool:
    if user is None:
        return False
    if str(event.get("type") or "") != "message":
        return False
    message = event.get("message")
    if not isinstance(message, dict) or str(message.get("type") or "") != "text":
        return False
    token = parse_bridge_command(str(message.get("text") or ""))
    if not token:
        return False

    result = claim_osm_bridge_invite(
        db,
        line_user_db_id=int(user.id),
        raw_token=token,
    )
    status = str(result.get("status") or "")
    if status in {"linked", "already_ready"}:
        reply_text = (
            "เชื่อม LINE OA สำรองกับบัญชี อสม. เดิมสำเร็จแล้ว\n"
            "ระบบพร้อมใช้ OA สำรองสำหรับการแจ้งเตือนนัดหมายเมื่อจำเป็น"
        )
    elif status == "conflict_user_mapped":
        reply_text = (
            "บัญชี LINE นี้เชื่อมกับบุคคลอื่นอยู่แล้ว "
            "กรุณาติดต่อเจ้าหน้าที่ก่อนเปลี่ยนการเชื่อมต่อ"
        )
    elif status == "conflict_ref_in_use":
        reply_text = (
            "บัญชี อสม. นี้มีการเชื่อม LINE สำรองอยู่แล้ว "
            "กรุณาติดต่อเจ้าหน้าที่หากต้องการเปลี่ยนบัญชี"
        )
    else:
        reply_text = (
            "ลิงก์เชื่อมต่อหมดอายุหรือถูกใช้แล้ว "
            "กรุณาขอลิงก์ใหม่จาก LINE OA พระบาท พลัส"
        )

    reply_token = str(event.get("replyToken") or "").strip()
    if deferred:
        if not user.line_user_id:
            return False
    elif not reply_token:
        return False

    client = LineMessagingClient(
        settings.line_channel_access_token,
        timeout_seconds=settings.line_request_timeout_seconds,
        transport=line_transport,
    )
    notifier = NotificationService(db, client)
    payload = [{"type": "text", "text": reply_text}]
    if deferred:
        notifier.push(
            to=user.line_user_id,
            messages=payload,
            request_id=digest,
            line_user_id=user.id,
            dedupe_key=f"osm-bridge:deferred:{digest}",
        )
    else:
        notifier.reply(
            reply_token=reply_token,
            messages=payload,
            request_id=digest,
            line_user_id=user.id,
            dedupe_key=f"osm-bridge:{digest}",
        )
    return True


def _reply_identity_link(
    db: Session,
    *,
    event: dict[str, Any],
    user: LineUser | None,
    digest: str,
    settings: Settings,
    line_transport=None,
    deferred: bool = False,
) -> bool:
    if not settings.line_main_menu_enabled or user is None:
        return False

    event_type = str(event.get("type") or "")
    text_command = ""
    postback_data = ""
    requested = False
    if event_type == "message":
        message = event.get("message")
        if isinstance(message, dict) and str(message.get("type") or "") == "text":
            text_command = str(message.get("text") or "").strip()
            requested = is_identity_link_request(text_command)
    elif event_type == "postback":
        postback = event.get("postback")
        if isinstance(postback, dict):
            postback_data = str(postback.get("data") or "").strip()
            requested = postback_data in {"action=identity_link", "action=appointment"}

    if not requested:
        return False
    reply_token = str(event.get("replyToken") or "").strip()
    if deferred:
        if not user.line_user_id:
            return False
    elif not reply_token:
        return False

    intent = ""
    if text_command in {"นัดหมาย", "ดูนัดหมาย"} or postback_data == "action=appointment":
        intent = "appointment"
    elif text_command in {"ยืมอุปกรณ์", "คืนอุปกรณ์", "ติดต่อ"}:
        intent = {
            "ยืมอุปกรณ์": "equipment",
            "คืนอุปกรณ์": "equipment_return",
            "ติดต่อ": "contact",
        }[text_command]

    portal_url = settings.line_portal_url
    if intent:
        parts = urlsplit(portal_url)
        query = dict(parse_qsl(parts.query))
        query["service"] = intent
        portal_url = urlunsplit((parts.scheme, parts.netloc, parts.path, urlencode(query), ""))
    url = issue_identity_link(
        db,
        line_user_id=user.id,
        portal_url=portal_url,
        ttl_seconds=settings.identity_link_ttl_seconds,
    )

    linked = _has_single_verified_mapping(db, user.id)
    if linked and intent in {"", "appointment"}:
        message = build_linked_account_message(url, appointment=intent == "appointment")
    else:
        message = build_identity_link_message(url, intent=intent)

    line_client = LineMessagingClient(
        settings.line_channel_access_token,
        timeout_seconds=settings.line_request_timeout_seconds,
        transport=line_transport,
    )
    notifier = NotificationService(db, line_client)
    if deferred:
        notifier.push(
            to=user.line_user_id,
            messages=[message],
            request_id=digest,
            line_user_id=user.id,
            dedupe_key=f"identity-link:deferred:{digest}",
        )
    else:
        notifier.reply(
            reply_token=reply_token,
            messages=[message],
            request_id=digest,
            line_user_id=user.id,
            dedupe_key=f"identity-link:{digest}",
        )
    return True



def process_event(
    database,
    digest: str,
    event: dict[str, Any],
    *,
    settings: Settings | None = None,
    equipment_transport=None,
    line_transport=None,
    deferred: bool = False,
) -> None:
    """Process a claimed event without retaining raw webhook/message content."""
    with database.SessionLocal() as db:
        row = db.get(WebhookEvent, digest)
        if row is None or row.status not in {"queued", "processing"}:
            return
        row.status = "processing"
        db.commit()

        try:
            user = _upsert_line_user(db, event)
            if user is not None:
                db.flush()
                row.line_user_id = user.id
            if settings is not None:
                replied = _reply_osm_bridge_claim(
                    db,
                    event=event,
                    user=user,
                    digest=digest,
                    settings=settings,
                    line_transport=line_transport,
                    deferred=deferred,
                )
                if not replied:
                    replied = _reply_identity_link(
                        db,
                        event=event,
                        user=user,
                        digest=digest,
                        settings=settings,
                        line_transport=line_transport,
                        deferred=deferred,
                    )
                if not replied:
                    replied = _reply_equipment_lookup(
                        db,
                        event=event,
                        user=user,
                        digest=digest,
                        settings=settings,
                        equipment_transport=equipment_transport,
                        line_transport=line_transport,
                        deferred=deferred,
                    )
                if not replied:
                    _reply_main_menu(
                        db,
                        event=event,
                        user=user,
                        digest=digest,
                        settings=settings,
                        line_transport=line_transport,
                        deferred=deferred,
                    )
            event_type = str(event.get("type") or "")
            row.status = "processed" if event_type in KNOWN_EVENT_TYPES else "ignored"
            row.processed_at = utcnow()
            db.commit()
        except Exception:
            db.rollback()
            failed = db.get(WebhookEvent, digest)
            if failed is not None:
                failed.status = "failed"
                failed.processed_at = utcnow()
                db.commit()
            raise