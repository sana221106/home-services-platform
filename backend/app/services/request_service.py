"""Service request lifecycle — the vertical slice core (§5, §61, §63, §90).

Ownership is always re-derived from the authenticated customer; a
``request_id`` supplied by the client is never trusted on its own (§90, §103).
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta
from decimal import Decimal
from typing import Any

from sqlalchemy import Select, func, select
from sqlalchemy.orm import Session, selectinload

from app.core.config import settings
from app.core.enums import (
    InspectionStatus,
    RequestStatus,
    Urgency,
    can_transition,
)
from app.core.exceptions import (
    ConflictError,
    CoverageError,
    DomainError,
    NotFoundError,
    ValidationError,
)
from app.core.logging import get_logger
from app.db.models.catalog import ProblemType, ServiceCategory
from app.db.models.properties import Property
from app.db.models.requests import (
    Inspection,
    OrderAddressSnapshot,
    PhotoAnnotation,
    RequestEvent,
    RequestMedia,
    ServiceRequest,
)
from app.schemas.requests import (
    AddressSnapshotPayload,
    AnnotationPayload,
    CreateServiceRequestRequest,
)
from app.services import analytics_service, geocoding_service
from app.services.analytics_service import AnalyticsEventName
from app.services.media_service import (
    build_storage_path,
    make_storage_client,
    validate_image,
)
from app.utils.pagination import offset_for
from app.utils.time import now_utc

log = get_logger(__name__)

REQUEST_EVENT_CUSTOMER_VISIBLE = {
    "REQUEST_CREATED",
    "REQUEST_SUBMITTED",
    "REVIEW_STARTED",
    "NEED_MORE_INFORMATION",
    "INSPECTION_REQUIRED",
    "INSPECTION_SCHEDULED",
    "INSPECTION_COMPLETED",
    "QUOTE_CREATED",
    "QUOTE_SENT",
    "QUOTE_REVISED",
    "QUOTE_ACCEPTED",
    "QUOTE_REJECTED",
    "DEPOSIT_REQUIRED",
    "DEPOSIT_VERIFIED",
    "REQUEST_CONFIRMED",
    "TECHNICIAN_ASSIGNED",
    "EXPECTED_ARRIVAL_UPDATED",
    "ON_THE_WAY",
    "ARRIVED",
    "SERVICE_STARTED",
    "SERVICE_COMPLETED",
    "PAYMENT_REQUIRED",
    "PAYMENT_RECORDED",
    "PAYMENT_VERIFIED",
    "RATING_REMINDER",
    "COMPLAINT_UPDATE",
    "CANCELLED",
}


# ------------------------------------------------------------------ accessors


def get_request_for_customer(
    session: Session, *, request_id: uuid.UUID, customer_id: uuid.UUID
) -> ServiceRequest:
    """Ownership-checked load. Raises 404 rather than 403 so the API does not
    confirm the existence of another customer's request (§90, §142)."""
    request = session.execute(
        select(ServiceRequest)
        .options(
            selectinload(ServiceRequest.media).selectinload(RequestMedia.annotations),
            selectinload(ServiceRequest.address_snapshot),
            selectinload(ServiceRequest.quotes),
            selectinload(ServiceRequest.assignments),
            selectinload(ServiceRequest.inspection),
            selectinload(ServiceRequest.events),
        )
        .where(ServiceRequest.id == request_id, ServiceRequest.customer_id == customer_id)
    ).scalar_one_or_none()
    if request is None:
        raise NotFoundError("Request not found.")
    return request


def get_request_for_staff(session: Session, *, request_id: uuid.UUID) -> ServiceRequest:
    request = session.execute(
        select(ServiceRequest)
        .options(
            selectinload(ServiceRequest.media).selectinload(RequestMedia.annotations),
            selectinload(ServiceRequest.address_snapshot),
            selectinload(ServiceRequest.quotes),
            selectinload(ServiceRequest.assignments),
            selectinload(ServiceRequest.inspection),
        )
        .where(ServiceRequest.id == request_id)
    ).scalar_one_or_none()
    if request is None:
        raise NotFoundError("Request not found.")
    return request


