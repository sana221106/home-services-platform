"""Notification fan-out (§85).

The database row is written in the request transaction so a customer always sees
the in-app notification even if push delivery is delayed or misconfigured. FCM
dispatch happens out-of-band via :mod:`app.workers.push_dispatcher`; when
credentials are absent the notification simply stays in-app (§135).
"""

from __future__ import annotations

import uuid

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.enums import NotificationType
from app.db.models.support import DeviceToken, Notification
from app.utils.pagination import offset_for
from app.utils.time import now_utc


def enqueue(
    session: Session,
    *,
    customer_id: uuid.UUID,
    type_: NotificationType,
    title_ar: str,
    body_ar: str,
    request_id: uuid.UUID | None = None,
    payload: dict | None = None,
) -> Notification:
    notification = Notification(
        customer_id=customer_id,
        request_id=request_id,
        type=type_,
        title_ar=title_ar,
        body_ar=body_ar,
        payload=payload,
    )
    session.add(notification)
    session.flush()
    return notification


def list_for_customer(
    session: Session,
    *,
    customer_id: uuid.UUID,
    page: int,
    per_page: int,
    unread_only: bool = False,
) -> tuple[list[Notification], int]:
    base = select(Notification).where(Notification.customer_id == customer_id)
    if unread_only:
        base = base.where(Notification.is_read.is_(False))
    total = int(
        session.execute(select(func.count()).select_from(base.subquery())).scalar_one()
    )
    rows = list(
        session.execute(
            base.order_by(Notification.created_at.desc())
            .offset(offset_for(page, per_page))
            .limit(per_page)
        )
        .scalars()
    )
    return rows, total


def mark_read(
    session: Session, *, customer_id: uuid.UUID, ids: list[uuid.UUID] | None
) -> int:
    stmt = select(Notification).where(
        Notification.customer_id == customer_id, Notification.is_read.is_(False)
    )
    if ids:
        stmt = stmt.where(Notification.id.in_(ids))
    updated = 0
    for notification in session.execute(stmt.limit(200)).scalars():
        notification.is_read = True
        notification.read_at = now_utc()
        updated += 1
    session.flush()
    return updated


def unread_count(session: Session, *, customer_id: uuid.UUID) -> int:
    return int(
        session.execute(
            select(func.count(Notification.id)).where(
                Notification.customer_id == customer_id,
                Notification.is_read.is_(False),
            )
        ).scalar_one()
        or 0
    )


def register_device_token(
    session: Session,
    *,
    customer_id: uuid.UUID,
    token: str,
    platform: str,
    app_version: str | None,
) -> DeviceToken:
    """Tokens are unique platform-wide and re-bound to the current customer on
    re-registration, so one device cannot accumulate stale owners."""
    existing = session.execute(
        select(DeviceToken).where(DeviceToken.token == token)
    ).scalar_one_or_none()
    if existing is not None:
        existing.customer_id = customer_id
        existing.is_active = True
        existing.app_version = app_version
        existing.last_seen_at = now_utc()
        session.flush()
        return existing
    device_token = DeviceToken(
        customer_id=customer_id,
        token=token,
        platform=platform,
        app_version=app_version,
        last_seen_at=now_utc(),
    )
    session.add(device_token)
    session.flush()
    return device_token


def active_tokens(session: Session, *, customer_id: uuid.UUID) -> list[str]:
    return list(
        session.execute(
            select(DeviceToken.token).where(
                DeviceToken.customer_id == customer_id, DeviceToken.is_active.is_(True)
            )
        ).scalars()
    )


def pending_push(session: Session, *, limit: int = 100) -> list[Notification]:
    return list(
        session.execute(
            select(Notification)
            .where(Notification.push_sent_at.is_(None), Notification.push_failure_reason.is_(None))
            .order_by(Notification.created_at.asc())
            .limit(limit)
        ).scalars()
    )


def mark_push_result(
    session: Session, *, notification: Notification, success: bool, reason: str | None = None
) -> None:
    notification.push_sent_at = now_utc() if success else None
    notification.push_failure_reason = None if success else (reason or "push_failed")[:255]
    session.flush()
