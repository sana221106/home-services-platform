"""Operations endpoints: request review, quoting, dispatch, inspections (§71-§73)."""

from __future__ import annotations

import uuid
from datetime import timedelta
from decimal import Decimal
from typing import Annotated

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select

from app.api.dependencies import AuthenticatedStaff, DbSession, require
from app.core.enums import (
    AssignmentStatus,
    CancellationReason,
    Permission,
    RequestStatus,
    Urgency,
)
from app.core.labels import REQUEST_STATUS_LABELS
from app.db.models.catalog import ProblemType, ServiceCategory
from app.db.models.identity import CustomerProfile
from app.db.models.properties import Property
from app.db.models.support import Complaint, StaffNote
from app.db.models.workforce import Assignment, Technician
from app.schemas.admin import (
    AdminCancelRequest,
    AdminInspectionCompleteRequest,
    AdminInspectionScheduleRequest,
    AdminQcReviewRequest,
    AdminRequestDetail,
    AdminRequestListItem,
    AdminStartReviewRequest,
    AdminStatusChangeRequest,
    AiClassifyRequestRequest,
    AiClassifyResponse,
    AiReviewDecisionRequest,
    QuoteResponse,
)
from app.schemas.common import MessageResponse, Page
from app.schemas.orders import (
    AssignmentResponse,
    AssignTechnicianRequest,
    DispatchCandidatesResponse,
    TechnicianCandidate,
)
from app.schemas.requests import CreateQuoteRequest, RequestMediaResponse
from app.services import (
    ai_service,
    audit_service,
    inspection_service,
    order_service,
    payment_service,
    pricing_service,
    quote_service,
    request_service,
)
from app.utils.time import age_minutes, now_utc

router = APIRouter(prefix="/staff/requests", tags=["staff-requests"])

OpsGuard = Annotated[AuthenticatedStaff, Depends(require(Permission.REQUEST_READ))]
WriteGuard = Annotated[AuthenticatedStaff, Depends(require(Permission.REQUEST_REVIEW))]


def _list_item(db: DbSession, request, *, technician_name: str | None = None):  # noqa: ANN001, ANN202
    category = db.get(ServiceCategory, request.category_id)
    problem = db.get(ProblemType, request.problem_type_id) if request.problem_type_id else None
    prop = db.get(Property, request.property_id)
    customer = db.get(CustomerProfile, request.customer_id)
    quote = quote_service.current_quote(db, request_id=request.id)
    sla_age = None
    if request.submitted_at is not None:
        sla_age = age_minutes(request.submitted_at)
    return AdminRequestListItem(
        id=request.id,
        reference_code=request.reference_code,
        status=RequestStatus(request.status),
        urgency=request.urgency,
        inspection_only=request.inspection_only,
        inspection_required=request.inspection_required,
        category_name_ar=category.name_ar if category else "",
        problem_name_ar=problem.name_ar if problem else None,
        property_label=prop.label if prop else "",
        customer_name=customer.full_name if customer else "",
        customer_phone=customer.user.phone if customer and customer.user else "",
        created_at=request.created_at,
        submitted_at=request.submitted_at,
        sla_age_minutes=sla_age,
        current_quote_total=quote.total if quote else None,
        assigned_technician_name=technician_name,
    )


def _technician_name(db: DbSession, request_id: uuid.UUID) -> str | None:
    return db.execute(
        select(Technician.name)
        .join(Assignment, Assignment.technician_id == Technician.id)
        .where(Assignment.request_id == request_id, Assignment.is_current.is_(True))
        .limit(1)
    ).scalar_one_or_none()


@router.get("", response_model=Page[AdminRequestListItem], summary="Operations queue")
def list_requests(
    db: DbSession,
    _staff: OpsGuard,
    page: int = Query(default=1, ge=1),
    per_page: int = Query(default=25, ge=1, le=100),
    status: RequestStatus | None = Query(default=None),
    urgency: Urgency | None = Query(default=None),
    category_id: uuid.UUID | None = Query(default=None),
    zone_id: uuid.UUID | None = Query(default=None),
    search: str | None = Query(default=None, max_length=64),
) -> Page[AdminRequestListItem]:
    rows, total = request_service.list_requests_for_staff(
        db,
        page=page,
        per_page=per_page,
        status=status,
        urgency=urgency,
        zone_id=zone_id,
        category_id=category_id,
        search=search,
    )
    items = [
        _list_item(db, row, technician_name=_technician_name(db, row.id)) for row in rows
    ]
    return Page[AdminRequestListItem].build(
        items=items, total=total, page=page, per_page=per_page
    )


