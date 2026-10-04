from __future__ import annotations

import hashlib
import re
from collections import defaultdict
from threading import Lock
from uuid import UUID, uuid4

from fastapi import Depends, HTTPException
from pydantic import BaseModel, Field

from .appointment_notice_preview import build_preview, _link_index, _load_config
from .boundary_quality import normalize_community
from .database import AppointmentNoticeDelivery, Audit, CloudLineLink, User, Volunteer, cipher, now
from .line_oa import LineAPIError, _line_api, _setting as _line_setting
from .line_oa_failover import backup_push, route_groups

CASE_RE = re.compile(r"^[0-9a-f]{24}$")
SEND_LOCK = Lock()


class AppointmentNoticeSendBody(BaseModel):
    from_date: str = Field(min_length=10, max_length=10)
    to_date: str = Field(min_length=10, max_length=10)
    case_ids: list[str] = Field(min_length=1, max_length=200)
    channel: str = Field(pattern=r"^(vhv|community)$")
    community: str = Field(default="", max_length=191)
    filter_community: str = Field(default="", max_length=191)
    filter_volunteer_id: int = Field(default=0, ge=0)
    recipient_target: str = Field(default="both", pattern=r"^(chair|staff|both)$")
    policy: str = Field(default="new_only", pattern=r"^(new_only|resend_all)$")
    preview_token: str = Field(pattern=r"^[0-9a-f]{64}$")
    send_nonce: str = Field(min_length=36, max_length=36)
    validate_only: bool = False


def _valid_uuid(value: str) -> str:
    try:
        return str(UUID(str(value)))
    except Exception as exc:
        raise HTTPException(422, "send nonce ไม่ถูกต้อง") from exc


def _thai_date(value: str) -> str:
    try:
        year, month, day = [int(x) for x in str(value).split("-")]
        return f"{day}/{month}/{year + 543}"
    except Exception:
        return str(value or "")


def _case_line(row: dict, *, include_owner: bool) -> str:
    when = _thai_date(row.get("appointment_date") or "")
    time_text = str(row.get("appointment_time") or "").strip() or "ไม่ระบุเวลา"
    line = (
        f"• {when} {time_text} · {row.get('patient_name') or 'ไม่ระบุชื่อ'}"
        f" · บ้าน {row.get('house_no') or '—'} · {row.get('service_label') or 'นัดหมาย'}"
    )
    if include_owner:
        line += f" · อสม. {row.get('volunteer_name') or 'ยังไม่มีผู้รับผิดชอบ'}"
    return line


def _chunk_messages(title: str, lines: list[str], footer: str) -> list[str]:
    limit = 4200
    chunks: list[str] = []
    current = title.strip()
    for line in lines:
        candidate = current + "\n" + line if current else line
        if len(candidate) > limit and current:
            chunks.append(current)
            current = "(ต่อ)\n" + line
        else:
            current = candidate
    if footer:
        candidate = current + "\n\n" + footer
        if len(candidate) > limit and current:
            chunks.append(current)
            current = footer
        else:
            current = candidate
    if current:
        chunks.append(current)
    if not chunks:
        raise HTTPException(422, "ไม่มีข้อความสำหรับส่ง")
    if len(chunks) > 5:
        raise HTTPException(422, "รายการมากเกินไปสำหรับ LINE 1 ครั้ง กรุณาแบ่งช่วงหรือแบ่งเคส")
    return chunks


def _vhv_messages(name: str, rows: list[dict]) -> list[str]:
    title = (
        "📅 แจ้งเตือนนัดหมายในพื้นที่รับผิดชอบ\n"
        f"อสม. {name}\n"
        f"มีนัดที่เลือก {len(rows)} รายการ"
    )
    lines = [_case_line(row, include_owner=False) for row in rows]
    footer = (
        "กรุณาช่วยย้ำเตือนประชาชนในบ้านที่รับผิดชอบ\n"
        "ศูนย์บริการสาธารณสุขบ้านโทกหัวช้าง"
    )
    return _chunk_messages(title, lines, footer)