def list_requests_for_customer(
    session: Session,
    *,
    customer_id: uuid.UUID,
    page: int,
    per_page: int,
    statuses: list[RequestStatus] | None = None,
) -> tuple[list[ServiceRequest], int]:
    base = select(ServiceRequest).where(ServiceRequest.customer_id == customer_id)
    if statuses:
        base = base.where(ServiceRequest.status.in_(statuses))
    total = session.execute(
        select(func.count()).select_from(base.subquery())
    ).scalar_one()
    rows = list(
        session.execute(
            base.order_by(ServiceRequest.created_at.desc())
            .offset(offset_for(page, per_page))
            .limit(per_page)
        )
        .unique()
        .scalars()
    )
    return rows, int(total)


def list_requests_for_staff(
    session: Session,
    *,
    page: int,
    per_page: int,
    status: RequestStatus | None = None,
    urgency: Urgency | None = None,
    zone_id: uuid.UUID | None = None,
    category_id: uuid.UUID | None = None,
    search: str | None = None,
) -> tuple[list[ServiceRequest], int]:
    base = select(ServiceRequest).join(
        OrderAddressSnapshot, OrderAddressSnapshot.request_id == ServiceRequest.id, isouter=True
    )
    if status is not None:
        base = base.where(ServiceRequest.status == status)
    if urgency is not None:
        base = base.where(ServiceRequest.urgency == urgency)
    if category_id is not None:
        base = base.where(ServiceRequest.category_id == category_id)
    if search:
        base = base.where(ServiceRequest.reference_code.ilike(f"%{search.strip()}%"))
    total = session.execute(select(func.count()).select_from(base.subquery())).scalar_one()
    rows = list(
        session.execute(
            base.order_by(ServiceRequest.created_at.desc())
            .options(selectinload(ServiceRequest.media))
            .offset(offset_for(page, per_page))
            .limit(per_page)
        )
        .unique()
        .scalars()
    )
    if zone_id is not None:
        rows = [
            row
            for row in rows
            if _matches_zone(session, request=row, zone_id=zone_id)
        ]
    return rows, int(total)


def _matches_zone(session: Session, *, request: ServiceRequest, zone_id: uuid.UUID) -> bool:
    from app.db.models.catalog import ServiceAreaSnapshot

    area = session.execute(
        select(ServiceAreaSnapshot).where(ServiceAreaSnapshot.request_id == request.id)
    ).scalar_one_or_none()
    if area is not None:
        return area.zone_id == zone_id
    return False


# --------------------------------------------------------------- create/draft


