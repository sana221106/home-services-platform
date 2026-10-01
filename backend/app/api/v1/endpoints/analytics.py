"""Analytics, audit log and health endpoints (§79, §110)."""

from __future__ import annotations

import uuid
from datetime import timedelta
from typing import Annotated

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select

from app.api.dependencies import DbSession, require
from app.core.enums import Permission
from app.schemas.admin import (
    AreaAnalyticsRow,
    AuditLogResponse,
    CategoryAnalyticsRow,
    FunnelBucket,
    OverviewResponse,
    TechnicianUtilisationRow,
)
from app.schemas.common import Page
from app.services import analytics_service, audit_service
from app.utils.time import now_utc

router = APIRouter(tags=["analytics"])

AnalyticsGuard = Annotated[..., Depends(require(Permission.ANALYTICS_READ))]
AuditGuard = Annotated[..., Depends(require(Permission.AUDIT_READ))]


@router.get("/staff/analytics/overview", response_model=OverviewResponse, summary="Dashboard")
def overview(
    db: DbSession,
    _staff: AnalyticsGuard,
    days: int = Query(default=30, ge=1, le=365),
    target: int = Query(default=30, ge=1),
) -> OverviewResponse:
    from decimal import Decimal

    from app.core.enums import RequestStatus
    from app.db.models.requests import ServiceRequest
    from app.db.models.support import Complaint
    from app.db.models.finance import Payment, PaymentStatus
    from sqlalchemy import func

    end = now_utc()
    start = end - timedelta(days=days)
    total_requests = analytics_service.requests_in_period(
        db, start=start, end=end
    )
    completed = analytics_service.completed_orders_in_period(
        db, start=start, end=end
    )
    open_requests = int(
        db.execute(
            select(func.count(ServiceRequest.id)).where(
                ServiceRequest.status.notin_(
                    [RequestStatus.CLOSED, RequestStatus.CANCELLED, RequestStatus.RESOLVED]
                )
            )
        ).scalar_one()
    )
    awaiting_quote = int(
        db.execute(
            select(func.count(ServiceRequest.id)).where(
                ServiceRequest.status.in_(
                    [
                        RequestStatus.UNDER_REVIEW,
                        RequestStatus.QUOTE_PREPARATION,
                        RequestStatus.INSPECTION_SCHEDULED,
                        RequestStatus.INSPECTION_IN_PROGRESS,
                    ]
                )
            )
        ).scalar_one()
    )
    awaiting_payment = int(
        db.execute(
            select(func.count(ServiceRequest.id)).where(
                ServiceRequest.status.in_(
                    [
                        RequestStatus.DEPOSIT_PENDING,
                        RequestStatus.PAYMENT_PENDING,
                        RequestStatus.PAYMENT_VERIFICATION,
                    ]
                )
            )
        ).scalar_one()
    )
    open_complaints = int(
        db.execute(
            select(func.count(Complaint.id)).where(
                Complaint.status.notin_(["RESOLVED", "CLOSED"])
            )
        ).scalar_one()
    )
    revenue = db.execute(
        select(func.coalesce(func.sum(Payment.amount), 0)).where(
            Payment.status == PaymentStatus.VERIFIED,
            Payment.created_at.between(start, end),
        )
    ).scalar_one()
    progress = min(1.0, completed / target) if target else 0.0
    return OverviewResponse(
        period_start=start,
        period_end=end,
        total_requests=total_requests,
        completed_orders=completed,
        completion_rate=round(completed / total_requests, 4) if total_requests else 0.0,
        open_requests=open_requests,
        awaiting_quote=awaiting_quote,
        awaiting_payment=awaiting_payment,
        open_complaints=open_complaints,
        total_revenue=Decimal(str(revenue)),
        active_customers=analytics_service.active_customers_in_period(
            db, start=start, end=end
        ),
        completed_orders_target=target,
        target_progress=round(progress, 4),
    )


@router.get(
    "/staff/analytics/funnel",
    response_model=list[FunnelBucket],
    summary="Request funnel with stage conversion",
)
def funnel(db: DbSession, _staff: AnalyticsGuard) -> list[FunnelBucket]:
    counts = analytics_service.funnel_counts(db)
    buckets: list[FunnelBucket] = []
    previous: int | None = None
    for stage, label in analytics_service.FUNNEL_STAGES:
        count = counts.get(stage, 0)
        buckets.append(
            FunnelBucket(
                stage=stage,
                label_ar=label,
                count=count,
                conversion_from_previous=(
                    round(count / previous, 4) if previous else None
                ),
            )
        )
        previous = count or previous
    return buckets


@router.get(
    "/staff/analytics/areas",
    response_model=list[AreaAnalyticsRow],
    summary="Area analytics (§18)",
)
def areas(db: DbSession, _staff: AnalyticsGuard) -> list[AreaAnalyticsRow]:
    return analytics_service.area_rows(db)


@router.get(
    "/staff/analytics/categories",
    response_model=list[CategoryAnalyticsRow],
    summary="Category analytics",
)
def categories(db: DbSession, _staff: AnalyticsGuard) -> list[CategoryAnalyticsRow]:
    return analytics_service.category_rows(db)


@router.get(
    "/staff/analytics/technicians",
    response_model=list[TechnicianUtilisationRow],
    summary="Technician utilisation",
)
def technician_rows(
    db: DbSession, _staff: AnalyticsGuard
) -> list[TechnicianUtilisationRow]:
    return analytics_service.technician_rows(db)


@router.get(
    "/staff/audit-logs",
    response_model=Page[AuditLogResponse],
    summary="Audit trail",
)
def audit_logs(
    db: DbSession,
    _staff: AuditGuard,
    page: int = Query(default=1, ge=1),
    per_page: int = Query(default=50, ge=1, le=200),
    entity: str | None = Query(default=None, max_length=64),
    actor_id: uuid.UUID | None = Query(default=None),
) -> Page[AuditLogResponse]:
    rows, total = audit_service.list_audit_logs(
        db, page=page, per_page=per_page, entity=entity, actor_id=actor_id
    )
    return Page[AuditLogResponse].build(
        items=[AuditLogResponse.model_validate(row) for row in rows],
        total=total,
        page=page,
        per_page=per_page,
    )