def _community_messages(community: str, rows: list[dict]) -> list[str]:
    people = len({row.get("person_key") for row in rows if row.get("person_key")})
    houses = len({row.get("hcode") for row in rows if row.get("hcode")})
    dates = sorted({row.get("appointment_date") for row in rows if row.get("appointment_date")})
    date_label = _thai_date(dates[0]) if len(dates) == 1 else (
        f"{_thai_date(dates[0])}–{_thai_date(dates[-1])}" if dates else "—"
    )
    title = (
        f"📅 สรุปนัดหมาย{community}\n"
        f"ช่วง {date_label}\n"
        f"{people} คน · {houses} บ้าน · {len(rows)} นัด"
    )
    lines = [_case_line(row, include_owner=True) for row in rows]
    footer = (
        "กรุณาช่วยย้ำเตือนประชาชนในพื้นที่\n"
        "ศูนย์บริการสาธารณสุขบ้านโทกหัวช้าง"
    )
    return _chunk_messages(title, lines, footer)


def _oa_status(db) -> dict:
    row = _line_setting(db)
    configured = bool(
        str(row.channel_access_token_encrypted or "").strip()
        and str(row.channel_secret_encrypted or "").strip()
    )
    enabled = bool(row.enabled)
    expected_basic_id = str(row.basic_id or "").strip()
    if not configured or not enabled:
        return {
            "ready": False,
            "configured": configured,
            "enabled": enabled,
            "basic_id": expected_basic_id,
            "display_name": "",
        }
    try:
        info = _line_api(row, "GET", "/v2/bot/info")
    except Exception:
        return {
            "ready": False,
            "configured": configured,
            "enabled": enabled,
            "basic_id": expected_basic_id,
            "display_name": "",
        }
    actual_basic_id = str(info.get("basicId") or "").strip()
    return {
        "ready": bool(actual_basic_id and (not expected_basic_id or actual_basic_id == expected_basic_id)),
        "configured": configured,
        "enabled": enabled,
        "basic_id": actual_basic_id or expected_basic_id,
        "display_name": str(info.get("displayName") or "")[:120],
    }


def _line_identity(link: CloudLineLink | None) -> tuple[str, str]:
    if link is None:
        return "", ""
    encrypted = str(link.line_user_encrypted or "").strip()
    if not encrypted:
        return "", ""
    try:
        raw = cipher().decrypt(encrypted.encode("utf-8")).decode("utf-8").strip()
    except Exception:
        return "", ""
    if not raw.startswith("U") or len(raw) < 20:
        return "", ""
    return raw, hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _selected_rows(preview: dict, case_ids: list[str]) -> list[dict]:
    requested = []
    seen = set()
    for case_id in case_ids:
        case_id = str(case_id or "").strip().casefold()
        if not CASE_RE.fullmatch(case_id):
            raise HTTPException(422, "รหัสเคสนัดหมายไม่ถูกต้อง")
        if case_id not in seen:
            requested.append(case_id)
            seen.add(case_id)
    index = {str(row.get("case_id")): row for row in preview.get("rows") or []}
    missing = [case_id for case_id in requested if case_id not in index]
    if missing:
        raise HTTPException(409, "ข้อมูลนัดหมายเปลี่ยนไป กรุณาโหลด Preview ใหม่")
    return [index[case_id] for case_id in requested]


