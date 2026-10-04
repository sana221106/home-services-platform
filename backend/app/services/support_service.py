"""Customer ⇄ company chat, support call log and reviews (§15, §16, §77)."""

from __future__ import annotations

import uuid
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.exceptions import NotFoundError, ValidationError
from app.db.models.requests import ServiceRequest
from app.db.models.support import (
    Conversation,
    Message,
    MessageAttachment,
    Review,
    SupportCallLog,
)
from app.schemas.support import (
    SendMessageRequest,
    StartConversationRequest,
)

from app.services import notification_service


# ------------------------------------------------------------------ chat


def _assert_customer(session: Session, *, conversation: Conversation, customer_id: uuid.UUID) -> None:
    if conversation.customer_id != customer_id:
        raise NotFoundError("Conversation not found.")


def list_conversations(
    session: Session, *, customer_id: uuid.UUID
) -> list[dict[str, Any]]:
    rows = list(
        session.execute(
            select(Conversation)
            .where(Conversation.customer_id == customer_id)
            .order_by(
                func.coalesce(Conversation.last_message_at, Conversation.created_at).desc()
            )
        ).scalars()
    )
    results: list[dict[str, Any]] = []
    for conversation in rows:
        unread = int(
            session.execute(
                select(func.count(Message.id)).where(
                    Message.conversation_id == conversation.id,
                    Message.read_at.is_(None),
                    Message.sender_type != "customer",
                )
            ).scalar_one()
        )
        preview = session.execute(
            select(Message.body)
            .where(Message.conversation_id == conversation.id)
            .order_by(Message.sent_at.desc())
            .limit(1)
        ).scalar_one_or_none()
        results.append(
            {
                "id": conversation.id,
                "request_id": conversation.request_id,
                "subject": conversation.subject,
                "is_open": conversation.is_open,
                "last_message_at": conversation.last_message_at,
                "last_message_preview": preview,
                "unread_count": unread,
            }
        )
    return results


def get_conversation(
    session: Session, *, conversation_id: uuid.UUID, customer_id: uuid.UUID
) -> Conversation:
    conversation = session.get(Conversation, conversation_id)
    if conversation is None:
        raise NotFoundError("Conversation not found.")
    _assert_customer(session, conversation=conversation, customer_id=customer_id)
    return conversation


def messages(
    session: Session, *, conversation: Conversation, customer_id: uuid.UUID, limit: int = 200
) -> list[dict[str, Any]]:
    _assert_customer(session, conversation=conversation, customer_id=customer_id)
    rows = list(
        session.execute(
            select(Message)
            .where(Message.conversation_id == conversation.id)
            .order_by(Message.sent_at.asc())
            .limit(limit)
        ).scalars()
    )
    attachments = list(
        session.execute(
            select(MessageAttachment).where(
                MessageAttachment.message_id.in_([row.id for row in rows])
            )
        ).scalars()
    )
    grouped: dict[uuid.UUID, list[str]] = {}
    for item in attachments:
        # Authorised API routes, never the raw storage path: a path carries the
        # bucket plus customer/conversation/attachment UUIDs (§79).
        grouped.setdefault(item.message_id, []).append(
            f"/api/v1/media/message-attachments/{item.id}/content"
        )
    return [
        {
            "id": row.id,
            "conversation_id": row.conversation_id,
            "sender_type": row.sender_type,
            "body": row.body,
            "sent_at": row.sent_at,
            "attachment_urls": grouped.get(row.id, []),
        }
        for row in rows
    ]


