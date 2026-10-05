"""Versioned quote creation and customer decisions (§64, §139, §140).

Concurrency rules:

* ``(request_id, revision_number)`` is unique — two operators racing to revise
  produce one winner and one integrity error, never two live quotes.
* Acceptance runs in a transaction with ``SELECT ... FOR UPDATE`` on the
  request, so an acceptance can never land after a supersede or a cancellation.
* Accepting one revision marks every sibling revision ``SUPERSEDED``/``EXPIRED``
  rather than deleting them.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta
from decimal import Decimal
from typing import Any, cast

from sqlalchemy import CursorResult, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.enums import AuditAction, QuoteStatus, RequestStatus, Urgency
from app.core.exceptions import (
    ConflictError,
    InvalidStateTransitionError,
    QuoteAlreadyDecidedError,
    QuoteExpiredError,
    ValidationError,
)
from app.core.logging import get_logger
from app.db.models.quotes import Quote, QuoteItem, QuoteRevision
from app.db.models.requests import ServiceRequest
from app.schemas.requests import CreateQuoteRequest
from app.services import analytics_service, request_service
from app.services.analytics_service import AnalyticsEventName
from app.services.audit_service import record_audit
from app.services.pricing_service import calculate_quote_totals
from app.utils.time import ensure_aware, now_utc

log = get_logger(__name__)

_STATUS_FOR_ACCEPT = {
    RequestStatus.QUOTE_SENT: RequestStatus.AWAITING_CUSTOMER_APPROVAL,
    RequestStatus.AWAITING_CUSTOMER_APPROVAL: RequestStatus.DEPOSIT_PENDING,
    RequestStatus.INSPECTION_COMPLETED: RequestStatus.QUOTE_SENT,
}


def next_revision_number(session: Session, *, request_id: uuid.UUID) -> int:
    latest = session.execute(
        select(Quote.revision_number)
        .where(Quote.request_id == request_id)
        .order_by(Quote.revision_number.desc())
        .limit(1)
    ).scalar_one_or_none()
    return int(latest or 0) + 1


def current_quote(session: Session, *, request_id: uuid.UUID) -> Quote | None:
    """The only revision the customer is allowed to act on."""
    return session.execute(
        select(Quote)
        .where(
            Quote.request_id == request_id,
            Quote.status.in_([QuoteStatus.SENT, QuoteStatus.ACCEPTED]),
        )
        .order_by(Quote.revision_number.desc())
        .limit(1)
    ).scalar_one_or_none()


def all_revisions(session: Session, *, request_id: uuid.UUID) -> list[Quote]:
    return list(
        session.execute(
            select(Quote)
            .where(Quote.request_id == request_id)
            .order_by(Quote.revision_number.desc())
        )
        .scalars()
    )


def create_quote(
    session: Session,
    *,
    request: ServiceRequest,
    payload: CreateQuoteRequest,
    staff_id: uuid.UUID,
    staff_role: str | None,
    deposit_percent: Decimal,
) -> Quote:
    if request.status not in {
        RequestStatus.UNDER_REVIEW,
        RequestStatus.QUOTE_PREPARATION,
        RequestStatus.QUOTE_SENT,
        RequestStatus.AWAITING_CUSTOMER_APPROVAL,
        RequestStatus.QUOTE_REJECTED,
        RequestStatus.INSPECTION_COMPLETED,
        RequestStatus.NEED_MORE_INFORMATION,
    }:
        raise InvalidStateTransitionError(
            "A quote cannot be created while the request is in its current status.",
            details={"status": request.status.value},
        )

    revision = next_revision_number(session, request_id=request.id)
    totals = calculate_quote_totals(
        service_cost=payload.service_cost,
        materials_cost=payload.materials_cost,
        urgency_fee=payload.urgency_fee,
        inspection_fee=payload.inspection_fee,
        discount=payload.discount,
        deposit_percent=deposit_percent,
    )

    expires_at = now_utc() + timedelta(hours=payload.expires_in_hours)
    quote = Quote(
        request_id=request.id,
        revision_number=revision,
        status=QuoteStatus.SENT if payload.send_immediately else QuoteStatus.DRAFT,
        urgency=request.urgency,
        service_cost=payload.service_cost,
        materials_cost=payload.materials_cost,
        urgency_fee=payload.urgency_fee,
        inspection_fee=payload.inspection_fee,
        discount=totals["discount"],
        subtotal=totals["subtotal"],
        total=totals["total"],
        deposit_amount=totals["deposit_amount"],
        estimated_duration_minutes=payload.estimated_duration_minutes,
        notes=payload.notes,
        internal_notes=payload.internal_notes,
        requires_deposit=totals["deposit_amount"] > 0,
        created_by_id=staff_id,
        sent_at=now_utc() if payload.send_immediately else None,
        expires_at=expires_at,
    )
    session.add(quote)
    try:
        session.flush()
    except IntegrityError as exc:
        session.rollback()
        raise ConflictError(
            "Another quote revision was created concurrently. Please reload.",
            code="QUOTE_REVISION_CONFLICT",
        ) from exc

    for position, item in enumerate(payload.items):
        session.add(
            QuoteItem(
                quote_id=quote.id,
                position=position,
                label_ar=item.label_ar,
                quantity=item.quantity,
                unit_price=item.unit_price,
                line_total=(item.quantity * item.unit_price).quantize(Decimal("0.01")),
                item_type=item.item_type,
            )
        )

    previous = session.execute(
        select(Quote)
        .where(Quote.request_id == request.id, Quote.id != quote.id)
        .order_by(Quote.revision_number.desc())
        .limit(1)
    ).scalar_one_or_none()

    session.execute(
        update(Quote)
        .where(
            Quote.request_id == request.id,
            Quote.id != quote.id,
            Quote.status.in_([QuoteStatus.SENT, QuoteStatus.DRAFT]),
        )
        .values(status=QuoteStatus.SUPERSEDED)
    )

    session.add(
        QuoteRevision(
            quote_id=quote.id,
            revision_number=revision,
            previous_total=previous.total if previous is not None else None,
            new_total=quote.total,
            change_reason=payload.notes,
            created_by_id=staff_id,
            created_at=now_utc(),
        )
    )

    record_audit(
        session,
        action=AuditAction.QUOTE_REVISED if previous is not None else AuditAction.QUOTE_CREATED,
        entity="quote",
        entity_id=quote.id,
        actor_id=staff_id,
        actor_role=staff_role,
        before={"revision": previous.revision_number, "total": str(previous.total)}
        if previous is not None
        else None,
        after={
            "revision": revision,
            "total": str(quote.total),
            "deposit": str(quote.deposit_amount),
            "status": quote.status.value,
        },
    )

    request_service.transition_request(
        session,
        request=request,
        target=RequestStatus.QUOTE_SENT,
        actor_type="staff",
        actor_id=staff_id,
        actor_role=staff_role,
        event_type="QUOTE_REVISED" if previous is not None else "QUOTE_SENT",
        note_ar=payload.notes,
    )
    request_service.record_event(
        session,
        request_id=request.id,
        event_type="QUOTE_CREATED",
        actor_type="staff",
        actor_id=staff_id,
        actor_role=staff_role,
        payload={"revision": revision, "total": str(quote.total)},
    )
    analytics_service.record_event(
        session,
        event_name=AnalyticsEventName.QUOTE_SENT if payload.send_immediately else AnalyticsEventName.QUOTE_CREATED,
        customer_id=request.customer_id,
        request_id=request.id,
        properties={"revision": revision, "total": str(quote.total)},
    )
    session.flush()
    return quote


def _lock_request(session: Session, *, request_id: uuid.UUID) -> ServiceRequest:
    """Row lock so acceptance cannot race a supersede or a cancellation (§140)."""
    return session.execute(
        select(ServiceRequest)
        .where(ServiceRequest.id == request_id)
        .with_for_update()
    ).scalar_one()


def accept_quote(
    session: Session,
    *,
    request: ServiceRequest,
    customer_id: uuid.UUID,
    accepted_revision: int,
    idempotency_key: str | None = None,
) -> Quote:
    if request.customer_id != customer_id:
        from app.core.exceptions import NotFoundError

        raise NotFoundError("Request not found.")

    locked = _lock_request(session, request_id=request.id)
    if RequestStatus(locked.status) not in {
        RequestStatus.AWAITING_CUSTOMER_APPROVAL,
        RequestStatus.QUOTE_SENT,
    }:
        raise InvalidStateTransitionError(
            "This quote cannot be accepted right now.",
            details={"status": locked.status.value},
        )

    quote = session.execute(
        select(Quote)
        .where(Quote.request_id == locked.id)
        .with_for_update()
        .order_by(Quote.revision_number.desc())
    ).scalars().first()

    if quote is None or quote.status != QuoteStatus.SENT:
        raise QuoteAlreadyDecidedError()
    if quote.revision_number != accepted_revision:
        raise ConflictError(
            "A newer quote is available. Please review the latest version.",
            code="QUOTE_SUPERSEDED",
            details={"current_revision": quote.revision_number},
        )
    if quote.expires_at is not None and ensure_aware(quote.expires_at) <= now_utc():
        quote.status = QuoteStatus.EXPIRED
        session.flush()
        raise QuoteExpiredError()

    quote.status = QuoteStatus.ACCEPTED
    quote.decided_at = now_utc()
    quote.decided_by_customer_id = customer_id
    quote.viewed_at = quote.viewed_at or now_utc()

    session.execute(
        update(Quote)
        .where(Quote.request_id == locked.id, Quote.id != quote.id, Quote.status == QuoteStatus.SENT)
        .values(status=QuoteStatus.SUPERSEDED)
    )

    request_service.record_event(
        session,
        request_id=locked.id,
        event_type="QUOTE_ACCEPTED",
        actor_type="customer",
        actor_id=customer_id,
        payload={"revision": quote.revision_number, "total": str(quote.total)},
    )

    next_status = _STATUS_FOR_ACCEPT.get(RequestStatus(locked.status), RequestStatus.DEPOSIT_PENDING)
    if quote.requires_deposit:
        target = RequestStatus.DEPOSIT_PENDING
        event_type = "DEPOSIT_REQUIRED"
        note = "يرجى سداد العربون لتأكيد الحجز"
    else:
        target = RequestStatus.CONFIRMED
        event_type = "REQUEST_CONFIRMED"
        note = "تم تأكيد الحجز"

    request_service.transition_request(
        session,
        request=locked,
        target=target,
        actor_type="customer",
        actor_id=customer_id,
        event_type=event_type,
        note_ar=note,
    )
    _ = next_status

    analytics_service.record_event(
        session,
        event_name=AnalyticsEventName.QUOTE_ACCEPTED,
        customer_id=customer_id,
        request_id=locked.id,
        properties={"revision": quote.revision_number},
    )
    session.flush()
    return quote


def reject_quote(
    session: Session,
    *,
    request: ServiceRequest,
    customer_id: uuid.UUID,
    reason: str | None = None,
) -> Quote:
    if request.customer_id != customer_id:
        from app.core.exceptions import NotFoundError

        raise NotFoundError("Request not found.")

    locked = _lock_request(session, request_id=request.id)
    if RequestStatus(locked.status) != RequestStatus.AWAITING_CUSTOMER_APPROVAL:
        raise InvalidStateTransitionError(
            "This quote cannot be rejected right now.",
            details={"status": locked.status.value},
        )

    quote = session.execute(
        select(Quote)
        .where(Quote.request_id == locked.id)
        .with_for_update()
        .order_by(Quote.revision_number.desc())
    ).scalars().first()
    if quote is None or quote.status != QuoteStatus.SENT:
        raise QuoteAlreadyDecidedError()

    quote.status = QuoteStatus.REJECTED
    quote.decided_at = now_utc()
    quote.decided_by_customer_id = customer_id

    request_service.record_event(
        session,
        request_id=locked.id,
        event_type="QUOTE_REJECTED",
        actor_type="customer",
        actor_id=customer_id,
        payload={"revision": quote.revision_number, "reason": reason},
    )
    request_service.transition_request(
        session,
        request=locked,
        target=RequestStatus.QUOTE_REJECTED,
        actor_type="customer",
        actor_id=customer_id,
        event_type="QUOTE_REJECTED",
        note_ar=reason,
    )
    analytics_service.record_event(
        session,
        event_name=AnalyticsEventName.QUOTE_REJECTED,
        customer_id=customer_id,
        request_id=locked.id,
        properties={"revision": quote.revision_number},
    )
    session.flush()
    return quote


def mark_quote_viewed(session: Session, *, quote: Quote, customer_id: uuid.UUID) -> Quote:
    if quote.viewed_at is None:
        quote.viewed_at = now_utc()
        analytics_service.record_event(
            session,
            event_name=AnalyticsEventName.QUOTE_VIEWED,
            customer_id=customer_id,
            request_id=quote.request_id,
            properties={"revision": quote.revision_number},
        )
        session.flush()
    return quote


def expire_stale_quotes(session: Session, *, at: datetime | None = None) -> int:
    """Called by the worker. Expired quotes are terminal for the customer but
    the revision row is preserved for audit."""
    moment = at or now_utc()
    # UPDATE returns a CursorResult; the plain Result annotation hides rowcount.
    result = session.execute(
        update(Quote)
        .where(Quote.status == QuoteStatus.SENT, Quote.expires_at.is_not(None), Quote.expires_at <= moment)
        .values(status=QuoteStatus.EXPIRED)
    )
    session.commit()
    # UPDATE via the ORM connection is a CursorResult at runtime; the annotation
    # is widened only at the call site because Session.execute is overloaded.
    return int(cast("CursorResult[Any]", result).rowcount or 0)


def assert_quote_actionable(quote: Quote | None) -> Quote:
    if quote is None:
        raise ValidationError("No quote is available for this request yet.")
    if quote.status == QuoteStatus.EXPIRED:
        raise QuoteExpiredError()
    if quote.status != QuoteStatus.SENT:
        raise QuoteAlreadyDecidedError()
    return quote


def quote_summary(quote: Quote | None) -> dict[str, Any] | None:
    if quote is None:
        return None
    return {
        "revision": quote.revision_number,
        "status": quote.status.value,
        "total": str(quote.total),
        "deposit": str(quote.deposit_amount),
        "urgency": str(quote.urgency),
    }


__all__ = [
    "URGENCY_LABELS",
    "accept_quote",
    "all_revisions",
    "assert_quote_actionable",
    "create_quote",
    "current_quote",
    "expire_stale_quotes",
    "mark_quote_viewed",
    "next_revision_number",
    "quote_summary",
    "reject_quote",
]

URGENCY_LABELS: dict[Urgency, str] = {
    Urgency.NORMAL: "عادي",
    Urgency.URGENT: "عاجل",
}