def _community_recipients(db, preview: dict, community: str, target: str) -> tuple[list[dict], list[str]]:
    summary = next(
        (
            item for item in preview.get("communities") or []
            if normalize_community(item.get("community")) == normalize_community(community)
        ),
        None,
    )
    if summary is None:
        raise HTTPException(409, "ไม่พบชุมชนใน Preview ปัจจุบัน")

    candidates: list[dict] = []
    missing: list[str] = []
    if target in {"chair", "both"}:
        chair = summary.get("chair")
        if chair:
            candidates.append({**chair, "target_kind": "chair"})
        else:
            missing.append("ยังไม่ได้กำหนดประธาน อสม.")
    if target in {"staff", "both"}:
        staff = list(summary.get("staff") or [])
        if staff:
            candidates.extend({**item, "target_kind": "staff"} for item in staff)
        else:
            missing.append("ไม่พบ Staff ของชุมชน")

    line_index = _link_index(db)
    merged: dict[int, dict] = {}
    for item in candidates:
        volunteer_id = int(item.get("volunteer_id") or 0)
        if volunteer_id < 1:
            continue
        link = line_index.get(volunteer_id)
        line_user_id, line_hash = _line_identity(link)
        if link is None or not line_user_id or not line_hash:
            missing.append(f"{item.get('name') or 'ผู้รับ'} ยังไม่เชื่อม LINE")
            continue
        existing = merged.get(volunteer_id)
        if existing:
            roles = set(str(existing["target_kind"]).split("+"))
            roles.add(str(item.get("target_kind") or "staff"))
            existing["target_kind"] = "+".join(sorted(roles))
            continue
        merged[volunteer_id] = {
            "volunteer_id": volunteer_id,
            "name": str(item.get("name") or ""),
            "target_kind": str(item.get("target_kind") or "staff"),
            "line_user_id": line_user_id,
            "line_user_hash": line_hash,
        }
    return list(merged.values()), missing


def _vhv_groups(db, rows: list[dict]) -> tuple[list[dict], list[str]]:
    line_index = _link_index(db)
    grouped: dict[int, list[dict]] = defaultdict(list)
    missing: list[str] = []
    for row in rows:
        volunteer_id = int(row.get("volunteer_id") or 0)
        if volunteer_id < 1:
            missing.append(f"บ้าน {row.get('house_no') or '—'} ยังไม่มี อสม.รับผิดชอบ")
            continue
        link = line_index.get(volunteer_id)
        line_user_id, line_hash = _line_identity(link)
        if link is None or not line_user_id or not line_hash:
            missing.append(f"{row.get('volunteer_name') or 'อสม.'} ยังไม่เชื่อม LINE")
            continue
        grouped[volunteer_id].append(row)
    output = []
    for volunteer_id, items in grouped.items():
        link = line_index[volunteer_id]
        output.append({
            "volunteer_id": volunteer_id,
            "name": str(items[0].get("volunteer_name") or ""),
            "target_kind": "vhv",
            "line_user_id": _line_identity(link)[0],
            "line_user_hash": _line_identity(link)[1],
            "rows": items,
        })
    return output, missing


def _sent_case_ids(db, channel: str, recipient_volunteer_id: int, case_ids: list[str]) -> set[str]:
    if not case_ids:
        return set()
    rows = db.query(AppointmentNoticeDelivery).filter(
        AppointmentNoticeDelivery.channel == channel,
        AppointmentNoticeDelivery.recipient_volunteer_id == int(recipient_volunteer_id),
        AppointmentNoticeDelivery.status == "sent",
        AppointmentNoticeDelivery.case_id.in_(case_ids),
    ).all()
    return {str(item.case_id) for item in rows}


def _dedupe_and_retry(db, *, channel: str, recipient_id: int, case_ids: list[str],
                      resend: bool, send_nonce: str) -> tuple[str, str]:
    del send_nonce  # Batch id is audited separately; retry identity must survive a browser retry.
    identity = f"{channel}|{recipient_id}|{','.join(sorted(case_ids))}"
    digest = hashlib.sha256(identity.encode("utf-8")).hexdigest()

    if not resend:
        dedupe = f"apptnotice:{channel}:n:{digest[:44]}"
        existing = db.query(AppointmentNoticeDelivery).filter(
            AppointmentNoticeDelivery.dedupe_key == dedupe
        ).order_by(AppointmentNoticeDelivery.id.desc()).first()
        retry_key = str(existing.retry_key) if existing and existing.retry_key else str(uuid4())
        return dedupe, retry_key

    prefix = f"apptnotice:{channel}:r:{digest[:32]}:"
    prior = db.query(AppointmentNoticeDelivery).filter(
        AppointmentNoticeDelivery.dedupe_key.like(prefix + "%")
    ).order_by(AppointmentNoticeDelivery.id).all()
    by_key: dict[str, list] = defaultdict(list)
    for item in prior:
        by_key[str(item.dedupe_key)].append(item)

    if by_key:
        latest_key = list(by_key.keys())[-1]
        latest_rows = by_key[latest_key]
        if any(str(item.status) != "sent" for item in latest_rows):
            retry_key = str(latest_rows[-1].retry_key or uuid4())
            return latest_key, retry_key

    sent_rounds = sum(
        1 for rows in by_key.values()
        if rows and all(str(item.status) == "sent" for item in rows)
    )
    dedupe = prefix + f"{sent_rounds + 1:04d}"
    return dedupe, str(uuid4())