def create_request(
    session: Session,
    *,
    customer_id: uuid.UUID,
    payload: CreateServiceRequestRequest,
    idempotency_key: str | None = None,
) -> ServiceRequest:
    """Create (or return) a draft. Pricing is resolved server-side; nothing the
    client sends about money is trusted (§120)."""
    if idempotency_key:
        existing = session.execute(
            select(ServiceRequest).where(
                ServiceRequest.customer_id == customer_id,
                ServiceRequest.reference_code == idempotency_key,
            )
        ).scalar_one_or_none()
        if existing is not None:
            return existing

    property_row = session.execute(
        select(Property).where(
            Property.id == payload.property_id,
            Property.customer_id == customer_id,
            Property.deleted_at.is_(None),
        )
    ).scalar_one_or_none()
    if property_row is None:
        # Covers both "does not exist" and "belongs to someone else".
        raise NotFoundError("Property not found.")

    category = session.execute(
        select(ServiceCategory).where(
            ServiceCategory.id == payload.category_id,
            ServiceCategory.is_active.is_(True),
            ServiceCategory.deleted_at.is_(None),
        )
    ).scalar_one_or_none()
    if category is None:
        raise ValidationError("Unknown or inactive service category.")

    problem_type = None
    if payload.problem_type_id is not None:
        problem_type = session.execute(
            select(ProblemType).where(
                ProblemType.id == payload.problem_type_id,
                ProblemType.category_id == payload.category_id,
                ProblemType.is_active.is_(True),
            )
        ).scalar_one_or_none()
        if problem_type is None:
            raise ValidationError("The selected problem type does not belong to this service.")

    if payload.inspection_only and payload.urgency == Urgency.URGENT:
        raise ValidationError("An inspection-only visit cannot be marked urgent.")

    zone_id = _resolve_zone_id(session, address=payload.address)
    _assert_within_coverage(payload.address, zone_id=zone_id)

    inspection_required = bool(
        payload.inspection_only
        or category.requires_inspection_default
        or (problem_type and problem_type.requires_inspection_default)
    )

    from app.utils.pagination import generate_reference_code

    request = ServiceRequest(
        reference_code=generate_reference_code("HSP"),
        customer_id=customer_id,
        property_id=payload.property_id,
        category_id=payload.category_id,
        problem_type_id=payload.problem_type_id,
        status=RequestStatus.DRAFT,
        urgency=payload.urgency,
        inspection_only=payload.inspection_only,
        inspection_required=inspection_required,
        problem_description=payload.problem_description.strip(),
        preferred_date=payload.preferred_date,
        preferred_time_window=payload.preferred_time_window,
        customer_notes=payload.customer_notes,
    )
    session.add(request)
    session.flush()

    session.add(
        OrderAddressSnapshot(
            request_id=request.id,
            governorate=payload.address.governorate,
            city=payload.address.city,
            zone=payload.address.zone,
            # The canonical coverage area, not the typed text. Analytics and
            # dispatch read this, so they group by served area rather than by
            # however the customer happened to spell the city.
            zone_code=_zone_code_for(session, zone_id=zone_id),
            district=payload.address.district,
            street=payload.address.street,
            building=payload.address.building,
            floor=payload.address.floor,
            apartment=payload.address.apartment,
            landmark=payload.address.landmark,
            notes=payload.address.notes,
            latitude=payload.address.latitude,
            longitude=payload.address.longitude,
            contact_name=payload.address.contact_name,
            contact_phone=payload.address.contact_phone,
        )
    )
    session.flush()

    record_event(
        session,
        request_id=request.id,
        event_type="REQUEST_DRAFTED",
        actor_type="customer",
        actor_id=customer_id,
        note="تم إنشاء الطلب",
    )
    analytics_service.record_event(
        session,
        event_name=AnalyticsEventName.REQUEST_STARTED,
        customer_id=customer_id,
        request_id=request.id,
    )
    session.flush()
    return request


def _zone_code_for(session: Session, *, zone_id: uuid.UUID | None) -> str | None:
    """The canonical code for a resolved area, or None if it is unserved."""
    if zone_id is None:
        return None
    zone = geocoding_service.zone_by_id(session, zone_id)
    return zone.code if zone is not None else None


def _resolve_zone_id(
    session: Session, *, address: AddressSnapshotPayload
) -> uuid.UUID | None:
    """Find the served area an address belongs to.

    The coordinates decide, then an explicitly picked area, then the typed text.
    Coordinates come first because dispatch sends the technician to exactly
    those coordinates: an area chosen independently of the point could put a
    Damietta technician on a Cairo address. The picked area is the safety net
    for a geocoder that placed the pin just outside every radius, and the text
    comparison is the last resort. Text matching also tries the Arabic district
    and zone name, so "دمياط الجديدة" resolves as readily as "New Damietta" (§30).
    """
    zones = geocoding_service.active_zones(session)
    if not zones:
        return None

    # Both coordinates are required by the schema, so this always runs. The 0,0
    # pair the app sends for "not picked" matches no zone and falls through to the
    # explicit area below rather than being served by accident.
    zone = geocoding_service.zone_for_point(
        zones, latitude=float(address.latitude), longitude=float(address.longitude)
    )
    if zone is not None:
        return zone.id

    # A choice from the list the server itself produced, so it cannot be
    # misspelled. It only applies where the point claims no area at all.
    if address.zone_code:
        zone = geocoding_service.zone_by_code(session, address.zone_code)
        if zone is not None:
            return zone.id

    zone = geocoding_service.zone_by_text(
        zones, governorate=address.governorate, city=address.city
    )
    return zone.id if zone is not None else None