def start_conversation(
    session: Session, *, customer_id: uuid.UUID, payload: StartConversationRequest
) -> Conversation:
    if payload.request_id is not None:
        owned = session.execute(
            select(ServiceRequest.id).where(
                ServiceRequest.id == payload.request_id,
                ServiceRequest.customer_id == customer_id,
            )
        ).scalar_one_or_none()
        if owned is None:
            raise NotFoundError("Request not found.")

    existing = session.execute(
        select(Conversation).where(
            Conversation.customer_id == customer_id,
            Conversation.request_id == payload.request_id,
            Conversation.is_open.is_(True),
        )
    ).scalar_one_or_none()
    if existing is not None:
        send_message(
            session,
            conversation=existing,
            customer_id=customer_id,
            payload=SendMessageRequest(body=payload.first_message),
        )
        return existing

    conversation = Conversation(
        customer_id=customer_id,
        request_id=payload.request_id,
        subject=payload.subject or "استفسار عبر المحادثة",
        is_open=True,
    )
    session.add(conversation)
    session.flush()
    send_message(
        session,
        conversation=conversation,
        customer_id=customer_id,
        payload=SendMessageRequest(body=payload.first_message),
    )
    return conversation


def send_message(
    session: Session,
    *,
    conversation: Conversation,
    customer_id: uuid.UUID,
    payload: SendMessageRequest,
) -> Message:
    _assert_customer(session, conversation=conversation, customer_id=customer_id)
    if not conversation.is_open:
        raise ValidationError("هذه المحادثة مغلقة. ابدأ محادثة جديدة.")

    from app.utils.time import now_utc

    message = Message(
        conversation_id=conversation.id,
        sender_type="customer",
        sender_id=customer_id,
        body=payload.body,
        sent_at=now_utc(),
    )
    if payload.latitude is not None and payload.longitude is not None:
        message.latitude = payload.latitude
        message.longitude = payload.longitude
    session.add(message)
    session.flush()

    for attachment_id in payload.attachment_ids:
        # message_attachments has no customer_id or conversation_id of its own,
        # so ownership is proven by walking attachment -> message -> conversation.
        owned = session.execute(
            select(MessageAttachment.id)
            .join(Message, Message.id == MessageAttachment.message_id)
            .join(Conversation, Conversation.id == Message.conversation_id)
            .where(
                MessageAttachment.id == attachment_id,
                Conversation.customer_id == customer_id,
            )
        ).scalar_one_or_none()
        if owned is None:
            raise NotFoundError("Attachment not found.")
        # Ownership is already proven above, so this fetch cannot come back empty.
        attachment = session.execute(
            select(MessageAttachment).where(MessageAttachment.id == attachment_id)
        ).scalar_one()
        attachment.message_id = message.id

    from app.utils.time import now_utc

    conversation.last_message_at = now_utc()
    session.flush()
    return message


def mark_conversation_read(
    session: Session, *, conversation: Conversation, customer_id: uuid.UUID
) -> None:
    _assert_customer(session, conversation=conversation, customer_id=customer_id)
    rows = list(
        session.execute(
            select(Message).where(
                Message.conversation_id == conversation.id,
                Message.read_at.is_(None),
                Message.sender_type != "customer",
            )
        ).scalars()
    )
    from app.utils.time import now_utc

    for row in rows:
        row.is_read = True
        row.read_at = now_utc()
    session.flush()


def close_conversation(
    session: Session, *, conversation: Conversation, customer_id: uuid.UUID
) -> Conversation:
    _assert_customer(session, conversation=conversation, customer_id=customer_id)
    conversation.is_open = False
    conversation.closed_at = _now()
    session.flush()
    return conversation


def _now():  # noqa: ANN202
    from app.utils.time import now_utc

    return now_utc()


def unread_chat_count(session: Session, *, customer_id: uuid.UUID) -> int:
    return int(
        session.execute(
            select(func.count(Message.id))
            .join(Conversation, Conversation.id == Message.conversation_id)
            .where(
                Conversation.customer_id == customer_id,
                Message.read_at.is_(None),
                Message.sender_type != "customer",
            )
        ).scalar_one()
    )


# ----------------------------------------------------------------- support