def _prepare(db, body: AppointmentNoticeSendBody) -> dict:
    send_nonce = _valid_uuid(body.send_nonce)
    preview = build_preview(
        db,
        from_date=body.from_date,
        to_date=body.to_date,
        community=(body.community if body.channel == "community" else body.filter_community),
        volunteer_id=(0 if body.channel == "community" else body.filter_volunteer_id),
    )
    if preview.get("preview_token") != body.preview_token:
        raise HTTPException(409, "Preview เปลี่ยนไปแล้ว กรุณาโหลดใหม่ก่อนส่ง")

    selected = _selected_rows(preview, body.case_ids)
    if body.channel == "community":
        if not body.community:
            raise HTTPException(422, "กรุณาระบุชุมชนสำหรับการส่งสรุป")
        wrong = [
            row for row in selected
            if normalize_community(row.get("community")) != normalize_community(body.community)
        ]
        if wrong:
            raise HTTPException(409, "มีเคสที่ไม่อยู่ในชุมชนที่เลือก กรุณาโหลดใหม่")
        recipients, missing = _community_recipients(
            db, preview, body.community, body.recipient_target
        )
        groups = [{
            **recipient,
            "rows": selected,
        } for recipient in recipients]
    else:
        groups, missing = _vhv_groups(db, selected)

    if not groups:
        raise HTTPException(409, "ไม่มีผู้รับที่เชื่อม LINE และพร้อมส่ง")

    prepared = []
    duplicate_deliveries = 0
    eligible_deliveries = 0
    for group in groups:
        all_rows = list(group["rows"])
        all_case_ids = [str(row["case_id"]) for row in all_rows]
        sent_ids = _sent_case_ids(
            db, body.channel, int(group["volunteer_id"]), all_case_ids
        )
        duplicate_deliveries += len(sent_ids)
        if body.policy == "new_only":
            send_rows = [row for row in all_rows if str(row["case_id"]) not in sent_ids]
        else:
            send_rows = all_rows
        if not send_rows:
            prepared.append({
                **group,
                "send_rows": [],
                "duplicate_case_ids": sorted(sent_ids),
                "dedupe_key": "",
                "retry_key": "",
                "request_ref": "",
                "messages": [],
            })
            continue

        send_case_ids = [str(row["case_id"]) for row in send_rows]
        eligible_deliveries += len(send_case_ids)
        dedupe, retry_key = _dedupe_and_retry(
            db,
            channel=body.channel,
            recipient_id=int(group["volunteer_id"]),
            case_ids=send_case_ids,
            resend=(body.policy == "resend_all"),
            send_nonce=send_nonce,
        )
        request_ref = f"{send_nonce[:8]}-{int(group['volunteer_id'])}-{body.channel}"
        messages = (
            _vhv_messages(group["name"], send_rows)
            if body.channel == "vhv"
            else _community_messages(body.community, send_rows)
        )
        prepared.append({
            **group,
            "send_rows": send_rows,
            "duplicate_case_ids": sorted(sent_ids),
            "dedupe_key": dedupe,
            "retry_key": retry_key,
            "request_ref": request_ref[:64],
            "messages": messages,
        })

    return {
        "send_nonce": send_nonce,
        "preview": preview,
        "selected": selected,
        "groups": prepared,
        "missing": sorted(set(missing)),
        "duplicate_deliveries": duplicate_deliveries,
        "eligible_deliveries": eligible_deliveries,
    }