@router.get(
    "/{request_id}",
    response_model=AdminRequestDetail,
    summary="Full operations view of a request",
)
def get_request(
    request_id: uuid.UUID, db: DbSession, _staff: OpsGuard
) -> AdminRequestDetail:
    request = request_service.get_request_for_staff(db, request_id=request_id)
    base = _list_item(db, request, technician_name=_technician_name(db, request.id))
    urls = request_service.media_urls(db, media=list(request.media))
    snapshot = request.address_snapshot

    address = None
    if snapshot is not None:
        address = {
            "governorate": snapshot.governorate,
            "city": snapshot.city,
            "zone": snapshot.zone,
            "district": snapshot.district,
            "street": snapshot.street,
            "building": snapshot.building,
            "floor": snapshot.floor,
            "apartment": snapshot.apartment,
            "landmark": snapshot.landmark,
            "notes": snapshot.notes,
            "latitude": snapshot.latitude,
            "longitude": snapshot.longitude,
            "contact_name": snapshot.contact_name,
            "contact_phone": snapshot.contact_phone,
        }

    quotes = [QuoteResponse.model_validate(quote) for quote in request.quotes]
    current = quote_service.current_quote(db, request_id=request.id)
    assignments = []
    for assignment in request.assignments:
        technician = db.get(Technician, assignment.technician_id)
        assignments.append(
            AssignmentResponse(
                id=assignment.id,
                request_id=assignment.request_id,
                technician_id=assignment.technician_id,
                technician_name=technician.name if technician else "",
                assigned_at=assignment.assigned_at,
                expected_arrival_start=assignment.expected_arrival_start,
                expected_arrival_end=assignment.expected_arrival_end,
                actual_arrival=assignment.actual_arrival,
                work_started_at=assignment.work_started_at,
                work_completed_at=assignment.work_completed_at,
                status=assignment.status,
                cancelled_reason=assignment.cancelled_reason,
            )
        )
    complaint = db.execute(
        select(Complaint).where(Complaint.request_id == request.id)
    ).scalar_one_or_none()
    payments = list(
        payment_service.payments_for_request(db, request_id=request.id)
    )
    notes = list(
        db.execute(select(StaffNote).where(StaffNote.request_id == request.id)).scalars()
    )
    ai_row = ai_service.latest_for_request(db, request_id=request.id)

    from app.schemas.admin import AiSuggestionSummary
    from app.schemas.finance import PaymentSummaryResponse
    from app.schemas.support import ComplaintResponse

    return AdminRequestDetail(
        **base.model_dump(),
        problem_description=request.problem_description,
        customer_notes=request.customer_notes,
        address=address,
        media=[
            RequestMediaResponse(
                id=item.id,
                kind=item.kind,
                mime_type=item.mime_type,
                size_bytes=item.size_bytes,
                width=item.width,
                height=item.height,
                sort_order=item.sort_order,
                url=urls.get(item.id),
                created_at=item.created_at,
            )
            for item in request.media
            if item.deleted_at is None
        ],
        quotes=quotes,
        current_quote=QuoteResponse.model_validate(current) if current else None,
        assignments=assignments,
        complaint=ComplaintResponse.model_validate(complaint) if complaint else None,
        payments=[PaymentSummaryResponse.model_validate(p) for p in payments],
        internal_notes=[note.body for note in notes],
        ai_suggestion=AiSuggestionSummary.model_validate(ai_row) if ai_row else None,
        funnels={
            "status_label_ar": REQUEST_STATUS_LABELS.get(
                RequestStatus(request.status), ""
            )
        },
    )