def _assert_within_coverage(
    address: AddressSnapshotPayload, zone_id: uuid.UUID | None
) -> None:
    """Rejects an address no served area claims.

    `details` carries the coordinates as well as the text so the client can tell
    the customer which part failed: an unserved point is a different fix from a
    misspelled city (§30).

    The coordinates are floats rather than the payload's `Decimal` because
    `details` is serialised straight into a `JSONResponse`, which has no encoder
    for `Decimal` and would turn this 422 into a 500.
    """
    if zone_id is None:
        raise CoverageError(
            "This area is not currently served.",
            details={
                "city": address.city,
                "governorate": address.governorate,
                "zone_code": address.zone_code,
                "latitude": float(address.latitude),
                "longitude": float(address.longitude),
            },
        )


def submit_request(
    session: Session, *, request_id: uuid.UUID, customer_id: uuid.UUID
) -> ServiceRequest:
    request = get_request_for_customer(
        session, request_id=request_id, customer_id=customer_id
    )
    if request.status != RequestStatus.DRAFT:
        raise ConflictError("This request has already been submitted.", code="ALREADY_SUBMITTED")

    media_count = session.execute(
        select(func.count(RequestMedia.id)).where(
            RequestMedia.request_id == request.id, RequestMedia.deleted_at.is_(None)
        )
    ).scalar_one()
    if media_count == 0:
        raise ValidationError("Please attach at least one photo of the problem.")

    transition_request(
        session,
        request=request,
        target=RequestStatus.SUBMITTED,
        actor_type="customer",
        actor_id=customer_id,
        event_type="REQUEST_SUBMITTED",
        note_ar="تم استلام الطلب، وهو الآن قيد المراجعة",
    )
    request.submitted_at = now_utc()
    _persist_area_snapshot(session, request=request)

    analytics_service.record_event(
        session,
        event_name=AnalyticsEventName.REQUEST_SUBMITTED,
        customer_id=customer_id,
        request_id=request.id,
    )
    session.flush()
    return request


def _persist_area_snapshot(session: Session, *, request: ServiceRequest) -> None:
    """Capture §18 analytics fields from day one."""
    from app.db.models.catalog import ServiceAreaSnapshot

    snapshot = session.execute(
        select(OrderAddressSnapshot).where(OrderAddressSnapshot.request_id == request.id)
    ).scalar_one_or_none()
    if snapshot is None:
        return

    # The area was already resolved once, when the request was created, and the
    # code was frozen onto the address snapshot. Re-deriving it here would repeat
    # work that can only disagree with itself if a zone was edited in between.
    zone = (
        geocoding_service.zone_by_code(session, snapshot.zone_code)
        if snapshot.zone_code
        else None
    )
    session.add(
        ServiceAreaSnapshot(
            request_id=request.id,
            latitude=snapshot.latitude,
            longitude=snapshot.longitude,
            governorate=snapshot.governorate,
            city=snapshot.city,
            zone=snapshot.zone,
            district=snapshot.district,
            zone_id=zone.id if zone is not None else None,
        )
    )
    session.flush()


# --------------------------------------------------------------------- events


def record_event(
    session: Session,
    *,
    request_id: uuid.UUID,
    event_type: str,
    actor_type: str = "system",
    actor_id: uuid.UUID | None = None,
    actor_role: str | None = None,
    from_status: RequestStatus | None = None,
    to_status: RequestStatus | None = None,
    correlation_id: str | None = None,
    payload: dict[str, Any] | None = None,
    note: str | None = None,
) -> RequestEvent:
    event = RequestEvent(
        request_id=request_id,
        event_type=event_type,
        from_status=from_status,
        to_status=to_status,
        occurred_at=now_utc(),
        actor_type=actor_type,
        actor_id=actor_id,
        actor_role=actor_role,
        correlation_id=correlation_id,
        payload=payload,
        note=note,
    )
    session.add(event)
    session.flush()
    return event