def log_call(
    session: Session,
    *,
    customer_id: uuid.UUID,
    request_id: uuid.UUID | None,
    staff_id: uuid.UUID,
    direction: str,
    outcome: str | None,
    duration_seconds: int | None,
    notes: str | None,
    next_follow_up_at=None,  # noqa: ANN001
) -> SupportCallLog:
    call = SupportCallLog(
        customer_id=customer_id,
        request_id=request_id,
        staff_id=staff_id,
        direction=direction,
        outcome=outcome,
        duration_seconds=duration_seconds,
        notes=notes,
        next_follow_up_at=next_follow_up_at,
    )
    session.add(call)
    session.flush()
    return call


# ----------------------------------------------------------------- reviews


def can_rate(session: Session, *, customer_id: uuid.UUID, request_id: uuid.UUID) -> bool:
    from app.core.enums import RequestStatus

    row = session.execute(
        select(ServiceRequest.status).where(
            ServiceRequest.id == request_id, ServiceRequest.customer_id == customer_id
        )
    ).scalar_one_or_none()
    if row is None:
        return False
    return RequestStatus(row) in {RequestStatus.PAID, RequestStatus.AWAITING_RATING, RequestStatus.CLOSED}


def create_review(
    session: Session,
    *,
    customer_id: uuid.UUID,
    request_id: uuid.UUID,
    rating: int,
    text: str | None,
    has_image: bool,
) -> Review:
    """Idempotent per request: re-rating updates the same row instead of
    creating duplicates (§69)."""
    request = session.execute(
        select(ServiceRequest).where(
            ServiceRequest.id == request_id, ServiceRequest.customer_id == customer_id
        )
    ).scalar_one_or_none()
    if request is None:
        raise NotFoundError("Request not found.")
    if not can_rate(session, customer_id=customer_id, request_id=request_id):
        raise ValidationError("التقييم متاح بعد إتمام الخدمة فقط.")

    existing = session.execute(
        select(Review).where(Review.request_id == request_id)
    ).scalar_one_or_none()
    if existing is not None:
        existing.rating = rating
        existing.text = text
        existing.has_image = existing.has_image or has_image
        session.flush()
        return existing

    review = Review(
        request_id=request_id,
        customer_id=customer_id,
        rating=rating,
        text=text,
        has_image=has_image,
        publication_status="PENDING",
    )
    session.add(review)
    session.flush()

    from app.core.enums import RequestStatus
    from app.services import request_service
    from app.utils.time import now_utc

    request.rated_at = now_utc()
    if RequestStatus(request.status) == RequestStatus.AWAITING_RATING:
        request_service.transition_request(
            session,
            request=request,
            target=RequestStatus.CLOSED,
            actor_type="customer",
            actor_id=customer_id,
            actor_role="customer",
            event_type="RATING_SUBMITTED",
        )
    session.flush()
    return review


def list_reviews(
    session: Session, *, customer_id: uuid.UUID, limit: int = 50
) -> list[dict[str, Any]]:
    rows = list(
        session.execute(
            select(Review)
            .where(Review.customer_id == customer_id)
            .order_by(Review.created_at.desc())
            .limit(limit)
        ).scalars()
    )
    return [
        {
            "id": row.id,
            "request_id": row.request_id,
            "rating": row.rating,
            "text": row.text,
            "publication_status": row.publication_status,
            "image_url": None,
            "created_at": row.created_at,
        }
        for row in rows
    ]


# -------------------------------------------------------------- notifications


def notify_support_of_message(
    session: Session, *, conversation: Conversation, message: Message
) -> None:
    """Flag the conversation for the care team.

    The customer is *not* notified about their own message. The queue entry is
    what puts the thread in front of a human.
    """
    from app.services import analytics_service

    analytics_service.record_event(
        session,
        event_name=analytics_service.AnalyticsEventName.REQUEST_STARTED,
        customer_id=conversation.customer_id,
        request_id=conversation.request_id,
        platform="support_chat",
        properties={"conversation_id": str(conversation.id)},
    )