@router.post(
    "/{request_id}/review",
    response_model=MessageResponse,
    summary="Start reviewing a submitted request",
)
def start_review(
    request_id: uuid.UUID,
    payload: AdminStartReviewRequest,
    db: DbSession,
    staff: WriteGuard,
) -> MessageResponse:
    request = request_service.get_request_for_staff(db, request_id=request_id)
    request_service.transition_request(
        db,
        request=request,
        target=RequestStatus.UNDER_REVIEW,
        actor_type="staff",
        actor_id=staff.staff.id,
        actor_role=staff.roles[0] if staff.roles else None,
        note_ar=payload.note,
    )
    audit_service.record_audit(
        db,
        actor_id=staff.staff.id,
        actor_role=staff.roles[0] if staff.roles else None,
        action="REQUEST_REVIEW_STARTED",
        entity="service_request",
        entity_id=request.id,
        after={"status": request.status},
    )
    db.commit()
    return MessageResponse(message="تم بدء مراجعة الطلب.")


@router.post(
    "/{request_id}/status",
    response_model=AdminRequestListItem,
    summary="Explicit status change (validated graph, audited)",
)
def change_status(
    request_id: uuid.UUID,
    payload: AdminStatusChangeRequest,
    db: DbSession,
    staff: WriteGuard,
) -> AdminRequestListItem:
    request = request_service.get_request_for_staff(db, request_id=request_id)
    before = request.status
    request_service.transition_request(
        db,
        request=request,
        target=payload.status,
        actor_type="staff",
        actor_id=staff.staff.id,
        actor_role=staff.roles[0] if staff.roles else None,
        note_ar=payload.reason,
        force=payload.force,
    )
    audit_service.record_audit(
        db,
        actor_id=staff.staff.id,
        actor_role=staff.roles[0] if staff.roles else None,
        action="REQUEST_STATUS_CHANGED",
        entity="service_request",
        entity_id=request.id,
        before={"status": before},
        after={"status": request.status, "forced": payload.force},
    )
    db.commit()
    return _list_item(db, request)


@router.post(
    "/{request_id}/cancel",
    response_model=AdminRequestListItem,
    summary="Cancel with a policy reason (never a free-text guess)",
)
def cancel_request(
    request_id: uuid.UUID,
    payload: AdminCancelRequest,
    db: DbSession,
    staff: WriteGuard,
) -> AdminRequestListItem:
    request = request_service.get_request_for_staff(db, request_id=request_id)
    reason = _resolve_cancellation_reason(payload.reason)
    order_service.cancel_request(
        db,
        request=request,
        reason=reason,
        reason_note=payload.reason_note,
        actor_id=staff.staff.id,
        actor_role=staff.roles[0] if staff.roles else None,
        actor_type="staff",
        discount=payload.apply_discount,
    )
    audit_service.record_audit(
        db,
        actor_id=staff.staff.id,
        actor_role=staff.roles[0] if staff.roles else None,
        action="REQUEST_CANCELLED",
        entity="service_request",
        entity_id=request.id,
        after={"reason": reason.value, "discount": str(payload.apply_discount)},
    )
    db.commit()
    return _list_item(db, request)


def _resolve_cancellation_reason(text: str) -> CancellationReason:
    mapping = {
        "customer": CancellationReason.CUSTOMER_REQUEST,
        "no_show": CancellationReason.NO_SHOW,
        "technician": CancellationReason.TECHNICIAN_UNAVAILABLE,
        "coverage": CancellationReason.OUT_OF_COVERAGE,
        "policy": CancellationReason.POLICY_VIOLATION,
        "other": CancellationReason.OTHER,
    }
    key = text.strip().lower()
    if key not in mapping:
        raise ValueError(f"Unsupported cancellation reason: {text}")
    return mapping[key]


# ----------------------------------------------------------------- quotations


@router.get(
    "/{request_id}/quotes",
    response_model=list[QuoteResponse],
    summary="All quote revisions",
)
def list_quotes(
    request_id: uuid.UUID, db: DbSession, staff: OpsGuard
) -> list[QuoteResponse]:
    request_service.get_request_for_staff(db, request_id=request_id)
    return [
        QuoteResponse.model_validate(quote)
        for quote in quote_service.all_revisions(db, request_id=request_id)
    ]


