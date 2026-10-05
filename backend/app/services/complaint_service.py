"""Complaints, rework and quality control (§15)."""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta
from typing import Any

from sqlalchemy import Select, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.enums import (
    AuditAction,
    ComplaintStatus,
    NotificationType,
    RequestStatus,
)
from app.core.exceptions import ConflictError, NotFoundError, ValidationError
from app.core.logging import get_logger
from app.db.models.requests import ServiceRequest
from app.db.models.support import Complaint, ComplaintAttachment, ReworkVisit
from app.services import analytics_service, notification_service, request_service
from app.services.analytics_service import AnalyticsEventName
from app.services.audit_service import record_audit
from app.utils.pagination import generate_reference_code, offset_for
from app.utils.time import now_utc

log = get_logger(__name__)

SLA_HOURS = {
    ComplaintStatus.OPEN: 24,
    ComplaintStatus.UNDER_REVIEW: 48,
    ComplaintStatus.QC_REQUIRED: 48,
    ComplaintStatus.REVISIT_REQUIRED: 72,
}

#: Valid complaint transitions.
COMPLAINT_TRANSITIONS: dict[ComplaintStatus, frozenset[ComplaintStatus]] = {
    ComplaintStatus.OPEN: frozenset({ComplaintStatus.UNDER_REVIEW, ComplaintStatus.RESOLVED}),
    ComplaintStatus.UNDER_REVIEW: frozenset(
        {
            ComplaintStatus.QC_REQUIRED,
            ComplaintStatus.REVISIT_REQUIRED,
            ComplaintStatus.REVISIT_SCHEDULED,
            ComplaintStatus.RESOLVED,
        }
    ),
    ComplaintStatus.QC_REQUIRED: frozenset(
        {ComplaintStatus.REVISIT_REQUIRED, ComplaintStatus.RESOLVED}
    ),
    ComplaintStatus.REVISIT_REQUIRED: frozenset(
        {ComplaintStatus.REVISIT_SCHEDULED, ComplaintStatus.RESOLVED}
    ),
    ComplaintStatus.REVISIT_SCHEDULED: frozenset(
        {ComplaintStatus.REVISIT_SCHEDULED, ComplaintStatus.RESOLVED}
    ),
    ComplaintStatus.RESOLVED: frozenset({ComplaintStatus.CLOSED}),
    ComplaintStatus.CLOSED: frozenset(),
}


def create_complaint(
    session: Session,
    *,
    customer_id: uuid.UUID,
    request_id: uuid.UUID | None,
    reason: Any,
    description: str,
    idempotency_key: str | None,
) -> Complaint:
    request: ServiceRequest | None = None
    if request_id is not None:
        request = session.execute(
            select(ServiceRequest).where(
                ServiceRequest.id == request_id, ServiceRequest.customer_id == customer_id
            )
        ).scalar_one_or_none()
        if request is None:
            raise NotFoundError("Request not found.")

    if idempotency_key:
        existing = session.execute(
            select(Complaint).where(
                Complaint.customer_id == customer_id, Complaint.reference_code == idempotency_key
            )
        ).scalar_one_or_none()
        if existing is not None:
            return existing

    complaint = Complaint(
        request_id=request.id if request is not None else None,
        customer_id=customer_id,
        reference_code=generate_reference_code("CMP"),
        reason=reason,
        description=description.strip(),
        status=ComplaintStatus.OPEN,
        sla_due_at=now_utc() + timedelta(hours=SLA_HOURS[ComplaintStatus.OPEN]),
    )
    session.add(complaint)
    try:
        session.flush()
    except IntegrityError as exc:
        session.rollback()
        raise ConflictError(
            "This complaint was already submitted.", code="IDEMPOTENCY_CONFLICT"
        ) from exc

    if request is not None:
        request.has_complaint = True
        if request.status in {
            RequestStatus.WORK_IN_PROGRESS,
            RequestStatus.SERVICE_COMPLETED,
            RequestStatus.PAYMENT_PENDING,
            RequestStatus.PAYMENT_VERIFICATION,
            RequestStatus.PAID,
            RequestStatus.AWAITING_RATING,
        }:
            request_service.transition_request(
                session,
                request=request,
                target=RequestStatus.COMPLAINT_OPEN,
                actor_type="customer",
                actor_id=customer_id,
                event_type="COMPLAINT_OPENED",
                note_ar="تم استلام الشكوى وجارٍ مراجعتها",
            )
        else:
            request.has_complaint = True
        request_service.record_event(
            session,
            request_id=request.id,
            event_type="COMPLAINT_OPENED",
            actor_type="customer",
            actor_id=customer_id,
            payload={"complaint_id": str(complaint.id)},
        )
        notification_service.enqueue(
            session,
            customer_id=customer_id,
            request_id=request.id,
            type_=NotificationType.COMPLAINT_UPDATE,
            title_ar="تم استلام شكواك",
            body_ar="سنتواصل معك بعد مراجعة الشكوى.",
        )

    analytics_service.record_event(
        session,
        event_name=AnalyticsEventName.COMPLAINT_CREATED,
        customer_id=customer_id,
        request_id=request.id if request is not None else None,
        properties={"reason": str(reason)},
    )
    session.flush()
    return complaint