def validate_send(db, body: AppointmentNoticeSendBody) -> dict:
    prepared = _prepare(db, body)
    active_groups = [group for group in prepared["groups"] if group.get("send_rows")]
    routing = route_groups(db, active_groups) if active_groups else {
        "state": "nothing_to_send",
        "primary": _oa_status(db),
        "backup": {"ready": False, "basic_id": ""},
        "decisions": [],
        "primary_groups": 0,
        "backup_groups": 0,
        "blocked_groups": 0,
        "backup_ready_groups": 0,
    }
    decision_map = {
        int(item.get("volunteer_id") or 0): item
        for item in routing.get("decisions") or []
    }
    recipient_rows = []
    not_ready = 0
    for group in prepared["groups"]:
        decision = decision_map.get(int(group.get("volunteer_id") or 0), {})
        provider = str(decision.get("provider") or "")
        if not group.get("send_rows"):
            status = "duplicate_only"
        elif provider in {"primary", "backup"}:
            status = "ready"
        else:
            status = "recipient_not_ready"
            not_ready += 1
        recipient_rows.append({
            "name": group.get("name") or "",
            "target_kind": group.get("target_kind") or "",
            "case_count": len(group.get("send_rows") or []),
            "duplicate_case_count": len(group.get("duplicate_case_ids") or []),
            "status": status,
            "provider": provider or "none",
            "backup_ready": bool(decision.get("backup_ready")),
            "route_reason": str(decision.get("reason") or ""),
        })
    primary = routing.get("primary") or {}
    backup = routing.get("backup") or {}
    return {
        "status": "validated",
        "channel": body.channel,
        "policy": body.policy,
        "selected_cases": len(prepared["selected"]),
        "eligible_deliveries": prepared["eligible_deliveries"],
        "duplicate_deliveries": prepared["duplicate_deliveries"],
        "requires_resend_confirmation": prepared["duplicate_deliveries"] > 0,
        "missing": prepared["missing"],
        "unmatched_recipients": not_ready,
        "recipients": recipient_rows,
        "oa_ready": bool(primary.get("ready") or backup.get("ready")),
        "oa_configured": bool(primary.get("ready")),
        "oa_enabled": True,
        "oa_basic_id": str(primary.get("basic_id") or ""),
        "oa_display_name": str(primary.get("display_name") or ""),
        "failover_state": str(routing.get("state") or ""),
        "primary_quota": primary,
        "backup_quota": backup,
        "primary_groups": int(routing.get("primary_groups") or 0),
        "backup_groups": int(routing.get("backup_groups") or 0),
        "blocked_groups": int(routing.get("blocked_groups") or 0),
        "backup_ready_groups": int(routing.get("backup_ready_groups") or 0),
    }


def _ensure_ledger_rows(db, group: dict, body: AppointmentNoticeSendBody, actor: str) -> list:
    existing = db.query(AppointmentNoticeDelivery).filter(
        AppointmentNoticeDelivery.dedupe_key == group["dedupe_key"]
    ).all()
    existing_by_case = {str(item.case_id): item for item in existing}
    output = []
    sent_before = set(group.get("duplicate_case_ids") or [])
    for row in group.get("send_rows") or []:
        case_id = str(row["case_id"])
        item = existing_by_case.get(case_id)
        if item is None:
            item = AppointmentNoticeDelivery(
                batch_id=body.send_nonce,
                case_id=case_id,
                channel=body.channel,
                target_kind=str(group.get("target_kind") or ""),
                recipient_volunteer_id=int(group["volunteer_id"]),
                recipient_line_hash=str(group["line_user_hash"]),
                community=str(row.get("community") or body.community or ""),
                status="pending",
                is_resend=(body.policy == "resend_all" or case_id in sent_before),
                dedupe_key=str(group["dedupe_key"]),
                retry_key=str(group["retry_key"]),
                provider_slot=str(group.get("provider_slot") or "primary"),
                oa_basic_id=str(group.get("oa_basic_id") or ""),
                created_by=str(actor or ""),
                created_at=now(),
            )
            db.add(item)
        else:
            item.status = "pending"
            item.error_code = ""
            item.batch_id = body.send_nonce
            item.provider_slot = str(group.get("provider_slot") or item.provider_slot or "primary")
            item.oa_basic_id = str(group.get("oa_basic_id") or item.oa_basic_id or "")
        output.append(item)
    db.flush()
    return output