@router.post(
    "/{request_id}/quotes",
    response_model=QuoteResponse,
    status_code=201,
    summary="Create a quote revision (server recomputes totals)",
)
def create_quote(
    request_id: uuid.UUID,
    payload: CreateQuoteRequest,
    db: DbSession,
    staff: WriteGuard,
) -> QuoteResponse:
    request = request_service.get_request_for_staff(db, request_id=request_id)
    zone_id = _zone_id(db, request.id)
    rule = pricing_service.resolve_pricing_rule(
        db,
        category_id=request.category_id,
        problem_type_id=request.problem_type_id,
        zone_id=zone_id,
        at=now_utc(),
    )
    deposit_percent = rule.deposit_percent if rule else Decimal("0")
    quote = quote_service.create_quote(
        db,
        request=request,
        payload=payload,
        staff_id=staff.staff.id,
        staff_role=staff.roles[0] if staff.roles else None,
        deposit_percent=deposit_percent,
    )
    audit_service.record_audit(
        db,
        actor_id=staff.staff.id,
        actor_role=staff.roles[0] if staff.roles else None,
        action="QUOTE_CREATED",
        entity="quote",
        entity_id=quote.id,
        after={"revision": quote.revision_number, "total": str(quote.total)},
    )
    db.commit()
    return QuoteResponse.model_validate(quote)


def _zone_id(db: DbSession, request_id: uuid.UUID) -> uuid.UUID | None:
    from app.db.models.catalog import ServiceAreaSnapshot

    return db.execute(
        select(ServiceAreaSnapshot.zone_id).where(
            ServiceAreaSnapshot.request_id == request_id
        )
    ).scalar_one_or_none()


# ------------------------------------------------------------------- dispatch


@router.get(
    "/{request_id}/dispatch-candidates",
    response_model=DispatchCandidatesResponse,
    summary="Ranked technician candidates",
)
def dispatch_candidates(
    request_id: uuid.UUID, db: DbSession, staff: OpsGuard
) -> DispatchCandidatesResponse:
    from app.services import dispatch_service

    request = request_service.get_request_for_staff(db, request_id=request_id)
    target = now_utc() + timedelta(hours=24)
    if request.preferred_date is not None:
        target = request.preferred_date
    scored = dispatch_service.score_candidates(
        db, request=request, target_start=target, limit=10
    )
    return DispatchCandidatesResponse(
        request_id=request.id,
        required_skill_category_id=request.category_id,
        required_zone_id=_zone_id(db, request.id),
        candidates=[
            TechnicianCandidate(
                id=row["id"],
                name=row["name"],
                active=row["active"],
                status=row["status"],
                matched_skills=[str(item) for item in row["matched_skills"]],
                matched_zones=[str(item) for item in row["matched_zones"]],
                current_workload=row["current_workload"],
                next_free_at=row["next_free_at"],
                is_available=row["is_available"],
                score=row["score"],
            )
            for row in scored
        ],
    )


@router.post(
    "/{request_id}/assign",
    response_model=AssignmentResponse,
    status_code=201,
    summary="Assign a technician with double-booking protection",
)
def assign_technician(
    request_id: uuid.UUID,
    payload: AssignTechnicianRequest,
    db: DbSession,
    staff: WriteGuard,
) -> AssignmentResponse:
    request = request_service.get_request_for_staff(db, request_id=request_id)
    assignment = order_service.assign_technician(
        db,
        request=request,
        payload=payload,
        staff_id=staff.staff.id,
        staff_role=staff.roles[0] if staff.roles else None,
    )
    audit_service.record_audit(
        db,
        actor_id=staff.staff.id,
        actor_role=staff.roles[0] if staff.roles else None,
        action="TECHNICIAN_ASSIGNED",
        entity="assignment",
        entity_id=assignment.id,
        after={"technician_id": str(payload.technician_id)},
    )
    db.commit()
    technician = db.get(Technician, assignment.technician_id)
    return AssignmentResponse(
        id=assignment.id,
        request_id=assignment.request_id,
        technician_id=assignment.technician_id,
        technician_name=technician.name if technician else "",
        assigned_at=assignment.assigned_at,
        expected_arrival_start=assignment.expected_arrival_start,
        expected_arrival_end=assignment.expected_arrival_end,
        actual_arrival=assignment.actual_arrival,
        work_started_at=assignment.work_started_at,
        work_completed_at=assignment.work_completed_at,
        status=assignment.status,
        cancelled_reason=assignment.cancelled_reason,
    )