def add_attachment(
    session: Session,
    *,
    complaint: Complaint,
    customer_id: uuid.UUID,
    content: bytes,
    declared_mime: str | None,
    filename: str | None,
) -> ComplaintAttachment:
    from app.services.media_service import (
        build_complaint_attachment_path,
        make_storage_client,
        validate_image,
    )

    if complaint.customer_id != customer_id:
        raise NotFoundError("Complaint not found.")
    validated = validate_image(content, declared_mime=declared_mime, filename=filename)
    attachment_id = uuid.uuid4()
    path = build_complaint_attachment_path(
        customer_id=customer_id,
        complaint_id=complaint.id,
        extension=validated.extension,
        attachment_id=attachment_id,
    )
    make_storage_client().write(path, validated.content)
    attachment = ComplaintAttachment(
        id=attachment_id,
        complaint_id=complaint.id,
        storage_path=path,
        mime_type=validated.mime_type,
        size_bytes=validated.size_bytes,
        checksum_sha256=validated.checksum_sha256,
    )
    session.add(attachment)
    session.flush()
    return attachment


def transition(
    session: Session,
    *,
    complaint: Complaint,
    target: ComplaintStatus,
    staff_id: uuid.UUID,
    staff_role: str | None,
    note: str | None = None,
) -> Complaint:
    current = ComplaintStatus(complaint.status)
    if target not in COMPLAINT_TRANSITIONS.get(current, frozenset()):
        raise ConflictError(
            f"Cannot move a complaint from {current.value} to {target.value}.",
            code="INVALID_COMPLAINT_TRANSITION",
            details={"from": current.value, "to": target.value},
        )
    complaint.status = target
    if target == ComplaintStatus.RESOLVED:
        complaint.resolved_at = now_utc()
    if target == ComplaintStatus.CLOSED:
        complaint.closed_at = now_utc()
    complaint.sla_due_at = now_utc() + timedelta(
        hours=SLA_HOURS.get(target, 72)
    )
    if target in {ComplaintStatus.QC_REQUIRED, ComplaintStatus.REVISIT_REQUIRED}:
        complaint.requires_qc = True
    if target in {ComplaintStatus.REVISIT_REQUIRED, ComplaintStatus.REVISIT_SCHEDULED}:
        complaint.requires_rework = True

    if complaint.request_id is not None:
        request = session.get(ServiceRequest, complaint.request_id)
        if request is not None:
            request.has_rework = complaint.requires_rework
            if target == ComplaintStatus.REVISIT_SCHEDULED:
                request_service.transition_request(
                    session,
                    request=request,
                    target=RequestStatus.REVISIT_SCHEDULED,
                    actor_type="staff",
                    actor_id=staff_id,
                    actor_role=staff_role,
                    event_type="REVISIT_SCHEDULED",
                    note_ar=note,
                )
            request_service.record_event(
                session,
                request_id=request.id,
                event_type="COMPLAINT_UPDATE",
                actor_type="staff",
                actor_id=staff_id,
                actor_role=staff_role,
                payload={"complaint_id": str(complaint.id), "status": target.value},
            )
            notification_service.enqueue(
                session,
                customer_id=complaint.customer_id,
                request_id=request.id,
                type_=NotificationType.COMPLAINT_UPDATE,
                title_ar="تحديث على شكواك",
                body_ar=note or "تم تحديث حالة الشكوى.",
            )
    session.flush()
    return complaint


