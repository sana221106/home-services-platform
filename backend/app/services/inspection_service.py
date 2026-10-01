"""Inspection-only flow (§7).

Inspection is a separate paid service. The technician records the diagnosis;
the platform still determines the final price through Operations, never through
customer or technician negotiation.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.enums import AuditAction, InspectionStatus, NotificationType, RequestStatus
from app.core.exceptions import ConflictError, NotFoundError
from app.db.models.requests import Inspection, InspectionReport, ServiceRequest
from app.services import notification_service, request_service
from app.services.audit_service import record_audit
from app.utils.time import now_utc


def get_inspection(session: Session, *, request_id: uuid.UUID) -> Inspection | None:
    return session.execute(
        select(Inspection).where(Inspection.request_id == request_id)
    ).scalar_one_or_none()


def get_inspection_report(session: Session, *, inspection_id: uuid.UUID) -> InspectionReport | None:
    return session.execute(
        select(InspectionReport).where(InspectionReport.inspection_id == inspection_id)
    ).scalar_one_or_none()


def schedule(
    session: Session,
    *,
    request: ServiceRequest,
    staff_id: uuid.UUID,
    staff_role: str | None,
    scheduled_start: datetime,
    scheduled_end: datetime | None,
    technician_id: uuid.UUID | None,
    fee: Decimal | None,
) -> Inspection:
    inspection = get_inspection(session, request_id=request.id)
    if inspection is not None and inspection.status == InspectionStatus.COMPLETED:
        raise ConflictError("This inspection is already complete.", code="INSPECTION_COMPLETED")

    if inspection is None:
        inspection = Inspection(
            request_id=request.id,
            status=InspectionStatus.PENDING,
            fee=fee,
        )
        session.add(inspection)
        session.flush()

    inspection.status = InspectionStatus.SCHEDULED
    inspection.scheduled_start = scheduled_start
    inspection.scheduled_end = scheduled_end
    inspection.assigned_technician_id = technician_id
    inspection.fee = fee if fee is not None else inspection.fee
    request.inspection_status = InspectionStatus.SCHEDULED

    request_service.transition_request(
        session,
        request=request,
        target=RequestStatus.INSPECTION_SCHEDULED,
        actor_type="staff",
        actor_id=staff_id,
        actor_role=staff_role,
        event_type="INSPECTION_SCHEDULED",
        note_ar="تم تحديد موعد الفحص الفني",
    )
    notification_service.enqueue(
        session,
        customer_id=request.customer_id,
        request_id=request.id,
        type_=NotificationType.APPOINTMENT_SCHEDULED,
        title_ar="تم تأكيد موعد الفحص",
        body_ar="سيتم إجراء الفحص الفني في الموعد المحدد.",
    )
    session.flush()
    return inspection


def start(
    session: Session, *, inspection: Inspection, request: ServiceRequest, staff_id: uuid.UUID, staff_role: str | None
) -> Inspection:
    if inspection.status != InspectionStatus.SCHEDULED:
        raise ConflictError(
            "Only a scheduled inspection can be started.", code="INVALID_INSPECTION_STATE"
        )
    inspection.status = InspectionStatus.IN_PROGRESS
    inspection.started_at = now_utc()
    request.inspection_status = InspectionStatus.IN_PROGRESS
    request_service.transition_request(
        session,
        request=request,
        target=RequestStatus.INSPECTION_IN_PROGRESS,
        actor_type="staff",
        actor_id=staff_id,
        actor_role=staff_role,
        event_type="INSPECTION_STARTED",
        note_ar="بدأ الفحص الفني",
    )
    session.flush()
    return inspection


def complete(
    session: Session,
    *,
    inspection: Inspection,
    request: ServiceRequest,
    staff_id: uuid.UUID,
    staff_role: str | None,
    diagnosis: str,
    problem_description: str | None,
    required_work: str | None,
    required_materials: str | None,
    estimated_duration_minutes: int | None,
    proposed_price: Decimal | None,
    internal_notes: str | None,
    media_references: list | None = None,
) -> InspectionReport:
    if inspection.status not in {
        InspectionStatus.IN_PROGRESS,
        InspectionStatus.SCHEDULED,
    }:
        raise ConflictError(
            "This inspection cannot be completed in its current state.",
            code="INVALID_INSPECTION_STATE",
        )

    inspection.status = InspectionStatus.COMPLETED
    inspection.completed_at = now_utc()
    request.inspection_status = InspectionStatus.COMPLETED
    if estimated_duration_minutes is None:
        estimated_duration_minutes = 120

    report = get_inspection_report(session, inspection_id=inspection.id)
    if report is None:
        report = InspectionReport(inspection_id=inspection.id, diagnosis=diagnosis)
        session.add(report)
    report.diagnosis = diagnosis
    report.problem_description = problem_description
    report.required_work = required_work
    report.required_materials = required_materials
    report.estimated_duration_minutes = estimated_duration_minutes
    report.proposed_price = proposed_price
    report.internal_notes = internal_notes
    report.media_references = media_references or []
    report.completed_by_id = staff_id
    session.flush()

    request_service.transition_request(
        session,
        request=request,
        target=RequestStatus.INSPECTION_COMPLETED,
        actor_type="staff",
        actor_id=staff_id,
        actor_role=staff_role,
        event_type="INSPECTION_COMPLETED",
        note_ar="انتهى الفحص الفني وسيتم إرسال عرض السعر",
        payload={"proposed_price": str(proposed_price) if proposed_price else None},
    )
    record_audit(
        session,
        action=AuditAction.QUOTE_CREATED,
        entity="inspection",
        entity_id=inspection.id,
        actor_id=staff_id,
        actor_role=staff_role,
        after={
            "diagnosis_present": bool(diagnosis),
            "proposed_price": str(proposed_price) if proposed_price is not None else None,
        },
    )
    session.flush()
    return report


def qc_review(
    session: Session,
    *,
    inspection: Inspection,
    staff_id: uuid.UUID,
    staff_role: str | None,
    qc_passed: bool,
    notes: str | None,
) -> InspectionReport:
    report = get_inspection_report(session, inspection_id=inspection.id)
    if report is None:
        raise NotFoundError("Inspection report not found.")
    report.qc_passed = qc_passed
    report.qc_reviewed_by_id = staff_id
    report.qc_reviewed_at = now_utc()
    report.internal_notes = "\n".join(filter(None, [report.internal_notes, notes]))
    session.flush()
    return report


def cancel(session: Session, *, inspection: Inspection) -> Inspection:
    if inspection.status == InspectionStatus.COMPLETED:
        raise ConflictError("A completed inspection cannot be cancelled.")
    inspection.status = InspectionStatus.CANCELLED
    session.flush()
    return inspection


def ensure_inspection_fee(
    session: Session, *, request: ServiceRequest, fee: Decimal
) -> Inspection:
    inspection = get_inspection(session, request_id=request.id)
    if inspection is None:
        inspection = Inspection(
            request_id=request.id, status=InspectionStatus.PENDING, fee=fee
        )
        session.add(inspection)
    else:
        inspection.fee = fee
    session.flush()
    return inspection

