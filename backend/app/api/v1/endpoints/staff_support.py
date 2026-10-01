"""Complaints, QC, reviews and chat for staff (§14, §15, §73)."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select

from app.api.dependencies import DbSession, require
from app.core.enums import ComplaintStatus, Permission, ReviewStatus
from app.db.models.support import Complaint, Review
from app.schemas.common import MessageResponse, Page
from app.schemas.support import (
    ComplaintAssignRequest,
    ComplaintResolveRequest,
    ComplaintResponse,
    ComplaintStatusChangeRequest,
    LogCallRequest,
    ModerateReviewRequest,
    ReviewResponse,
)
from app.services import audit_service, complaint_service, support_service
from app.db.models.identity import CustomerProfile

router = APIRouter(prefix="/staff", tags=["staff-support"])

ComplaintReadGuard = Annotated[..., Depends(require(Permission.COMPLAINT_READ))]
ComplaintWriteGuard = Annotated[..., Depends(require(Permission.COMPLAINT_WRITE))]
ComplaintAssignGuard = Annotated[..., Depends(require(Permission.COMPLAINT_ASSIGN))]
ComplaintResolveGuard = Annotated[..., Depends(require(Permission.COMPLAINT_RESOLVE))]
ReviewGuard = Annotated[..., Depends(require(Permission.REVIEW_MODERATE))]
ChatReadGuard = Annotated[..., Depends(require(Permission.CHAT_READ))]
ChatSendGuard = Annotated[..., Depends(require(Permission.CHAT_SEND))]
CallLogGuard = Annotated[..., Depends(require(Permission.CALL_LOG_WRITE))]


@router.get(
    "/complaints",
    response_model=Page[ComplaintResponse],
    summary="Complaint queue",
)
def list_complaints(
    db: DbSession,
    _staff: ComplaintReadGuard,
    page: int = Query(default=1, ge=1),
    per_page: int = Query(default=25, ge=1, le=100),
    status: ComplaintStatus | None = Query(default=None),
    assigned_to: uuid.UUID | None = Query(default=None),
) -> Page[ComplaintResponse]:
    rows, total = complaint_service.list_for_staff(
        session=db, page=page, per_page=per_page, status=status, assigned_to=assigned_to
    )
    return Page[ComplaintResponse].build(
        items=[ComplaintResponse.model_validate(row) for row in rows],
        total=total,
        page=page,
        per_page=per_page,
    )


@router.post(
    "/complaints/{complaint_id}/status",
    response_model=ComplaintResponse,
    summary="Move a complaint through its workflow",
)
def change_complaint_status(
    complaint_id: uuid.UUID,
    payload: ComplaintStatusChangeRequest,
    db: DbSession,
    staff: ComplaintWriteGuard,
) -> ComplaintResponse:
    from app.core.exceptions import NotFoundError

    complaint = db.get(Complaint, complaint_id)
    if complaint is None:
        raise NotFoundError("Complaint not found.")
    updated = complaint_service.transition(
        db,
        complaint=complaint,
        target=payload.status,
        staff_id=staff.staff.id,
        staff_role=staff.roles[0] if staff.roles else None,
        note=payload.note,
    )
    db.commit()
    return ComplaintResponse.model_validate(updated)


@router.post(
    "/complaints/{complaint_id}/assign",
    response_model=ComplaintResponse,
    summary="Assign a complaint owner",
)
def assign_complaint(
    complaint_id: uuid.UUID,
    payload: ComplaintAssignRequest,
    db: DbSession,
    staff: ComplaintAssignGuard,
) -> ComplaintResponse:
    from app.core.exceptions import NotFoundError

    complaint = db.get(Complaint, complaint_id)
    if complaint is None:
        raise NotFoundError("Complaint not found.")
    updated = complaint_service.assign_employee(
        db,
        complaint=complaint,
        employee_id=payload.employee_id,
        staff_id=staff.staff.id,
        staff_role=staff.roles[0] if staff.roles else None,
    )
    db.commit()
    return ComplaintResponse.model_validate(updated)


@router.post(
    "/complaints/{complaint_id}/resolve",
    response_model=ComplaintResponse,
    summary="Resolve a complaint and optionally schedule rework",
)
def resolve_complaint(
    complaint_id: uuid.UUID,
    payload: ComplaintResolveRequest,
    db: DbSession,
    staff: ComplaintResolveGuard,
) -> ComplaintResponse:
    from app.core.exceptions import NotFoundError

    complaint = db.get(Complaint, complaint_id)
    if complaint is None:
        raise NotFoundError("Complaint not found.")
    updated = complaint_service.resolve(
        db,
        complaint=complaint,
        staff_id=staff.staff.id,
        staff_role=staff.roles[0] if staff.roles else None,
        resolution=payload.resolution,
        requires_rework=payload.requires_rework,
        schedule_rework_at=payload.schedule_rework_at,
    )
    audit_service.record_audit(
        db,
        actor_id=staff.staff.id,
        actor_role=staff.roles[0] if staff.roles else None,
        action="COMPLAINT_RESOLVED",
        entity="complaint",
        entity_id=complaint.id,
        after={"requires_rework": payload.requires_rework},
    )
    db.commit()
    return ComplaintResponse.model_validate(updated)


# -------------------------------------------------------------------- reviews


@router.get(
    "/reviews", response_model=list[ReviewResponse], summary="Reviews awaiting moderation"
)
def list_reviews(
    db: DbSession,
    _staff: ReviewGuard,
    status: ReviewStatus | None = Query(default=None),
    limit: int = Query(default=50, ge=1, le=200),
) -> list[ReviewResponse]:
    stmt = select(Review).order_by(Review.created_at.desc()).limit(limit)
    if status is not None:
        stmt = stmt.where(Review.publication_status == status)
    rows = list(db.execute(stmt).scalars())
    return [ReviewResponse.model_validate(row) for row in rows]


@router.post(
    "/reviews/{review_id}/moderate",
    response_model=ReviewResponse,
    summary="Approve, hide or reject a review",
)
def moderate_review(
    review_id: uuid.UUID,
    payload: ModerateReviewRequest,
    db: DbSession,
    staff: ReviewGuard,
) -> ReviewResponse:
    from app.core.exceptions import NotFoundError

    review = db.get(Review, review_id)
    if review is None:
        raise NotFoundError("Review not found.")
    review.publication_status = payload.status
    review.moderation_note = payload.note
    db.commit()
    return ReviewResponse.model_validate(review)


# ----------------------------------------------------------------------- chat


@router.get(
    "/conversations/{conversation_id}/messages",
    response_model=list[dict],
    summary="Read a customer conversation",
)
def conversation_messages(
    conversation_id: uuid.UUID,
    db: DbSession,
    _staff: ChatReadGuard,
    limit: int = Query(default=200, ge=1, le=500),
) -> list[dict]:
    from app.db.models.support import Conversation

    conversation = db.get(Conversation, conversation_id)
    if conversation is None:
        from app.core.exceptions import NotFoundError

        raise NotFoundError("Conversation not found.")
    customer = db.get(CustomerProfile, conversation.customer_id)
    customer_id = customer.id if customer else conversation.customer_id
    return support_service.messages(
        session=db,
        conversation=conversation,
        customer_id=customer_id,
        limit=limit,
    )


@router.post(
    "/conversations/{conversation_id}/messages",
    response_model=dict,
    status_code=201,
    summary="Reply to a customer as the company",
)
def reply_to_customer(
    conversation_id: uuid.UUID,
    body: dict,
    db: DbSession,
    staff: ChatSendGuard,
) -> dict:
    from app.db.models.support import Conversation, Message as MessageModel

    conversation = db.get(Conversation, conversation_id)
    if conversation is None:
        from app.core.exceptions import NotFoundError

        raise NotFoundError("Conversation not found.")
    message = MessageModel(
        conversation_id=conversation.id,
        request_id=conversation.request_id,
        sender_type="staff",
        sender_staff_id=staff.staff.id,
        body=str(body.get("body", ""))[:4000],
        is_read=False,
    )
    db.add(message)
    from app.utils.time import now_utc

    conversation.last_message_at = now_utc()
    db.commit()
    return {"id": str(message.id), "sent_at": message.sent_at}


# ------------------------------------------------------------------ call logs


@router.post(
    "/customers/{customer_id}/calls",
    response_model=dict,
    status_code=201,
    summary="Log a call-centre interaction",
)
def log_call(
    customer_id: uuid.UUID,
    payload: LogCallRequest,
    db: DbSession,
    staff: CallLogGuard,
) -> dict:
    call = support_service.log_call(
        db,
        customer_id=customer_id,
        request_id=None,
        staff_id=staff.staff.id,
        direction=payload.direction,
        outcome=payload.outcome,
        duration_seconds=payload.duration_seconds,
        notes=payload.notes,
        next_follow_up_at=payload.next_follow_up_at,
    )
    db.commit()
    return {"id": str(call.id), "created_at": call.created_at}