@router.post(
    "/{request_id}/assignment-status",
    response_model=AssignmentResponse,
    summary="Advance the assignment lifecycle",
)
def update_assignment_status(
    request_id: uuid.UUID,
    payload: dict,
    db: DbSession,
    staff: WriteGuard,
) -> AssignmentResponse:
    from app.services import dispatch_service

    request = request_service.get_request_for_staff(db, request_id=request_id)
    assignment = dispatch_service.find_assignment(db, request_id=request.id)
    if assignment is None:
        from app.core.exceptions import NotFoundError

        raise NotFoundError("No assignment exists for this request.")
    target = AssignmentStatus(payload["status"])
    updated = order_service.update_assignment_status(
        db,
        assignment=assignment,
        target=target,
        staff_id=staff.staff.id,
        staff_role=staff.roles[0] if staff.roles else None,
        note_ar=payload.get("note_ar"),
    )
    db.commit()
    technician = db.get(Technician, updated.technician_id)
    return AssignmentResponse(
        id=updated.id,
        request_id=updated.request_id,
        technician_id=updated.technician_id,
        technician_name=technician.name if technician else "",
        assigned_at=updated.assigned_at,
        expected_arrival_start=updated.expected_arrival_start,
        expected_arrival_end=updated.expected_arrival_end,
        actual_arrival=updated.actual_arrival,
        work_started_at=updated.work_started_at,
        work_completed_at=updated.work_completed_at,
        status=updated.status,
        cancelled_reason=updated.cancelled_reason,
    )


# ---------------------------------------------------------------- inspections


@router.post(
    "/{request_id}/inspection/schedule",
    response_model=dict,
    status_code=201,
    summary="Schedule an inspection",
)
def schedule_inspection(
    request_id: uuid.UUID,
    payload: AdminInspectionScheduleRequest,
    db: DbSession,
    staff: WriteGuard,
) -> dict:
    request = request_service.get_request_for_staff(db, request_id=request_id)
    inspection = inspection_service.schedule(
        db,
        request=request,
        staff_id=staff.staff.id,
        staff_role=staff.roles[0] if staff.roles else None,
        scheduled_start=payload.scheduled_start,
        scheduled_end=payload.scheduled_end,
        technician_id=payload.technician_id,
        fee=payload.fee,
    )
    db.commit()
    return {
        "inspection_id": str(inspection.id),
        "status": inspection.status.value,
        "scheduled_start": inspection.scheduled_start,
    }


@router.post(
    "/{request_id}/inspection/start", response_model=dict, summary="Start inspection"
)
def start_inspection(
    request_id: uuid.UUID, db: DbSession, staff: WriteGuard
) -> dict:
    request = request_service.get_request_for_staff(db, request_id=request_id)
    inspection = inspection_service.get_inspection(db, request_id=request.id)
    if inspection is None:
        from app.core.exceptions import NotFoundError

        raise NotFoundError("No inspection exists for this request.")
    updated = inspection_service.start(
        db,
        inspection=inspection,
        request=request,
        staff_id=staff.staff.id,
        staff_role=staff.roles[0] if staff.roles else None,
    )
    db.commit()
    return {"inspection_id": str(updated.id), "status": updated.status.value}


