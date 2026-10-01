"""Append-only audit trail for sensitive staff actions (§78).

``before``/``after`` snapshots are scrubbed by the logging redactor's sibling
:func:`_safe_snapshot` so a price change never leaks an unrelated secret.
"""

from __future__ import annotations

import uuid
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.enums import AuditAction
from app.db.models.intelligence import AuditLog
from app.utils.time import now_utc

#: Fields never written into an audit snapshot.
_FORBIDDEN_SNAPSHOT_KEYS = frozenset(
    {
        "password",
        "password_hash",
        "otp",
        "otp_code",
        "code_hash",
        "token_hash",
        "service_role_key",
        "jwt_secret",
        "api_key",
    }
)


def _safe_snapshot(payload: dict[str, Any] | None) -> dict[str, Any] | None:
    if not payload:
        return None
    return {
        key: (value if key not in _FORBIDDEN_SNAPSHOT_KEYS else "[REDACTED]")
        for key, value in payload.items()
        if key not in {"created_at", "updated_at"}
    }


def record_audit(
    session: Session,
    *,
    action: AuditAction | str,
    entity: str,
    entity_id: uuid.UUID | str | None = None,
    actor_id: uuid.UUID | None = None,
    actor_role: str | None = None,
    actor_type: str = "staff",
    before: dict[str, Any] | None = None,
    after: dict[str, Any] | None = None,
    correlation_id: str | None = None,
    ip_address: str | None = None,
    user_agent: str | None = None,
) -> AuditLog:
    entry = AuditLog(
        actor_id=actor_id,
        actor_role=actor_role,
        actor_type=actor_type,
        action=str(action),
        entity=entity,
        entity_id=uuid.UUID(entity_id) if isinstance(entity_id, str) else entity_id,
        before=_safe_snapshot(before),
        after=_safe_snapshot(after),
        correlation_id=correlation_id,
        ip_address=ip_address,
        user_agent=(user_agent or "")[:255] or None,
        created_at=now_utc(),
    )
    session.add(entry)
    session.flush()
    return entry


def list_audit_logs(
    session: Session,
    *,
    entity: str | None = None,
    entity_id: uuid.UUID | None = None,
    actor_id: uuid.UUID | None = None,
    action: str | None = None,
    page: int = 1,
    per_page: int = 50,
) -> tuple[list[AuditLog], int]:
    stmt = select(AuditLog)
    filters = []
    if entity:
        filters.append(AuditLog.entity == entity)
    if entity_id:
        filters.append(AuditLog.entity_id == entity_id)
    if actor_id:
        filters.append(AuditLog.actor_id == actor_id)
    if action:
        filters.append(AuditLog.action == str(action))
    if filters:
        stmt = stmt.where(*filters)

    total = session.execute(
        select(func.count()).select_from(AuditLog).where(*filters)
    ).scalar_one()
    rows = list(
        session.execute(
            stmt.order_by(AuditLog.created_at.desc()).offset((page - 1) * per_page).limit(per_page)
        ).scalars()
    )
    return rows, int(total)