def execute_send(db, body: AppointmentNoticeSendBody, *, actor: str) -> dict:
    prepared = _prepare(db, body)
    active_groups = [group for group in prepared["groups"] if group.get("send_rows")]
    if not active_groups:
        return {
            "status": "nothing_to_send",
            "selected_cases": len(prepared["selected"]),
            "sent_groups": 0,
            "failed_groups": 0,
            "duplicate_deliveries": prepared["duplicate_deliveries"],
            "missing": prepared["missing"],
            "recipients": [],
            "primary_sent_groups": 0,
            "backup_sent_groups": 0,
            "blocked_groups": 0,
        }

    routing = route_groups(db, active_groups)
    decision_map = {
        int(item.get("volunteer_id") or 0): item
        for item in routing.get("decisions") or []
    }
    primary = routing.get("primary") or {}
    backup = routing.get("backup") or {}

    for group in active_groups:
        decision = decision_map.get(int(group.get("volunteer_id") or 0), {})
        provider = str(decision.get("provider") or "none")
        group["provider_slot"] = provider
        group["route_reason"] = str(decision.get("reason") or "")
        group["backup_ref"] = str(decision.get("backup_ref") or "")
        group["backup_ready"] = bool(decision.get("backup_ready"))
        group["oa_basic_id"] = (
            str(backup.get("basic_id") or "")
            if provider == "backup"
            else str(primary.get("basic_id") or "")
        )

    ledger_by_dedupe = {}
    for group in active_groups:
        ledger_by_dedupe[group["dedupe_key"]] = _ensure_ledger_rows(
            db, group, body, actor
        )
    db.commit()

    setting = _line_setting(db)
    sent_groups = 0
    failed_groups = 0
    primary_sent_groups = 0
    backup_sent_groups = 0
    fallback_groups = 0
    recipient_results = []

    for group in active_groups:
        ledger_rows = ledger_by_dedupe.get(group["dedupe_key"], [])
        status = "failed"
        duplicate = False
        error_code = ""
        hub_delivery_ref = ""
        provider = str(group.get("provider_slot") or "none")
        oa_basic_id = str(group.get("oa_basic_id") or "")
        fallback_used = False

        if provider == "primary":
            try:
                result = _line_api(
                    setting,
                    "POST",
                    "/v2/bot/message/push",
                    body={
                        "to": str(group["line_user_id"]),
                        "messages": [
                            {"type": "text", "text": text}
                            for text in group["messages"]
                        ],
                    },
                    retry_key=str(group["retry_key"]),
                )
                status = "sent"
                duplicate = bool((result or {}).get("duplicate"))
            except LineAPIError as exc:
                primary_error = int(exc.status or 0)
                error_code = f"line_http_{primary_error}" if primary_error else "line_unavailable"
                # Fail over only on an explicit quota/rate response. Ambiguous
                # network failures stay on Primary to avoid cross-OA duplicates.
                if (
                    primary_error == 429
                    and group.get("backup_ref")
                    and backup.get("ready")
                ):
                    try:
                        bres = backup_push(
                            local_patient_ref=str(group["backup_ref"]),
                            messages=list(group["messages"]),
                            dedupe_key=str(group["dedupe_key"]),
                            request_id=str(group["request_ref"]),
                            dry_run=False,
                        )
                        if str(bres.get("status") or "") == "sent":
                            status = "sent"
                            duplicate = bool(bres.get("duplicate"))
                            provider = "backup"
                            oa_basic_id = str(bres.get("basic_id") or backup.get("basic_id") or "")
                            hub_delivery_ref = str(bres.get("delivery_id") or "")[:64]
                            fallback_used = True
                            error_code = ""
                    except HTTPException as bexc:
                        error_code = f"backup_http_{int(bexc.status_code)}"
            except Exception:
                error_code = "line_send_failed"

        elif provider == "backup":
            try:
                bres = backup_push(
                    local_patient_ref=str(group.get("backup_ref") or ""),
                    messages=list(group["messages"]),
                    dedupe_key=str(group["dedupe_key"]),
                    request_id=str(group["request_ref"]),
                    dry_run=False,
                )
                if str(bres.get("status") or "") == "sent":
                    status = "sent"
                    duplicate = bool(bres.get("duplicate"))
                    oa_basic_id = str(bres.get("basic_id") or backup.get("basic_id") or "")
                    hub_delivery_ref = str(bres.get("delivery_id") or "")[:64]
                else:
                    error_code = "backup_not_sent"
            except HTTPException as exc:
                error_code = f"backup_http_{int(exc.status_code)}"
            except Exception:
                error_code = "backup_send_failed"
        else:
            error_code = "no_oa_capacity_or_mapping"

        if status == "sent":
            sent_groups += 1
            if provider == "backup":
                backup_sent_groups += 1
            else:
                primary_sent_groups += 1
            if fallback_used:
                fallback_groups += 1
            for item in ledger_rows:
                item.status = "sent"
                item.sent_at = now()
                item.provider_slot = provider
                item.oa_basic_id = oa_basic_id
                item.hub_delivery_ref = hub_delivery_ref
                item.error_code = ""
        else:
            failed_groups += 1
            for item in ledger_rows:
                item.status = "failed"
                item.provider_slot = provider
                item.oa_basic_id = oa_basic_id
                item.error_code = error_code[:80]
                item.hub_delivery_ref = hub_delivery_ref

        recipient_results.append({
            "name": group.get("name") or "",
            "target_kind": group.get("target_kind") or "",
            "status": status,
            "duplicate": duplicate,
            "case_count": len(group.get("send_rows") or []),
            "error_code": error_code,
            "provider": provider,
            "oa_basic_id": oa_basic_id,
            "fallback_used": fallback_used,
            "route_reason": group.get("route_reason") or "",
        })
        db.commit()

    db.add(Audit(
        actor=actor,
        action="appointment_notice_send_batch",
        entity="appointment_notice",
        detail={
            "batch_id": body.send_nonce,
            "channel": body.channel,
            "policy": body.policy,
            "selected_cases": len(prepared["selected"]),
            "eligible_deliveries": prepared["eligible_deliveries"],
            "duplicate_deliveries": prepared["duplicate_deliveries"],
            "recipient_groups": len(active_groups),
            "sent_groups": sent_groups,
            "failed_groups": failed_groups,
            "primary_sent_groups": primary_sent_groups,
            "backup_sent_groups": backup_sent_groups,
            "fallback_groups": fallback_groups,
            "blocked_groups": int(routing.get("blocked_groups") or 0),
            "missing_recipient_count": len(prepared["missing"]),
            "routing_state": str(routing.get("state") or ""),
            "primary_basic_id": str(primary.get("basic_id") or ""),
            "primary_quota_used": primary.get("used"),
            "primary_quota_remaining": primary.get("remaining"),
            "backup_basic_id": str(backup.get("basic_id") or ""),
            "backup_quota_used": backup.get("used"),
            "backup_quota_remaining": backup.get("remaining"),
            "raw_line_id_logged": False,
            "message_content_logged": False,
        },
    ))
    db.commit()

    return {
        "status": "sent" if failed_groups == 0 else ("partial" if sent_groups else "failed"),
        "batch_id": body.send_nonce,
        "channel": body.channel,
        "policy": body.policy,
        "selected_cases": len(prepared["selected"]),
        "eligible_deliveries": prepared["eligible_deliveries"],
        "duplicate_deliveries": prepared["duplicate_deliveries"],
        "sent_groups": sent_groups,
        "failed_groups": failed_groups,
        "primary_sent_groups": primary_sent_groups,
        "backup_sent_groups": backup_sent_groups,
        "fallback_groups": fallback_groups,
        "blocked_groups": int(routing.get("blocked_groups") or 0),
        "routing_state": str(routing.get("state") or ""),
        "missing": prepared["missing"],
        "recipients": recipient_results,
    }