@router.post(
    "/{request_id}/inspection/complete", response_model=dict, summary="Complete inspection"
)
def complete_inspection(
    request_id: uuid.UUID,
    payload: AdminInspectionCompleteRequest,
    db: DbSession,
    staff: WriteGuard,
) -> dict:
    request = request_service.get_request_for_staff(db, request_id=request_id)
    inspection = inspection_service.get_inspection(db, request_id=request.id)
    if inspection is None:
        from app.core.exceptions import NotFoundError

        raise NotFoundError("No inspection exists for this request.")
    report = inspection_service.complete(
        db,
        inspection=inspection,
        request=request,
        staff_id=staff.staff.id,
        staff_role=staff.roles[0] if staff.roles else None,
        diagnosis=payload.diagnosis,
        problem_description=payload.problem_description,
        required_work=payload.required_work,
        required_materials=payload.required_materials,
        estimated_duration_minutes=payload.estimated_duration_minutes,
        proposed_price=payload.proposed_price,
        internal_notes=payload.internal_notes,
    )
    db.commit()
    return {
        "inspection_id": str(inspection.id),
        "status": inspection.status.value,
        "report_id": str(report.id),
    }


@router.post(
    "/{request_id}/inspection/qc", response_model=MessageResponse, summary="QC review"
)
def qc_review(
    request_id: uuid.UUID,
    payload: AdminQcReviewRequest,
    db: DbSession,
    staff: WriteGuard,
) -> MessageResponse:
    # The name ``request`` was undefined here (the HTTP request object shadows
    # nothing here), so this route raised NameError on every QC review.
    request = request_service.get_request_for_staff(db, request_id=request_id)
    inspection = inspection_service.get_inspection(db, request_id=request.id)
    if inspection is None:
        from app.core.exceptions import NotFoundError

        raise NotFoundError("No inspection exists for this request.")
    report = inspection_service.qc_review(
        db,
        inspection=inspection,
        staff_id=staff.staff.id,
        staff_role=staff.roles[0] if staff.roles else None,
        qc_passed=payload.qc_passed,
        notes=payload.notes,
    )
    db.commit()
    state = "ناجح" if report.qc_passed else "يحتاج إعادة عمل"
    return MessageResponse(message=f"تم تسجيل نتيجة فحص الجودة: {state}")


# ------------------------------------------------------------------------- AI


@router.post(
    "/ai/classify",
    response_model=AiClassifyResponse,
    summary="Optional AI classification (advisory, never binding)",
)
def ai_classify(
    payload: AiClassifyRequestRequest, db: DbSession, staff: OpsGuard
) -> AiClassifyResponse:
    from app.schemas.requests import CreateServiceRequestRequest  # noqa: F401

    if not ai_service.is_configured():
        return AiClassifyResponse(
            request_id=payload.request_id,
            predicted_category="",
            predicted_problem="",
            confidence=0.0,
            inspection_recommended=False,
            model_provider="none",
            model_name="none",
            available=False,
            reason_ar="خدمة التصنيف الذكي غير مهيأة حاليًا.",
        )
    result, _row = ai_service.classify(
        db,
        problem_description=payload.problem_description,
        request_id=payload.request_id,
        include_history=payload.include_history,
    )
    return AiClassifyResponse(
        request_id=payload.request_id,
        predicted_category=result.predicted_category,
        predicted_problem=result.predicted_problem,
        confidence=result.confidence,
        inspection_recommended=result.inspection_recommended,
        model_provider=result.model_provider,
        model_name=result.model_name,
        model_version=result.model_version,
        available=result.available,
        reason_ar=result.reason_ar,
    )


@router.post(
    "/{request_id}/ai/decision",
    response_model=MessageResponse,
    summary="Record the human decision on an AI suggestion",
)
def ai_decision(
    request_id: uuid.UUID,
    payload: AiReviewDecisionRequest,
    db: DbSession,
    staff: WriteGuard,
) -> MessageResponse:
    classification = ai_service.latest_for_request(db, request_id=request_id)
    if classification is None:
        from app.core.exceptions import NotFoundError

        raise NotFoundError("No AI suggestion exists for this request.")
    ai_service.apply_human_decision(
        db,
        classification=classification,
        staff_id=staff.staff.id,
        approved_category=payload.approved_category_code,
        approved_problem=payload.approved_problem_code,
    )
    db.commit()
    return MessageResponse(message="تم تسجيل قرار الموظف.")