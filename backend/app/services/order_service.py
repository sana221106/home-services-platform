"""Order execution, assignment and completion (§10, §11, §66, §125, §138).

Every mutation that changes money or assignment state runs inside an explicit
transaction with a row lock so concurrent operators cannot produce a split
brain (§138, §140).
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta
from decimal import Decimal
from typing import Any

from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.enums import (
    AssignmentStatus,
    AuditAction,
    CancellationReason,
    NotificationType,
    RequestStatus,
    Urgency,
)
from app.core.exceptions import ConflictError, NotFoundError, ValidationError
from app.core.logging import get_logger
from app.db.models.finance import Cancellation
from app.db.models.intelligence import MaintenanceRecord
from app.db.models.quotes import Quote
from app.db.models.requests import ServiceRequest
from app.db.models.support import Complaint
from app.db.models.workforce import Assignment, Technician
from app.schemas.orders import AssignTechnicianRequest
from app.services import (
    analytics_service,
    dispatch_service,
    notification_service,
    request_service,
)
from app.services.analytics_service import AnalyticsEventName
from app.services.audit_service import record_audit
from app.utils.time import now_utc

log = get_logger(__name__)

STATUS_BY_ASSIGNMENT: dict[AssignmentStatus, RequestStatus] = {
    AssignmentStatus.ASSIGNED: RequestStatus.TECHNICIAN_ASSIGNED,
    AssignmentStatus.EN_ROUTE: RequestStatus.ON_THE_WAY,
    AssignmentStatus.ARRIVED: RequestStatus.ARRIVED,
    AssignmentStatus.IN_PROGRESS: RequestStatus.WORK_IN_PROGRESS,
    AssignmentStatus.COMPLETED: RequestStatus.SERVICE_COMPLETED,
}

CANCELLABLE_STATUSES: frozenset[RequestStatus] = frozenset(
    {
        RequestStatus.DRAFT,
        RequestStatus.SUBMITTED,
        RequestStatus.UNDER_REVIEW,
        RequestStatus.NEED_MORE_INFORMATION,
        RequestStatus.INSPECTION_REQUIRED,
        RequestStatus.INSPECTION_SCHEDULED,
        RequestStatus.QUOTE_PREPARATION,
        RequestStatus.QUOTE_SENT,
        RequestStatus.AWAITING_CUSTOMER_APPROVAL,
        RequestStatus.DEPOSIT_PENDING,
        RequestStatus.DEPOSIT_VERIFICATION,
        RequestStatus.CONFIRMED,
        RequestStatus.TECHNICIAN_ASSIGNMENT_PENDING,
        RequestStatus.TECHNICIAN_ASSIGNED,
        RequestStatus.ON_THE_WAY,
        RequestStatus.ARRIVED,
    }
)


def assign_technician(
    session: Session,
    *,
    request: ServiceRequest,
    payload: AssignTechnicianRequest,
    staff_id: uuid.UUID,
    staff_role: str | None,
) -> Assignment:
    technician = dispatch_service.assert_assignable(
        session, request=request, technician_id=payload.technician_id
    )

    start = payload.expected_arrival_start
    end = payload.expected_arrival_end or (start + timedelta(minutes=120))

    if dispatch_service.is_technician_double_booked(
        session,
        technician_id=technician.id,
        start=start,
        end=end,
        exclude_request_id=request.id,
    ):
        raise ConflictError(
            "This technician already has an overlapping assignment in that window.",
            code="TECHNICIAN_DOUBLE_BOOKED",
        )

    previous = dispatch_service.find_assignment(session, request_id=request.id)
    if previous is not None:
        previous.is_current = False
        if previous.status in {
            AssignmentStatus.ASSIGNED,
            AssignmentStatus.EN_ROUTE,
            AssignmentStatus.ARRIVED,
            AssignmentStatus.IN_PROGRESS,
        }:
            previous.status = AssignmentStatus.CANCELLED
            previous.cancelled_reason = "Reassigned by operations"

    assignment = Assignment(
        request_id=request.id,
        technician_id=technician.id,
        assigned_by_id=staff_id,
        assigned_at=now_utc(),
        expected_arrival_start=start,
        expected_arrival_end=end,
        status=AssignmentStatus.ASSIGNED,
        is_current=True,
        internal_notes=payload.notes,
    )
    session.add(assignment)
    try:
        session.flush()
    except IntegrityError as exc:
        session.rollback()
        raise ConflictError(
            "The assignment conflicted with another update. Please retry.",
            code="ASSIGNMENT_CONFLICT",
        ) from exc

    technician.total_assignments += 1

    # The graph requires CONFIRMED -> TECHNICIAN_ASSIGNMENT_PENDING ->
    # TECHNICIAN_ASSIGNED (§62), so walk the intermediate state instead of
    # jumping straight to TECHNICIAN_ASSIGNED.
    if request.status == RequestStatus.CONFIRMED:
        request_service.transition_request(
            session,
            request=request,
            target=RequestStatus.TECHNICIAN_ASSIGNMENT_PENDING,
            actor_type="staff",
            actor_id=staff_id,
            actor_role=staff_role,
            event_type="TECHNICIAN_ASSIGNMENT_PENDING",
            note_ar="في انتظار تعيين الفني.",
        )

    request_service.transition_request(
        session,
        request=request,
        target=RequestStatus.TECHNICIAN_ASSIGNED,
        actor_type="staff",
        actor_id=staff_id,
        actor_role=staff_role,
        event_type="TECHNICIAN_ASSIGNED",
        note_ar=(
            "تم تعيين الفني. الموعد المتوقع: "
            f"{dispatch_service.time_window_label(start, end)}"
        ),
        payload={
            "assignment_id": str(assignment.id),
            "expected_arrival_start": start.isoformat(),
            "expected_arrival_end": end.isoformat(),
        },
    )
    request_service.record_event(
        session,
        request_id=request.id,
        event_type="EXPECTED_ARRIVAL_UPDATED",
        actor_type="staff",
        actor_id=staff_id,
        actor_role=staff_role,
        payload={
            "start": start.isoformat(),
            "end": end.isoformat(),
            "label": dispatch_service.time_window_label(start, end),
        },
    )

    record_audit(
        session,
        action=AuditAction.TECHNICIAN_ASSIGNMENT,
        entity="assignment",
        entity_id=assignment.id,
        actor_id=staff_id,
        actor_role=staff_role,
        before={"technician_id": str(previous.technician_id)} if previous else None,
        after={
            "technician_id": str(technician.id),
            "expected_arrival_start": start.isoformat(),
            "expected_arrival_end": end.isoformat(),
        },
    )
    analytics_service.record_event(
        session,
        event_name=AnalyticsEventName.TECHNICIAN_ASSIGNED,
        customer_id=request.customer_id,
        request_id=request.id,
    )
    notification_service.enqueue(
        session,
        customer_id=request.customer_id,
        request_id=request.id,
        type_=NotificationType.TECHNICIAN_ASSIGNED,
        title_ar="تم تعيين الفني",
        body_ar="تم تأكيد موعد الزيارة. ستصلك تحديثات الموعد المتوقع قبل الوصول.",
    )
    session.flush()
    return assignment


def update_assignment_status(
    session: Session,
    *,
    assignment: Assignment,
    target: AssignmentStatus,
    staff_id: uuid.UUID,
    staff_role: str | None,
    note_ar: str | None = None,
) -> Assignment:
    request = session.get(ServiceRequest, assignment.request_id)
    if request is None:
        raise NotFoundError("Request not found.")

    previous = assignment.status
    if previous == AssignmentStatus.COMPLETED and target != AssignmentStatus.CANCELLED:
        raise ConflictError("This assignment is already closed.", code="ASSIGNMENT_CLOSED")

    now = now_utc()
    assignment.status = target

    if target == AssignmentStatus.ARRIVED:
        assignment.actual_arrival = now
        technician = session.get(Technician, assignment.technician_id)
        if technician is not None and assignment.expected_arrival_end is not None:
            if assignment.expected_arrival_end < now:
                technician.late_arrivals += 1
    if target == AssignmentStatus.IN_PROGRESS:
        assignment.work_started_at = now
    if target == AssignmentStatus.COMPLETED:
        assignment.work_completed_at = now
        technician = session.get(Technician, assignment.technician_id)
        if technician is not None:
            technician.completed_assignments += 1

    new_request_status = STATUS_BY_ASSIGNMENT.get(target)
    if new_request_status is not None:
        request_service.transition_request(
            session,
            request=request,
            target=new_request_status,
            actor_type="staff",
            actor_id=staff_id,
            actor_role=staff_role,
            event_type={
                AssignmentStatus.EN_ROUTE: "ON_THE_WAY",
                AssignmentStatus.ARRIVED: "ARRIVED",
                AssignmentStatus.IN_PROGRESS: "SERVICE_STARTED",
                AssignmentStatus.COMPLETED: "SERVICE_COMPLETED",
            }.get(target, "ASSIGNMENT_UPDATED"),
            note_ar=note_ar,
        )
        if target == AssignmentStatus.COMPLETED:
            request.completed_at = now
            _write_maintenance_record(session, request=request, assignment=assignment)

    if target == AssignmentStatus.EN_ROUTE:
        notification_service.enqueue(
            session,
            customer_id=request.customer_id,
            request_id=request.id,
            type_=NotificationType.ON_THE_WAY,
            title_ar="الفني في الطريق",
            body_ar="الفني متجه إلى موقع الخدمة.",
        )
    elif target == AssignmentStatus.COMPLETED:
        notification_service.enqueue(
            session,
            customer_id=request.customer_id,
            request_id=request.id,
            type_=NotificationType.SERVICE_COMPLETED,
            title_ar="تم إنجاز الخدمة",
            body_ar="تم إنهاء العمل. يمكنك متابعة الدفع والتقييم.",
        )

    analytics_service.record_event(
        session,
        event_name=AnalyticsEventName.SERVICE_STARTED
        if target == AssignmentStatus.IN_PROGRESS
        else AnalyticsEventName.ORDER_COMPLETED
        if target == AssignmentStatus.COMPLETED
        else "ASSIGNMENT_UPDATED",
        customer_id=request.customer_id,
        request_id=request.id,
        properties={"assignment_status": target.value},
    )
    session.flush()
    return assignment


def _write_maintenance_record(
    session: Session, *, request: ServiceRequest, assignment: Assignment
) -> MaintenanceRecord:
    """Property maintenance health record (§17). Writes once per request; the
    unique constraint on ``request_id`` makes a replay a no-op-safe error."""
    from app.db.models.catalog import ProblemType, ServiceCategory
    from app.db.models.quotes import Quote as QuoteModel

    existing = session.execute(
        select(MaintenanceRecord).where(MaintenanceRecord.request_id == request.id)
    ).scalar_one_or_none()
    if existing is not None:
        return existing

    category = session.get(ServiceCategory, request.category_id)
    problem = (
        session.get(ProblemType, request.problem_type_id) if request.problem_type_id else None
    )
    quote = session.execute(
        select(QuoteModel)
        .where(QuoteModel.request_id == request.id, QuoteModel.status == "ACCEPTED")
        .order_by(QuoteModel.revision_number.desc())
        .limit(1)
    ).scalar_one_or_none()

    had_complaint = bool(
        session.execute(
            select(Complaint.id).where(Complaint.request_id == request.id).limit(1)
        ).scalar_one_or_none()
    )

    group_key = f"{request.property_id}:{request.category_id}:{problem.code if problem else 'general'}"
    occurrence = int(
        session.execute(
            select(MaintenanceRecord.id).where(MaintenanceRecord.recurrence_group_key == group_key)
        ).rowcount
        or 0
    )

    media_paths = [
        media.storage_path
        for media in request.media
        if getattr(media, "deleted_at", None) is None
    ]

    record = MaintenanceRecord(
        property_id=request.property_id,
        request_id=request.id,
        customer_id=request.customer_id,
        category_code=category.code if category else "unknown",
        problem_code=problem.code if problem else None,
        customer_description=request.problem_description,
        price=quote.total if quote is not None else None,
        technician_id=assignment.technician_id,
        media_references=media_paths,
        had_complaint=had_complaint,
        had_rework=request.has_rework,
        is_completed=True,
        served_on=now_utc(),
        recurrence_group_key=group_key,
        recurrence_index=occurrence + 1,
        diagnosis=None,
        resolution=None,
    )
    session.add(record)
    session.flush()
    return record


def mark_no_show(
    session: Session,
    *,
    assignment: Assignment,
    staff_id: uuid.UUID,
    staff_role: str | None,
) -> Assignment:
    technician = session.get(Technician, assignment.technician_id)
    if technician is not None:
        technician.no_show_count += 1
    return update_assignment_status(
        session,
        assignment=assignment,
        target=AssignmentStatus.NO_SHOW,
        staff_id=staff_id,
        staff_role=staff_role,
        note_ar="تعذر وصول الفني في الموعد المحدد.",
    )


def cancel_request(
    session: Session,
    *,
    request: ServiceRequest,
    reason: CancellationReason,
    reason_note: str | None,
    actor_id: uuid.UUID | None,
    actor_role: str | None,
    actor_type: str,
    discount: Decimal = Decimal("0"),
    requires_approval: bool = False,
) -> Cancellation:
    """§11 — delay/no-show lets the customer cancel; any discount is applied by
    staff, never decided by the client."""
    if request.status not in CANCELLABLE_STATUSES:
        raise ConflictError(
            "This request can no longer be cancelled online.",
            code="NOT_CANCELLABLE",
            details={"status": request.status.value},
        )

    assignment = dispatch_service.find_assignment(session, request_id=request.id)
    if assignment is not None:
        assignment.is_current = False
        assignment.status = AssignmentStatus.CANCELLED
        assignment.cancelled_reason = reason_note or reason.value

    session.execute(
        update(Assignment)
        .where(Assignment.request_id == request.id, Assignment.is_current.is_(True))
        .values(is_current=False, status=AssignmentStatus.CANCELLED)
    )

    cancellation = Cancellation(
        request_id=request.id,
        reason=reason,
        reason_note=reason_note,
        cancelled_by_id=actor_id,
        cancelled_at=now_utc(),
        approved_by_id=actor_id if requires_approval else None,
        discount_applied=discount,
    )
    session.add(cancellation)
    session.flush()

    request_service.transition_request(
        session,
        request=request,
        target=RequestStatus.CANCELLED,
        actor_type=actor_type,
        actor_id=actor_id,
        actor_role=actor_role,
        event_type="CANCELLED",
        note_ar=reason_note,
        payload={"reason": reason.value, "discount": str(discount)},
    )
    request.cancelled_at = now_utc()
    notification_service.enqueue(
        session,
        customer_id=request.customer_id,
        request_id=request.id,
        type_=NotificationType.COMPLAINT_UPDATE,
        title_ar="تم إلغاء الطلب",
        body_ar="تم إلغاء طلبك.如有 استفسار تواصل مع خدمة العملاء.".replace("如有 ", ""),    )
    session.flush()
    return cancellation


def can_customer_rate(session: Session, *, request: ServiceRequest) -> bool:
    return request.status in {RequestStatus.PAID, RequestStatus.AWAITING_RATING}


def can_customer_complain(session: Session, *, request: ServiceRequest) -> bool:
    return request.status in {
        RequestStatus.WORK_IN_PROGRESS,
        RequestStatus.SERVICE_COMPLETED,
        RequestStatus.PAYMENT_PENDING,
        RequestStatus.PAYMENT_VERIFICATION,
        RequestStatus.PAID,
        RequestStatus.AWAITING_RATING,
        RequestStatus.CLOSED,
    }


def current_assignment_summary(request: ServiceRequest) -> dict[str, Any] | None:
    current = [a for a in request.assignments if a.is_current]
    if not current:
        return None
    assignment = current[0]
    return {
        "assignment_id": str(assignment.id),
        "expected_arrival_start": assignment.expected_arrival_start,
        "expected_arrival_end": assignment.expected_arrival_end,
    }


def mark_rating_prompted(session: Session, *, request: ServiceRequest) -> None:
    if request.status == RequestStatus.PAID:
        request_service.transition_request(
            session,
            request=request,
            target=RequestStatus.AWAITING_RATING,
            actor_type="system",
            event_type="RATING_REMINDER",
            note_ar="قيّم تجربتك معنا",
        )
        notification_service.enqueue(
            session,
            customer_id=request.customer_id,
            request_id=request.id,
            type_=NotificationType.RATING_REMINDER,
            title_ar="قيّم خدماتنا",
            body_ar="شاركنا تقييمك لآخر خدمة.",
        )
        session.flush()


def urgency_label(urgency: Urgency) -> str:
    return "عاجل" if urgency == Urgency.URGENT else "عادي"
