"""Complaints, reviews and support endpoints (§14, §15, §16)."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, File, Query, Request, UploadFile

from app.api.dependencies import CurrentCustomer, DbSession
from app.core.enums import ComplaintReason
from app.core.exceptions import ValidationError
from app.core.rate_limit import COMPLAINT_LIMIT, limiter
from app.schemas.common import MessageResponse, Page
from app.schemas.support import (
    ComplaintCreateRequest,
    ComplaintResponse,
    ReviewCreateRequest,
    ReviewResponse,
    SendMessageRequest,
    StartConversationRequest,
    SupportContact,
    SupportPageResponse,
)
from app.services import complaint_service, request_service, support_service

router = APIRouter(tags=["support"])

SUPPORT_CONTACTS = [
    SupportContact(
        code="CALL_CENTER",
        label_ar="خدمة العملاء",
        phone="+201000000000",
        available_hours_ar="يوميًا من 9 صباحًا حتى 9 مساءً",
    ),
    SupportContact(
        code="COMPLAINT",
        label_ar="شكاوى الخدمة",
        phone="+201000000001",
        available_hours_ar="يوميًا من 10 صباحًا حتى 6 مساءً",
    ),
]


@router.post(
    "/complaints",
    response_model=ComplaintResponse,
    status_code=201,
    summary="File a complaint about a request",
)
@limiter.limit(COMPLAINT_LIMIT)
def create_complaint(
    payload: ComplaintCreateRequest,
    request: Request,
    db: DbSession,
    customer: CurrentCustomer,
) -> ComplaintResponse:
    if payload.request_id is not None:
        request_service.get_request_for_customer(
            db, request_id=payload.request_id, customer_id=customer.profile.id
        )
    complaint = complaint_service.create_complaint(
        db,
        customer_id=customer.profile.id,
        request_id=payload.request_id,
        reason=payload.reason,
        description=payload.description,
        idempotency_key=payload.idempotency_key,
    )
    db.commit()
    return ComplaintResponse.model_validate(complaint)


@router.get(
    "/complaints",
    response_model=Page[ComplaintResponse],
    summary="My complaints",
)
def list_complaints(
    db: DbSession,
    customer: CurrentCustomer,
    page: int = Query(default=1, ge=1),
    per_page: int = Query(default=20, ge=1, le=100),
) -> Page[ComplaintResponse]:
    rows, total = complaint_service.list_for_customer(
        session=db, customer_id=customer.profile.id, page=page, per_page=per_page
    )
    return Page[ComplaintResponse].build(
        items=[ComplaintResponse.model_validate(row) for row in rows],
        total=total,
        page=page,
        per_page=per_page,
    )


@router.get(
    "/complaints/reasons",
    response_model=list[str],
    summary="Complaint reason codes",
)
def complaint_reasons(_customer: CurrentCustomer) -> list[str]:
    # Declared before "/complaints/{complaint_id}" so the literal path wins;
    # otherwise "reasons" is parsed as a UUID and the route 422s.
    return [reason.value for reason in ComplaintReason]


@router.get(
    "/complaints/{complaint_id}",
    response_model=ComplaintResponse,
    summary="Complaint detail",
)
def get_complaint(
    complaint_id: uuid.UUID, db: DbSession, customer: CurrentCustomer
) -> ComplaintResponse:
    complaint = complaint_service.get_for_customer(
        session=db, complaint_id=complaint_id, customer_id=customer.profile.id
    )
    return ComplaintResponse.model_validate(complaint)


@router.post(
    "/complaints/{complaint_id}/attachments",
    response_model=MessageResponse,
    status_code=201,
    summary="Attach evidence to a complaint",
)
def attach_complaint_file(
    complaint_id: uuid.UUID,
    db: DbSession,
    customer: CurrentCustomer,
    file: Annotated[UploadFile, File(description="JPEG/PNG/WebP")],
) -> MessageResponse:
    complaint = complaint_service.get_for_customer(
        session=db, complaint_id=complaint_id, customer_id=customer.profile.id
    )
    content = file.file.read()
    if not content:
        raise ValidationError("The uploaded file is empty.")
    complaint_service.add_attachment(
        session=db,
        complaint=complaint,
        customer_id=customer.profile.id,
        content=content,
        declared_mime=file.content_type,
        filename=file.filename,
    )
    db.commit()
    return MessageResponse(message="تم إرفاق الصورة.")


# ------------------------------------------------------------------ reviews


@router.post(
    "/reviews",
    response_model=ReviewResponse,
    status_code=201,
    summary="Rate a completed request",
)
def create_review(
    payload: ReviewCreateRequest, db: DbSession, customer: CurrentCustomer
) -> ReviewResponse:
    review = support_service.create_review(
        db,
        customer_id=customer.profile.id,
        request_id=payload.request_id,
        rating=payload.rating,
        text=payload.text,
        has_image=payload.has_image,
    )
    db.commit()
    return ReviewResponse.model_validate(review)


@router.get(
    "/reviews",
    response_model=list[ReviewResponse],
    summary="My ratings",
)
def list_reviews(
    db: DbSession,
    customer: CurrentCustomer,
    limit: int = Query(default=50, ge=1, le=200),
) -> list[ReviewResponse]:
    rows = support_service.list_reviews(
        session=db, customer_id=customer.profile.id, limit=limit
    )
    return [ReviewResponse(**row) for row in rows]


# --------------------------------------------------------------------- chat


@router.get(
    "/conversations",
    response_model=list[dict],
    summary="My conversations",
)
def list_conversations(
    db: DbSession, customer: CurrentCustomer
) -> list[dict]:
    return support_service.list_conversations(
        session=db, customer_id=customer.profile.id
    )


@router.post(
    "/conversations",
    response_model=dict,
    status_code=201,
    summary="Start a conversation with the company",
)
def start_conversation(
    payload: StartConversationRequest, db: DbSession, customer: CurrentCustomer
) -> dict:
    conversation = support_service.start_conversation(
        session=db, customer_id=customer.profile.id, payload=payload
    )
    db.commit()
    return {"id": conversation.id, "subject": conversation.subject}


@router.post(
    "/conversations/{conversation_id}/messages",
    response_model=dict,
    status_code=201,
    summary="Reply inside an existing conversation",
)
def send_message(
    conversation_id: uuid.UUID,
    payload: SendMessageRequest,
    db: DbSession,
    customer: CurrentCustomer,
) -> dict:
    conversation = support_service.get_conversation(
        session=db, conversation_id=conversation_id, customer_id=customer.profile.id
    )
    message = support_service.send_message(
        session=db,
        conversation=conversation,
        customer_id=customer.profile.id,
        payload=payload,
    )
    support_service.notify_support_of_message(
        session=db, conversation=conversation, message=message
    )
    db.commit()
    return {
        "id": message.id,
        "conversation_id": conversation.id,
        "body": message.body,
        "sent_at": message.sent_at,
    }


@router.get(
    "/conversations/{conversation_id}/messages",
    response_model=list[dict],
    summary="Conversation messages",
)
def list_messages(
    conversation_id: uuid.UUID,
    db: DbSession,
    customer: CurrentCustomer,
    limit: int = Query(default=200, ge=1, le=500),
) -> list[dict]:
    conversation = support_service.get_conversation(
        session=db, conversation_id=conversation_id, customer_id=customer.profile.id
    )
    rows = support_service.messages(
        session=db,
        conversation=conversation,
        customer_id=customer.profile.id,
        limit=limit,
    )
    support_service.mark_conversation_read(
        session=db, conversation=conversation, customer_id=customer.profile.id
    )
    db.commit()
    return rows


@router.post(
    "/conversations/{conversation_id}/read",
    response_model=MessageResponse,
    summary="Mark a conversation as read",
)
def mark_read(
    conversation_id: uuid.UUID, db: DbSession, customer: CurrentCustomer
) -> MessageResponse:
    conversation = support_service.get_conversation(
        session=db, conversation_id=conversation_id, customer_id=customer.profile.id
    )
    support_service.mark_conversation_read(
        session=db, conversation=conversation, customer_id=customer.profile.id
    )
    db.commit()
    return MessageResponse(message="تم تعليم المحادثة كمقروءة.")


# ------------------------------------------------------------------ support


@router.get(
    "/support",
    response_model=SupportPageResponse,
    summary="Support channels",
)
def support_page(_customer: CurrentCustomer) -> SupportPageResponse:
    return SupportPageResponse(
        contacts=SUPPORT_CONTACTS,
        availability_note_ar="يمكنك مراسلتنا عبر المحادثة في أي وقت.",
        can_chat=True,
    )