def transition_request(
    session: Session,
    *,
    request: ServiceRequest,
    target: RequestStatus,
    actor_type: str = "system",
    actor_id: uuid.UUID | None = None,
    actor_role: str | None = None,
    event_type: str | None = None,
    note_ar: str | None = None,
    correlation_id: str | None = None,
    payload: dict[str, Any] | None = None,
    force: bool = False,
) -> ServiceRequest:
    """Validated state change (§62). ``force`` is reserved for audited admin
    overrides and still emits an event + audit trail."""
    current = RequestStatus(request.status)
    if not force and not can_transition(current, target):
        raise ConflictError(
            f"Cannot move a request from {current.value} to {target.value}.",
            code="INVALID_STATE_TRANSITION",
            details={"from": current.value, "to": target.value},
        )
    request.status = target
    record_event(
        session,
        request_id=request.id,
        event_type=event_type or f"STATUS_{target.value}",
        actor_type=actor_type,
        actor_id=actor_id,
        actor_role=actor_role,
        from_status=current,
        to_status=target,
        correlation_id=correlation_id,
        payload=payload,
        note=note_ar,
    )
    return request


def timeline_for_customer(
    session: Session, *, request: ServiceRequest, customer_id: uuid.UUID
) -> list[RequestEvent]:
    return list(
        session.execute(
            select(RequestEvent)
            .where(
                RequestEvent.request_id == request.id,
                RequestEvent.event_type.in_(REQUEST_EVENT_CUSTOMER_VISIBLE),
            )
            .order_by(RequestEvent.occurred_at.asc())
        ).scalars()
    )


# ---------------------------------------------------------------------- media


def add_media(
    session: Session,
    *,
    request: ServiceRequest,
    customer_id: uuid.UUID,
    content: bytes,
    declared_mime: str | None,
    filename: str | None,
    captured_at: datetime | None = None,
) -> RequestMedia:
    if request.customer_id != customer_id:
        raise NotFoundError("Request not found.")
    if request.status not in {
        RequestStatus.DRAFT,
        RequestStatus.SUBMITTED,
        RequestStatus.NEED_MORE_INFORMATION,
    }:
        raise ConflictError(
            "Photos can no longer be added to this request.",
            code="MEDIA_LOCKED",
        )

    active_count = session.execute(
        select(func.count(RequestMedia.id)).where(
            RequestMedia.request_id == request.id, RequestMedia.deleted_at.is_(None)
        )
    ).scalar_one()
    if int(active_count) >= settings.max_images_per_request:
        raise ValidationError(
            f"You can attach up to {settings.max_images_per_request} photos.",
            details={"max_images": settings.max_images_per_request},
        )

    validated = validate_image(content, declared_mime=declared_mime, filename=filename)
    media_id = uuid.uuid4()
    path = build_storage_path(
        customer_id=customer_id,
        request_id=request.id,
        extension=validated.extension,
        media_id=media_id,
    )
    storage = make_storage_client()
    storage.write(path, validated.content)

    media = RequestMedia(
        id=media_id,
        request_id=request.id,
        storage_path=path,
        storage_provider=storage.provider,
        mime_type=validated.mime_type,
        size_bytes=validated.size_bytes,
        width=validated.width,
        height=validated.height,
        checksum_sha256=validated.checksum_sha256,
        sort_order=int(active_count),
        uploaded_by_id=customer_id,
        captured_at=captured_at,
    )
    session.add(media)
    session.flush()
    analytics_service.record_event(
        session,
        event_name=AnalyticsEventName.REQUEST_MEDIA_ADDED,
        customer_id=customer_id,
        request_id=request.id,
    )
    return media


def delete_media(
    session: Session, *, request: ServiceRequest, media_id: uuid.UUID, customer_id: uuid.UUID
) -> None:
    if request.customer_id != customer_id:
        raise NotFoundError("Request not found.")
    media = session.execute(
        select(RequestMedia).where(
            RequestMedia.id == media_id,
            RequestMedia.request_id == request.id,
            RequestMedia.deleted_at.is_(None),
        )
    ).scalar_one_or_none()
    if media is None:
        raise NotFoundError("Photo not found.")
    if request.status not in {
        RequestStatus.DRAFT,
        RequestStatus.SUBMITTED,
        RequestStatus.NEED_MORE_INFORMATION,
    }:
        raise ConflictError("Photos can no longer be removed.", code="MEDIA_LOCKED")
    media.deleted_at = now_utc()
    session.flush()


