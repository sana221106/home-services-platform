"""Order tracking for customers (§30, §66).

Deliberately exposes an expected arrival *range* and coarse status only —
never live GPS, never the technician's phone or photo (§9, §10).
"""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Query
from sqlalchemy import func, select

from app.api.dependencies import CurrentCustomer, DbSession
from app.core.enums import RequestStatus
from app.core.labels import REQUEST_STATUS_LABELS, URGENCY_LABELS
from app.db.models.catalog import ServiceCategory
from app.db.models.properties import Property
from app.db.models.requests import OrderAddressSnapshot
from app.db.models.support import Notification
from app.db.models.workforce import Technician
from app.schemas.common import Page
from app.schemas.orders import OrderListItem, OrderTrackingResponse
from app.schemas.requests import ExpectedArrival, RequestEventResponse
from app.services import (
    dashboard_service,
    dispatch_service,
    order_service,
    payment_service,
    request_service,
)

router = APIRouter(prefix="/orders", tags=["orders"])


def _address_line(db: DbSession, request) -> str | None:  # noqa: ANN001, ANN202
    """One-line visit address, composed the same way the requests detail does.

    The snapshot is what the technician will actually visit, so it is preferred
    over the property record: the customer can edit the address on the request
    after the property was saved.
    """
    snapshot = db.execute(
        select(OrderAddressSnapshot).where(
            OrderAddressSnapshot.request_id == request.id
        )
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
        line = "، ".join(part for part in parts if part)
        if line:
            return line

    prop = db.get(Property, request.property_id)
    if prop is None:
        return None
    parts = [prop.building, prop.street, prop.city, prop.governorate]
    line = "، ".join(part for part in parts if part)
    return line or None


def _owned(db: DbSession, request_id: uuid.UUID, customer):  # noqa: ANN001, ANN202
    return request_service.get_request_for_customer(
        db, request_id=request_id, customer_id=customer.profile.id
    )


def _has_unread_updates(db: DbSession, request_id: uuid.UUID) -> bool:
    return (
        db.execute(
            select(func.count(Notification.id)).where(
                Notification.request_id == request_id,
                Notification.is_read.is_(False),
            )
        ).scalar_one()
        or 0
    ) > 0


@router.get(
    "",
    response_model=Page[OrderListItem],
    summary="Order list with Arabic status labels",
)
def list_orders(
    db: DbSession,
    customer: CurrentCustomer,
    page: int = Query(default=1, ge=1),
    per_page: int = Query(default=20, ge=1, le=100),
) -> Page[OrderListItem]:
    rows, total = request_service.list_requests_for_customer(
        db, customer_id=customer.profile.id, page=page, per_page=per_page
    )
    items: list[OrderListItem] = []
    for row in rows:
        category = db.get(ServiceCategory, row.category_id)
        prop = db.get(Property, row.property_id)
        quote = payment_service.accepted_quote(db, request_id=row.id)
        items.append(
            OrderListItem(
                request_id=row.id,
                reference_code=row.reference_code,
                status=RequestStatus(row.status),
                status_label_ar=REQUEST_STATUS_LABELS.get(RequestStatus(row.status), ""),
                category_name_ar=category.name_ar if category else "",
                category_icon_key=category.icon_key if category else "wrench",
                urgency=URGENCY_LABELS.get(row.urgency, row.urgency.value),
                property_label=prop.label if prop else "",
                created_at=row.created_at,
                submitted_at=row.submitted_at,
                completed_at=row.completed_at,
                total=str(quote.total) if quote else None,
                has_complaint=row.has_complaint,
                has_unread_updates=_has_unread_updates(db, row.id),
            )
        )
    return Page[OrderListItem].build(
        items=items, total=total, page=page, per_page=per_page
    )


@router.get(
    "/{request_id}",
    response_model=OrderTrackingResponse,
    summary="Order tracking detail",
)
def track_order(
    request_id: uuid.UUID, db: DbSession, customer: CurrentCustomer
) -> OrderTrackingResponse:
    request = _owned(db, request_id, customer)
    status = RequestStatus(request.status)

    assignment = dispatch_service.find_assignment(db, request_id=request.id)
    technician_summary = None
    actual_arrival = None
    work_started_at = None
    work_completed_at = None
    expected: ExpectedArrival | None = None
    if assignment is not None:
        technician = db.get(Technician, assignment.technician_id)
        if technician is not None:
            technician_summary = {
                "display_name": dispatch_service.technician_first_name(
                    technician.name
                ),
                "company_label_ar": "فريق الخدمة",
            }
        actual_arrival = assignment.actual_arrival
        work_started_at = assignment.work_started_at
        work_completed_at = assignment.work_completed_at
        if assignment.expected_arrival_start is not None:
            expected = ExpectedArrival(
                start=assignment.expected_arrival_start,
                end=assignment.expected_arrival_end,
            )

    events = request_service.timeline_for_customer(
        db, request=request, customer_id=customer.profile.id
    )
    return OrderTrackingResponse(
        request_id=request.id,
        reference_code=request.reference_code,
        status=status,
        status_label_ar=REQUEST_STATUS_LABELS.get(status, ""),
        status_description_ar=dashboard_service.NEXT_STEP_AR.get(status, ""),
        urgency=URGENCY_LABELS.get(request.urgency, request.urgency.value),
        expected_arrival=expected,
        actual_arrival=actual_arrival,
        work_started_at=work_started_at,
        work_completed_at=work_completed_at,
        service_completed_at=request.completed_at,
        technician=technician_summary,
        address_summary_ar=_address_line(db, request),
        events=[RequestEventResponse.model_validate(event) for event in events],
        can_cancel=status in order_service.CANCELLABLE_STATUSES,
        can_open_complaint=order_service.can_customer_complain(db, request=request),
        can_rate=order_service.can_customer_rate(db, request=request),
    )