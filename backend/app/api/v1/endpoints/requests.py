"""Service request, media, annotation and timeline endpoints (§62-§66, §80)."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, File, Query, UploadFile
from sqlalchemy import func, select

from app.api.dependencies import CurrentCustomer, DbSession
from app.core.enums import RequestStatus
from app.core.exceptions import ValidationError
from app.db.models.catalog import ProblemType, ServiceCategory
from app.db.models.requests import OrderAddressSnapshot, RequestMedia
from app.db.models.support import Notification
from app.schemas.common import MessageResponse, Page
from app.schemas.requests import (
    AcceptQuoteRequest,
    AnnotationResponse,
    CancellationPreviewResponse,
    CancelRequestRequest,
    CreateAnnotationRequest,
    CreateServiceRequestRequest,
    QuoteResponse,
    RejectQuoteRequest,
    RequestEventResponse,
    RequestMediaResponse,
    ServiceRequestDetailResponse,
    ServiceRequestResponse,
    SubmitServiceRequestRequest,
    TimelineResponse,
    UploadedMediaBatch,
)
from app.services import (
    order_service,
    payment_service,
    quote_service,
    request_service,
)

router = APIRouter(prefix="/requests", tags=["requests"])

ACTIVE_CUSTOMER_STATUSES = [
    RequestStatus.SUBMITTED,
    RequestStatus.UNDER_REVIEW,
    RequestStatus.QUOTE_PREPARATION,
    RequestStatus.QUOTE_SENT,
    RequestStatus.AWAITING_CUSTOMER_APPROVAL,
    RequestStatus.QUOTE_REJECTED,
    RequestStatus.PAYMENT_PENDING,
    RequestStatus.PAYMENT_VERIFICATION,
    RequestStatus.TECHNICIAN_ASSIGNED,
    RequestStatus.ON_THE_WAY,
    RequestStatus.ARRIVED,
    RequestStatus.WORK_IN_PROGRESS,
    RequestStatus.SERVICE_COMPLETED,
    RequestStatus.AWAITING_RATING,
    RequestStatus.NEED_MORE_INFORMATION,
    RequestStatus.INSPECTION_SCHEDULED,
    RequestStatus.INSPECTION_IN_PROGRESS,
    RequestStatus.INSPECTION_COMPLETED,
]


def _media_payload(
    media: list[RequestMedia], urls: dict[uuid.UUID, str]
) -> list[RequestMediaResponse]:
    return [
        RequestMediaResponse(
            id=item.id,
            kind=item.kind,
            mime_type=item.mime_type,
            size_bytes=item.size_bytes,
            width=item.width,
            height=item.height,
            sort_order=item.sort_order,
            url=urls.get(item.id),
            annotations=[AnnotationResponse.model_validate(a) for a in item.annotations],
            created_at=item.created_at,
        )
        for item in media
        if item.deleted_at is None
    ]


def _request_payload(
    db: DbSession, request, *, detail: bool = False
):  # noqa: ANN001, ANN202 - ServiceRequest
    category = db.get(ServiceCategory, request.category_id)
    problem = (
        db.get(ProblemType, request.problem_type_id) if request.problem_type_id else None
    )
    urls = request_service.media_urls(db, media=list(request.media))
    inspection = request.inspection
    technician = order_service_technician(db, request)
    address_line = None
    snapshot = db.execute(
        select(OrderAddressSnapshot).where(OrderAddressSnapshot.request_id == request.id)
    ).scalar_one_or_none()
    if snapshot is not None:
        parts = [
            snapshot.building,
            f"شقة {snapshot.apartment}" if snapshot.apartment else None,
            snapshot.street,
            snapshot.zone,
            snapshot.city,
            snapshot.governorate,
        ]
        address_line = "، ".join(part for part in parts if part)

    expected = order_service_current_window(request)
    base = {
        "id": request.id,
        "reference_code": request.reference_code,
        "customer_id": request.customer_id,
        "property_id": request.property_id,
        "category_id": request.category_id,
        "category_name_ar": category.name_ar if category else "",
        "category_icon_key": category.icon_key if category else "wrench",
        "problem_type_id": request.problem_type_id,
        "problem_name_ar": problem.name_ar if problem else None,
        "status": RequestStatus(request.status),
        "urgency": request.urgency,
        "inspection_only": request.inspection_only,
        "inspection_required": request.inspection_required,
        "problem_description": request.problem_description,
        "preferred_date": request.preferred_date,
        "preferred_time_window": request.preferred_time_window,
        "customer_notes": request.customer_notes,
        "created_at": request.created_at,
        "submitted_at": request.submitted_at,
        "completed_at": request.completed_at,
        "has_complaint": request.has_complaint,
        "has_rework": request.has_rework,
        "rated_at": request.rated_at,
        "media_count": sum(1 for m in request.media if m.deleted_at is None),
        "expected_arrival": expected,
        "technician": technician,
        "address_summary_ar": address_line,
    }
    if not detail:
        return ServiceRequestResponse(**base)

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
    inspection_summary = None
    if inspection is not None:
        inspection_summary = {
            "id": inspection.id,
            "status": inspection.status,
            "scheduled_start": inspection.scheduled_start,
            "scheduled_end": inspection.scheduled_end,
            "completed_at": inspection.completed_at,
        }
    return ServiceRequestDetailResponse(
        **base,
        media=_media_payload(list(request.media), urls),
        address=address,
        inspection=inspection_summary,
        has_unread_updates=has_unread_customer_update(db, request.id),
    )


def has_unread_customer_update(db: DbSession, request_id: uuid.UUID) -> bool:
    """Unread operator messages bound to this request drive the badge in the app."""
    return (
        db.execute(
            select(func.count(Notification.id)).where(
                Notification.request_id == request_id,
                Notification.is_read.is_(False),
            )
        ).scalar_one()
        or 0
    ) > 0


def order_service_current_window(request):  # noqa: ANN001, ANN202
    summary = order_service.current_assignment_summary(request)
    if summary is None:
        return None
    return {"start": summary["expected_arrival_start"], "end": summary["expected_arrival_end"]}


def order_service_technician(db: DbSession, request):  # noqa: ANN001, ANN202
    from app.db.models.workforce import Technician
    from app.services import dispatch_service

    assignment = dispatch_service.find_assignment(db, request_id=request.id)
    if assignment is None:
        return None
    technician = db.get(Technician, assignment.technician_id)
    first_name = (technician.name.split() or [""])[0] if technician else ""
    return {"display_name": first_name, "company_label_ar": "فريق الخدمة"}


def _owned(db: DbSession, request_id: uuid.UUID, customer):  # noqa: ANN001, ANN202
    return request_service.get_request_for_customer(
        db, request_id=request_id, customer_id=customer.profile.id
    )


# ------------------------------------------------------------------- list/read


@router.get("", response_model=Page[ServiceRequestResponse], summary="My requests")
def list_requests(
    db: DbSession,
    customer: CurrentCustomer,
    page: int = Query(default=1, ge=1),
    per_page: int = Query(default=20, ge=1, le=100),
    status: list[RequestStatus] | None = Query(default=None),
) -> Page[ServiceRequestResponse]:
    rows, total = request_service.list_requests_for_customer(
        db,
        customer_id=customer.profile.id,
        page=page,
        per_page=per_page,
        statuses=status,
    )
    items = [_request_payload(db, row) for row in rows]
    return Page[ServiceRequestResponse].build(
        items=items, total=total, page=page, per_page=per_page
    )


@router.get("/active", response_model=list[ServiceRequestResponse], summary="Active requests")
def active_requests(db: DbSession, customer: CurrentCustomer) -> list[ServiceRequestResponse]:
    rows, _total = request_service.list_requests_for_customer(
        db,
        customer_id=customer.profile.id,
        page=1,
        per_page=100,
        statuses=ACTIVE_CUSTOMER_STATUSES,
    )
    return [_request_payload(db, row) for row in rows]


@router.post(
    "",
    response_model=ServiceRequestDetailResponse,
    status_code=201,
    summary="Create a draft request",
)
def create_request(
    payload: CreateServiceRequestRequest, db: DbSession, customer: CurrentCustomer
) -> ServiceRequestDetailResponse:
    request = request_service.create_request(
        db,
        customer_id=customer.profile.id,
        payload=payload,
        idempotency_key=payload.idempotency_key,
    )
    db.commit()
    return _request_payload(db, request, detail=True)


@router.get(
    "/{request_id}",
    response_model=ServiceRequestDetailResponse,
    summary="Request detail",
)
def get_request(
    request_id: uuid.UUID, db: DbSession, customer: CurrentCustomer
) -> ServiceRequestDetailResponse:
    request = _owned(db, request_id, customer)
    return _request_payload(db, request, detail=True)


@router.post(
    "/{request_id}/submit",
    response_model=ServiceRequestDetailResponse,
    summary="Submit a draft request",
)
def submit_request(
    request_id: uuid.UUID,
    payload: SubmitServiceRequestRequest,
    db: DbSession,
    customer: CurrentCustomer,
) -> ServiceRequestDetailResponse:
    request = request_service.submit_request(
        db, request_id=request_id, customer_id=customer.profile.id
    )
    db.commit()
    db.refresh(request)
    return _request_payload(db, request, detail=True)


@router.get(
    "/{request_id}/timeline",
    response_model=TimelineResponse,
    summary="Customer-visible timeline",
)
def timeline(
    request_id: uuid.UUID, db: DbSession, customer: CurrentCustomer
) -> TimelineResponse:
    request = _owned(db, request_id, customer)
    events = request_service.timeline_for_customer(
        db, request=request, customer_id=customer.profile.id
    )
    return TimelineResponse(
        request_id=request.id,
        status=RequestStatus(request.status),
        events=[RequestEventResponse.model_validate(event) for event in events],
    )


# ------------------------------------------------------------------------ media


@router.post(
    "/{request_id}/media",
    response_model=UploadedMediaBatch,
    status_code=201,
    summary="Attach a problem photo",
)
def upload_media(
    request_id: uuid.UUID,
    db: DbSession,
    customer: CurrentCustomer,
    file: Annotated[UploadFile, File(description="JPEG/PNG/WebP, max 10 MB")],
) -> UploadedMediaBatch:
    request = _owned(db, request_id, customer)
    content = file.file.read()
    if not content:
        raise ValidationError("The uploaded file is empty.")
    media = request_service.add_media(
        db,
        request=request,
        customer_id=customer.profile.id,
        content=content,
        declared_mime=file.content_type,
        filename=file.filename,
    )
    db.commit()
    urls = request_service.media_urls(db, media=[media])
    return UploadedMediaBatch(media=_media_payload([media], urls))


@router.delete(
    "/{request_id}/media/{media_id}",
    response_model=MessageResponse,
    summary="Remove an attached photo",
)
def delete_media(
    request_id: uuid.UUID,
    media_id: uuid.UUID,
    db: DbSession,
    customer: CurrentCustomer,
) -> MessageResponse:
    request = _owned(db, request_id, customer)
    request_service.delete_media(
        db, request=request, media_id=media_id, customer_id=customer.profile.id
    )
    db.commit()
    return MessageResponse(message="تم حذف الصورة.")


@router.post(
    "/{request_id}/media/{media_id}/annotations",
    response_model=AnnotationResponse,
    status_code=201,
    summary="Annotate an attached photo",
)
def annotate_media(
    request_id: uuid.UUID,
    media_id: uuid.UUID,
    payload: CreateAnnotationRequest,
    db: DbSession,
    customer: CurrentCustomer,
) -> AnnotationResponse:
    request = _owned(db, request_id, customer)
    annotation = request_service.add_annotation(
        db,
        request=request,
        media_id=media_id,
        customer_id=customer.profile.id,
        payload=payload,
    )
    db.commit()
    return AnnotationResponse.model_validate(annotation)


# ----------------------------------------------------------------------- quotes


@router.get(
    "/{request_id}/quote",
    response_model=QuoteResponse | None,
    summary="Current actionable quote",
)
def current_quote(
    request_id: uuid.UUID, db: DbSession, customer: CurrentCustomer
) -> QuoteResponse | None:
    request = _owned(db, request_id, customer)
    quote = quote_service.current_quote(db, request_id=request.id)
    if quote is not None:
        quote_service.mark_quote_viewed(
            db, quote=quote, customer_id=customer.profile.id
        )
        db.commit()
    return QuoteResponse.model_validate(quote) if quote else None


@router.post(
    "/{request_id}/quote/accept",
    response_model=ServiceRequestDetailResponse,
    summary="Accept the quote (idempotent)",
)
def accept_quote(
    request_id: uuid.UUID,
    payload: AcceptQuoteRequest,
    db: DbSession,
    customer: CurrentCustomer,
) -> ServiceRequestDetailResponse:
    request = _owned(db, request_id, customer)
    quote = quote_service.accept_quote(
        db,
        request=request,
        customer_id=customer.profile.id,
        accepted_revision=payload.accepted_revision,
        idempotency_key=payload.idempotency_key,
    )
    payment_service.ensure_deposit(db, request=request, quote=quote)
    db.commit()
    db.refresh(request)
    return _request_payload(db, request, detail=True)


@router.post(
    "/{request_id}/quote/reject",
    response_model=ServiceRequestDetailResponse,
    summary="Reject the quote",
)
def reject_quote(
    request_id: uuid.UUID,
    payload: RejectQuoteRequest,
    db: DbSession,
    customer: CurrentCustomer,
) -> ServiceRequestDetailResponse:
    request = _owned(db, request_id, customer)
    quote_service.reject_quote(
        db,
        request=request,
        customer_id=customer.profile.id,
        reason=payload.reason,
    )
    db.commit()
    db.refresh(request)
    return _request_payload(db, request, detail=True)


@router.get(
    "/{request_id}/cancellation-preview",
    response_model=CancellationPreviewResponse,
    summary="Server-computed cancellation refund preview",
)
def cancellation_preview(
    request_id: uuid.UUID, db: DbSession, customer: CurrentCustomer
) -> CancellationPreviewResponse:
    request = _owned(db, request_id, customer)
    preview = payment_service.preview_cancellation(db, request=request)
    db.commit()
    return CancellationPreviewResponse(**preview)


@router.post(
    "/{request_id}/cancel",
    response_model=ServiceRequestDetailResponse,
    summary="Cancel the request",
)
def cancel_request(
    request_id: uuid.UUID,
    payload: CancelRequestRequest,
    db: DbSession,
    customer: CurrentCustomer,
) -> ServiceRequestDetailResponse:
    from app.core.enums import CancellationReason

    request = _owned(db, request_id, customer)
    order_service.cancel_request(
        db,
        request=request,
        reason=CancellationReason.CUSTOMER_REQUEST,
        reason_note=payload.reason_note,
        actor_id=customer.profile.id,
        actor_role="customer",
        actor_type="customer",
    )
    from app.db.models.finance import Cancellation

    cancellation = db.execute(
        select(Cancellation).where(Cancellation.request_id == request.id)
    ).scalar_one_or_none()
    if cancellation is not None:
        payment_service.apply_cancellation_refund(
            db,
            request=request,
            cancellation=cancellation,
            staff_id=customer.profile.id,
            staff_role="customer",
        )
    db.commit()
    db.refresh(request)
    return _request_payload(db, request, detail=True)