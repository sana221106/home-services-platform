"""Analytics event constants (§113) and the funnel query (§3).

Client-reported events are accepted for UX funnel visibility; server-derived
events (``source='server'``) are the authoritative record used for reporting.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from decimal import Decimal
from typing import Any

from sqlalchemy import Integer, ScalarSelect, func, select
from sqlalchemy.orm import Session

from app.core.enums import PaymentStatus, RequestStatus, Urgency
from app.db.models.finance import Payment
from app.db.models.intelligence import AnalyticsEvent
from app.db.models.requests import ServiceRequest
from app.utils.time import now_utc


class AnalyticsEventName:
    APP_OPENED = "APP_OPENED"
    REGISTRATION_STARTED = "REGISTRATION_STARTED"
    REGISTRATION_COMPLETED = "REGISTRATION_COMPLETED"
    REQUEST_STARTED = "REQUEST_STARTED"
    SERVICE_SELECTED = "SERVICE_SELECTED"
    PROBLEM_DESCRIPTION_ADDED = "PROBLEM_DESCRIPTION_ADDED"
    REQUEST_MEDIA_ADDED = "REQUEST_MEDIA_ADDED"
    REQUEST_LOCATION_ADDED = "REQUEST_LOCATION_ADDED"
    REQUEST_SCHEDULE_SELECTED = "REQUEST_SCHEDULE_SELECTED"
    REQUEST_SUBMITTED = "REQUEST_SUBMITTED"
    REVIEW_STARTED = "REVIEW_STARTED"
    QUOTE_CREATED = "QUOTE_CREATED"
    QUOTE_SENT = "QUOTE_SENT"
    QUOTE_VIEWED = "QUOTE_VIEWED"
    QUOTE_ACCEPTED = "QUOTE_ACCEPTED"
    QUOTE_REJECTED = "QUOTE_REJECTED"
    TECHNICIAN_ASSIGNED = "TECHNICIAN_ASSIGNED"
    SERVICE_STARTED = "SERVICE_STARTED"
    ORDER_COMPLETED = "ORDER_COMPLETED"
    PAYMENT_RECORDED = "PAYMENT_RECORDED"
    PAYMENT_VERIFIED = "PAYMENT_VERIFIED"
    REVIEW_SUBMITTED = "REVIEW_SUBMITTED"
    COMPLAINT_CREATED = "COMPLAINT_CREATED"


#: Ordered funnel used by the North Star metric (§3).
FUNNEL_STAGES: tuple[tuple[str, str], ...] = (
    ("REQUEST_STARTED", "بدء الطلب"),
    ("SERVICE_SELECTED", "اختيار الخدمة"),
    ("PROBLEM_DESCRIPTION_ADDED", "وصف المشكلة"),
    ("REQUEST_MEDIA_ADDED", "إضافة صور"),
    ("REQUEST_LOCATION_ADDED", "تحديد الموقع"),
    ("REQUEST_SCHEDULE_SELECTED", "اختيار الموعد"),
    ("REQUEST_SUBMITTED", "تم إرسال الطلب"),
    ("REVIEW_STARTED", "بدء مراجعة الفريق"),
    ("QUOTE_CREATED", "إنشاء عرض السعر"),
    ("QUOTE_SENT", "إرسال عرض السعر"),
    ("QUOTE_VIEWED", "العميل شاهد العرض"),
    ("QUOTE_ACCEPTED", "العميل وافق"),
    ("TECHNICIAN_ASSIGNED", "تعيين الفني"),
    ("SERVICE_STARTED", "بدء الخدمة"),
    ("ORDER_COMPLETED", "اكتمال الطلب"),
    ("PAYMENT_RECORDED", "تسجيل الدفع"),
    ("REVIEW_SUBMITTED", "تقييم العميل"),
)


def record_event(
    session: Session,
    *,
    event_name: str,
    source: str = "server",
    customer_id: uuid.UUID | None = None,
    request_id: uuid.UUID | None = None,
    session_id: str | None = None,
    platform: str | None = None,
    app_version: str | None = None,
    properties: dict[str, Any] | None = None,
    occurred_at: datetime | None = None,
) -> AnalyticsEvent:
    event = AnalyticsEvent(
        event_name=event_name,
        source=source,
        customer_id=customer_id,
        request_id=request_id,
        session_id=session_id,
        platform=platform,
        app_version=app_version,
        properties=properties,
        occurred_at=occurred_at or now_utc(),
    )
    session.add(event)
    session.flush()
    return event


def _stage_stmt(stage: str) -> ScalarSelect[int]:
    """A correlated scalar subquery, not a Select, despite the select() call."""
    return (
        select(func.count(func.distinct(AnalyticsEvent.request_id)))
        .where(
            AnalyticsEvent.event_name == stage,
            AnalyticsEvent.request_id.is_not(None),
            AnalyticsEvent.source == "server",
        )
        .scalar_subquery()
    )


def funnel_counts(session: Session, *, since: datetime | None = None) -> dict[str, int]:
    """Server-side funnel. ``REQUEST_STARTED`` has no request id yet, so it is
    counted by customer instead of by request."""
    conditions = []
    if since is not None:
        conditions.append(AnalyticsEvent.occurred_at >= since)

    counts: dict[str, int] = {}
    for stage, _label in FUNNEL_STAGES:
        if stage == "REQUEST_STARTED":
            base = select(func.count(func.distinct(AnalyticsEvent.customer_id))).where(
                AnalyticsEvent.event_name == stage, AnalyticsEvent.source == "server"
            )
        else:
            base = select(func.count(func.distinct(AnalyticsEvent.request_id))).where(
                AnalyticsEvent.event_name == stage,
                AnalyticsEvent.request_id.is_not(None),
                AnalyticsEvent.source == "server",
            )
        if conditions:
            base = base.where(*conditions)
        counts[stage] = int(session.execute(base).scalar_one() or 0)
    return counts


def completed_orders_in_period(session: Session, *, start: datetime, end: datetime) -> int:
    return int(
        session.execute(
            select(func.count(ServiceRequest.id)).where(
                ServiceRequest.completed_at.is_not(None),
                ServiceRequest.completed_at >= start,
                ServiceRequest.completed_at < end,
            )
        ).scalar_one()
        or 0
    )


def requests_in_period(session: Session, *, start: datetime, end: datetime) -> int:
    return int(
        session.execute(
            select(func.count(ServiceRequest.id)).where(
                ServiceRequest.created_at >= start,
                ServiceRequest.created_at < end,
            )
        ).scalar_one()
        or 0
    )


def active_customers_in_period(session: Session, *, start: datetime, end: datetime) -> int:
    return int(
        session.execute(
            select(func.count(func.distinct(ServiceRequest.customer_id))).where(
                ServiceRequest.created_at >= start,
                ServiceRequest.created_at < end,
            )
        ).scalar_one()
        or 0
    )


def completed_since(session: Session, *, customer_id: uuid.UUID) -> int:
    return int(
        session.execute(
            select(func.count(ServiceRequest.id)).where(
                ServiceRequest.customer_id == customer_id,
                ServiceRequest.completed_at.is_not(None),
            )
        ).scalar_one()
        or 0
    )


def total_spent_by_customer(session: Session, *, customer_id: uuid.UUID) -> Decimal:
    total = session.execute(
        select(func.coalesce(func.sum(Payment.amount), 0)).where(
            Payment.customer_id == customer_id,
            Payment.status == PaymentStatus.VERIFIED,
        )
    ).scalar_one()
    return Decimal(str(total or 0))


def requests_by_status(
    session: Session, *, customer_id: uuid.UUID | None = None
) -> dict[RequestStatus, int]:
    stmt = select(ServiceRequest.status, func.count(ServiceRequest.id)).group_by(
        ServiceRequest.status
    )
    if customer_id is not None:
        stmt = stmt.where(ServiceRequest.customer_id == customer_id)
    rows = session.execute(stmt).all()
    return {status: int(count) for status, count in rows}


def urgent_request_count(
    session: Session, *, start: datetime, end: datetime
) -> int:
    return int(
        session.execute(
            select(func.count(ServiceRequest.id)).where(
                ServiceRequest.urgency == Urgency.URGENT,
                ServiceRequest.created_at >= start,
                ServiceRequest.created_at < end,
            )
        ).scalar_one()
        or 0
    )


# ------------------------------------------------------------------ rollups


def area_rows(session: Session) -> list[Any]:
    """Area performance (§18). Every row is derived from stored snapshots, never
    from a live geolocation call."""
    from app.db.models.catalog import ServiceAreaSnapshot
    from app.db.models.support import Complaint

    rows = session.execute(
        select(
            ServiceAreaSnapshot.governorate,
            ServiceAreaSnapshot.city,
            ServiceAreaSnapshot.zone,
            ServiceAreaSnapshot.district,
            func.count(ServiceRequest.id).label("requests"),
            func.sum(
                func.cast(ServiceRequest.completed_at.is_not(None), Integer)
            ).label("completed"),
            func.sum(
                func.cast(ServiceRequest.urgency == Urgency.URGENT, Integer)
            ).label("urgent"),
            func.sum(
                func.cast(
                    ServiceRequest.inspection_required.is_(True),
                    Integer,
                )
            ).label("inspections"),
        )
        .select_from(ServiceAreaSnapshot)
        .join(ServiceRequest, ServiceRequest.id == ServiceAreaSnapshot.request_id)
        .group_by(
            ServiceAreaSnapshot.governorate,
            ServiceAreaSnapshot.city,
            ServiceAreaSnapshot.zone,
            ServiceAreaSnapshot.district,
        )
    ).all()

    complaint_counts = {
        (row[0], row[1]): int(row[2])
        for row in session.execute(
            select(
                ServiceAreaSnapshot.city,
                ServiceAreaSnapshot.governorate,
                func.count(Complaint.id),
            )
            .select_from(ServiceAreaSnapshot)
            .join(Complaint, Complaint.request_id == ServiceAreaSnapshot.request_id)
            .group_by(ServiceAreaSnapshot.city, ServiceAreaSnapshot.governorate)
        ).all()
    }
    revenue_rows = {
        (row[0], row[1]): Decimal(str(row[2] or 0))
        for row in session.execute(
            select(
                ServiceAreaSnapshot.city,
                ServiceAreaSnapshot.governorate,
                func.coalesce(func.sum(Payment.amount), 0),
            )
            .select_from(ServiceAreaSnapshot)
            .join(Payment, Payment.request_id == ServiceAreaSnapshot.request_id)
            .where(Payment.status == PaymentStatus.VERIFIED)
            .group_by(ServiceAreaSnapshot.city, ServiceAreaSnapshot.governorate)
        ).all()
    }

    from app.schemas.admin import AreaAnalyticsRow

    results: list[AreaAnalyticsRow] = []
    for governorate, city, zone, district, requests, completed, urgent, inspections in rows:
        results.append(
            AreaAnalyticsRow(
                governorate=governorate,
                city=city,
                zone=zone,
                district=district,
                requests=int(requests or 0),
                completed=int(completed or 0),
                urgent=int(urgent or 0),
                inspections_required=int(inspections or 0),
                complaints=complaint_counts.get((city, governorate), 0),
                revenue=revenue_rows.get((city, governorate), Decimal("0")),
            )
        )
    results.sort(key=lambda item: item.requests, reverse=True)
    return results


def category_rows(session: Session) -> list[Any]:
    from app.db.models.catalog import ServiceCategory
    from app.db.models.support import Review
    from app.schemas.admin import CategoryAnalyticsRow

    rows = session.execute(
        select(
            ServiceCategory.code,
            ServiceCategory.name_ar,
            func.count(ServiceRequest.id),
            func.sum(
                func.cast(
                    ServiceRequest.status == RequestStatus.CLOSED,
                    Integer,
                )
            ),
        )
        .select_from(ServiceCategory)
        .join(ServiceRequest, ServiceRequest.category_id == ServiceCategory.id)
        .group_by(ServiceCategory.code, ServiceCategory.name_ar)
    ).all()

    revenue = {
        row[0]: Decimal(str(row[1] or 0))
        for row in session.execute(
            select(ServiceRequest.category_id, func.coalesce(func.sum(Payment.amount), 0))
            .join(Payment, Payment.request_id == ServiceRequest.id)
            .where(Payment.status == PaymentStatus.VERIFIED)
            .group_by(ServiceRequest.category_id)
        ).all()
    }
    ratings = {
        row[0]: float(row[1])
        for row in session.execute(
            select(ServiceRequest.category_id, func.avg(Review.rating))
            .join(Review, Review.request_id == ServiceRequest.id)
            .group_by(ServiceRequest.category_id)
        ).all()
        if row[1] is not None
    }

    results: list[CategoryAnalyticsRow] = []
    for code, name_ar, requests, completed in rows:
        category = session.execute(
            select(ServiceCategory).where(ServiceCategory.code == code)
        ).scalar_one()
        results.append(
            CategoryAnalyticsRow(
                category_code=code,
                category_name_ar=name_ar,
                requests=int(requests or 0),
                completed=int(completed or 0),
                revenue=revenue.get(category.id, Decimal("0")),
                avg_rating=ratings.get(category.id),
            )
        )
    results.sort(key=lambda item: item.requests, reverse=True)
    return results


def technician_rows(session: Session) -> list[Any]:
    from app.db.models.workforce import Assignment, Technician
    from app.schemas.admin import TechnicianUtilisationRow

    technicians = list(session.execute(select(Technician)).scalars())
    results: list[TechnicianUtilisationRow] = []
    for technician in technicians:
        assignments = int(
            session.execute(
                select(func.count(Assignment.id)).where(
                    Assignment.technician_id == technician.id
                )
            ).scalar_one()
        )
        capacity = max(1, technician.total_assignments)
        minutes = session.execute(
            select(
                func.avg(
                    func.extract(
                        "epoch", Assignment.work_completed_at - Assignment.work_started_at
                    )
                )
            ).where(
                Assignment.technician_id == technician.id,
                Assignment.work_completed_at.is_not(None),
            )
        ).scalar_one()
        results.append(
            TechnicianUtilisationRow(
                technician_id=technician.id,
                technician_name=technician.name,
                assignments=assignments,
                completed=technician.completed_assignments,
                late=technician.late_arrivals,
                no_shows=technician.no_show_count,
                utilisation_percent=round(assignments / capacity, 4),
                avg_completion_minutes=round(float(minutes) / 60, 2) if minutes else None,
            )
        )
    results.sort(key=lambda item: item.assignments, reverse=True)
    return results