def add_annotation(
    session: Session,
    *,
    request: ServiceRequest,
    media_id: uuid.UUID,
    customer_id: uuid.UUID,
    payload: AnnotationPayload,
) -> PhotoAnnotation:
    """Normalized-geometry annotation (§80). Coordinates stay in 0..1 so the
    same record can be replayed onto a different render size later."""
    if request.customer_id != customer_id:
        raise NotFoundError("Request not found.")
    media = session.execute(
        select(RequestMedia).where(
            RequestMedia.id == media_id,
            RequestMedia.request_id == request.id,
            RequestMedia.deleted_at.is_(None),
        )
    ).scalar_one_or_none()
    if media is None:
        raise NotFoundError("Photo not found.")

    annotation = PhotoAnnotation(
        media_id=media.id,
        request_id=request.id,
        annotation_type=payload.annotation_type.value,
        geometry=payload.geometry,
        note=payload.note,
        created_by_id=customer_id,
    )
    session.add(annotation)
    session.flush()
    return annotation


def media_urls(session: Session, *, media: list[RequestMedia]) -> dict[uuid.UUID, str]:
    """Resolve storage paths to authorised URLs. Raw paths are never exposed."""
    base = _storage_base_url().rstrip("/")
    resolved: dict[uuid.UUID, str] = {}
    for item in media:
        if item.deleted_at is not None:
            continue
        if base:
            resolved[item.id] = f"{base}/{item.storage_path}"
        else:
            resolved[item.id] = f"/api/v1/media/{item.id}/content"
    return resolved


def _storage_base_url() -> str:
    return settings.storage_public_base_url


# ---------------------------------------------------------------- inspection


def ensure_inspection(
    session: Session, *, request: ServiceRequest, fee: Decimal | None = None
) -> Inspection:
    inspection = session.execute(
        select(Inspection).where(Inspection.request_id == request.id)
    ).scalar_one_or_none()
    if inspection is not None:
        return inspection
    inspection = Inspection(
        request_id=request.id,
        status=InspectionStatus.PENDING,
        fee=fee,
    )
    session.add(inspection)
    session.flush()
    request.inspection_status = InspectionStatus.PENDING
    return inspection


def request_counts_by_status(
    session: Session, *, customer_id: uuid.UUID
) -> dict[RequestStatus, int]:
    rows = session.execute(
        select(ServiceRequest.status, func.count(ServiceRequest.id))
        .where(ServiceRequest.customer_id == customer_id)
        .group_by(ServiceRequest.status)
    ).all()
    return {RequestStatus(status): int(count) for status, count in rows}


def requests_needing_follow_up(session: Session, *, since: datetime) -> Select[tuple[Any]]:
    """Funnel-stall detector for the call centre (§74)."""
    return (
        select(ServiceRequest)
        .where(
            ServiceRequest.submitted_at.is_not(None),
            ServiceRequest.submitted_at <= since,
            ServiceRequest.status.in_(
                [
                    RequestStatus.SUBMITTED,
                    RequestStatus.UNDER_REVIEW,
                    RequestStatus.QUOTE_SENT,
                    RequestStatus.AWAITING_CUSTOMER_APPROVAL,
                ]
            ),
        )
        .order_by(ServiceRequest.submitted_at.asc())
    )


def default_expected_arrival(
    *, start: datetime, duration_minutes: int = 120
) -> tuple[datetime, datetime]:
    return start, start + timedelta(minutes=max(30, duration_minutes))


__all__ = [
    "REQUEST_EVENT_CUSTOMER_VISIBLE",
    "add_annotation",
    "add_media",
    "create_request",
    "default_expected_arrival",
    "delete_media",
    "ensure_inspection",
    "get_request_for_customer",
    "get_request_for_staff",
    "list_requests_for_customer",
    "list_requests_for_staff",
    "media_urls",
    "record_event",
    "request_counts_by_status",
    "requests_needing_follow_up",
    "submit_request",
    "timeline_for_customer",
    "transition_request",
]