def history(db, limit: int = 50) -> dict:
    limit = max(1, min(int(limit or 50), 100))
    rows = db.query(AppointmentNoticeDelivery).order_by(
        AppointmentNoticeDelivery.id.desc()
    ).limit(1000).all()
    volunteers = {
        int(v.id): (v.name or v.full_name or "")
        for v in db.query(Volunteer).all()
    }
    groups = {}
    for item in rows:
        key = (str(item.batch_id), str(item.dedupe_key))
        group = groups.setdefault(key, {
            "max_id": int(item.id),
            "batch_id": str(item.batch_id),
            "channel": str(item.channel),
            "target_kind": str(item.target_kind),
            "recipient_volunteer_id": int(item.recipient_volunteer_id),
            "recipient_name": volunteers.get(int(item.recipient_volunteer_id), ""),
            "community": str(item.community or ""),
            "case_ids": set(),
            "statuses": [],
            "is_resend": False,
            "created_at": str(item.created_at or ""),
            "sent_at": str(item.sent_at or ""),
            "error_code": "",
            "provider_slot": str(getattr(item, "provider_slot", "") or ""),
            "oa_basic_id": str(getattr(item, "oa_basic_id", "") or ""),
        })
        group["case_ids"].add(str(item.case_id))
        group["statuses"].append(str(item.status))
        group["is_resend"] = bool(group["is_resend"] or item.is_resend)
        if item.sent_at and str(item.sent_at) > group["sent_at"]:
            group["sent_at"] = str(item.sent_at)
        if item.error_code:
            group["error_code"] = str(item.error_code)
        if getattr(item, "provider_slot", None):
            group["provider_slot"] = str(item.provider_slot)
        if getattr(item, "oa_basic_id", None):
            group["oa_basic_id"] = str(item.oa_basic_id)
        group["max_id"] = max(group["max_id"], int(item.id))

    output = []
    for group in groups.values():
        statuses = set(group.pop("statuses"))
        if "failed" in statuses:
            status = "failed"
        elif statuses == {"sent"}:
            status = "sent"
        elif "pending" in statuses:
            status = "pending"
        else:
            status = sorted(statuses)[0] if statuses else "unknown"
        case_ids = group.pop("case_ids")
        group["case_count"] = len(case_ids)
        group["status"] = status
        output.append(group)

    output.sort(key=lambda item: item["max_id"], reverse=True)
    for item in output:
        item.pop("max_id", None)
    return {"items": output[:limit], "count": len(output[:limit])}


def install_appointment_notice_phase2(app, auth, db_session, admin):
    @app.post("/api/v1/appointment-notices/send")
    def appointment_notice_send(
        body: AppointmentNoticeSendBody,
        u=Depends(auth), db=Depends(db_session),
    ):
        admin(u)
        if body.validate_only:
            return validate_send(db, body)
        if not SEND_LOCK.acquire(blocking=False):
            raise HTTPException(409, "กำลังส่ง LINE อีกชุดอยู่ กรุณารอให้เสร็จก่อน")
        try:
            return execute_send(db, body, actor=u.username)
        finally:
            SEND_LOCK.release()

    @app.get("/api/v1/appointment-notices/history")
    def appointment_notice_history(
        limit: int = 50, u=Depends(auth), db=Depends(db_session),
    ):
        admin(u)
        return history(db, limit)