def assign_employee(
    session: Session, *, complaint: Complaint, employee_id: uuid.UUID, staff_id: uuid.UUID, staff_role: str | None
) -> Complaint:
    complaint.assigned_employee_id = employee_id
    if ComplaintStatus(complaint.status) == ComplaintStatus.OPEN:
        transition(
            session,
            complaint=complaint,
            target=ComplaintStatus.UNDER_REVIEW,
            staff_id=staff_id,
            staff_role=staff_role,
            note="تم إسناد الشكوى لموظف",
        )
    session.flush()
    return complaint


def resolve(
    session: Session,
    *,
    complaint: Complaint,
    staff_id: uuid.UUID,
    staff_role: str | None,
    resolution: str,
    requires_rework: bool,
    schedule_rework_at: datetime | None,
) -> Complaint:
    complaint.resolution = resolution.strip()
    if requires_rework:
        if schedule_rework_at is None:
            raise ValidationError("A rework date is required when rework is required.")
        transition(
            session,
            complaint=complaint,
            target=ComplaintStatus.REVISIT_SCHEDULED,
            staff_id=staff_id,
            staff_role=staff_role,
            note="تمت جدولة زيارة إصلاح",
        )
        session.add(
            ReworkVisit(
                complaint_id=complaint.id,
                request_id=complaint.request_id,
                scheduled_start=schedule_rework_at,
                status="PLANNED",
                waived_charge=True,
            )
        )
    else:
        transition(
            session,
            complaint=complaint,
            target=ComplaintStatus.RESOLVED,
            staff_id=staff_id,
            staff_role=staff_role,
            note=resolution[:400],
        )
    record_audit(
        session,
        action=AuditAction.COMPLAINT_RESOLUTION,
        entity="complaint",
        entity_id=complaint.id,
        actor_id=staff_id,
        actor_role=staff_role,
        after={"status": complaint.status.value, "requires_rework": requires_rework},
    )
    session.flush()
    return complaint


def get_for_customer(
    session: Session, *, complaint_id: uuid.UUID, customer_id: uuid.UUID
) -> Complaint:
    complaint = session.execute(
        select(Complaint).where(
            Complaint.id == complaint_id, Complaint.customer_id == customer_id
        )
    ).scalar_one_or_none()
    if complaint is None:
        raise NotFoundError("Complaint not found.")
    return complaint


def list_for_customer(
    session: Session, *, customer_id: uuid.UUID, page: int, per_page: int
) -> tuple[list[Complaint], int]:
    base = select(Complaint).where(Complaint.customer_id == customer_id)
    total = int(session.execute(select(func.count()).select_from(base.subquery())).scalar_one())
    rows = list(
        session.execute(
            base.order_by(Complaint.created_at.desc())
            .offset(offset_for(page, per_page))
            .limit(per_page)
        )
        .scalars()
    )
    return rows, total


def list_for_staff(
    session: Session,
    *,
    page: int,
    per_page: int,
    status: ComplaintStatus | None = None,
    assigned_to: uuid.UUID | None = None,
) -> tuple[list[Complaint], int]:
    base = select(Complaint)
    if status is not None:
        base = base.where(Complaint.status == status)
    if assigned_to is not None:
        base = base.where(Complaint.assigned_employee_id == assigned_to)
    total = int(session.execute(select(func.count()).select_from(base.subquery())).scalar_one())
    rows = list(
        session.execute(
            base.order_by(Complaint.created_at.desc())
            .offset(offset_for(page, per_page))
            .limit(per_page)
        )
        .scalars()
    )
    return rows, total


def open_complaints_stmt() -> Select[Complaint]:
    return select(Complaint).where(
        Complaint.status.in_(
            [
                ComplaintStatus.OPEN,
                ComplaintStatus.UNDER_REVIEW,
                ComplaintStatus.QC_REQUIRED,
                ComplaintStatus.REVISIT_REQUIRED,
                ComplaintStatus.REVISIT_SCHEDULED,
            ]
        )
    )
