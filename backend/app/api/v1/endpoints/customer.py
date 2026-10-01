"""Home dashboard, notifications, profile and analytics ingestion (§20, §24, §79)."""

from __future__ import annotations

from fastapi import APIRouter, Query

from app.api.dependencies import CurrentCustomer, DbSession
from app.schemas.common import MessageResponse
from app.schemas.support import (
    DeviceTokenRequest,
    MarkNotificationsReadRequest,
    NotificationResponse,
    ProfileResponse,
    RecordAnalyticsEventRequest,
    UpdateProfileRequest,
)
from app.services import analytics_service, dashboard_service, notification_service

router = APIRouter(tags=["customer"])


@router.get("/home", response_model=dict, summary="Home dashboard payload")
def home(db: DbSession, customer: CurrentCustomer) -> dict:
    return dashboard_service.home_payload(db, customer_id=customer.profile.id)


@router.get("/profile", response_model=ProfileResponse, summary="Profile with totals")
def profile(db: DbSession, customer: CurrentCustomer) -> ProfileResponse:
    payload = dashboard_service.profile_payload(
        db,
        customer_id=customer.profile.id,
        phone=customer.user.phone,
        created_at=customer.profile.created_at,
    )
    return ProfileResponse(
        id=customer.profile.id,
        full_name=customer.profile.full_name,
        avatar_url=customer.profile.avatar_url,
        preferred_language=customer.profile.preferred_language,
        **payload,
    )


@router.patch("/profile", response_model=ProfileResponse, summary="Update profile")
def update_profile(
    payload: UpdateProfileRequest, db: DbSession, customer: CurrentCustomer
) -> ProfileResponse:
    data = payload.model_dump(exclude_unset=True)
    for field, value in data.items():
        setattr(customer.profile, field, value)
    db.commit()
    return profile(db, customer)


@router.get(
    "/notifications",
    response_model=list[NotificationResponse],
    summary="My notifications",
)
def list_notifications(
    db: DbSession,
    customer: CurrentCustomer,
    unread_only: bool = Query(default=False),
    limit: int = Query(default=50, ge=1, le=200),
) -> list[NotificationResponse]:
    rows, _total = notification_service.list_for_customer(
        session=db,
        customer_id=customer.profile.id,
        page=1,
        per_page=limit,
        unread_only=unread_only,
    )
    return [NotificationResponse.model_validate(row) for row in rows]


@router.post(
    "/notifications/read",
    response_model=MessageResponse,
    summary="Mark notifications as read",
)
def mark_notifications_read(
    payload: MarkNotificationsReadRequest, db: DbSession, customer: CurrentCustomer
) -> MessageResponse:
    notification_service.mark_read(
        session=db, customer_id=customer.profile.id, ids=payload.ids
    )
    db.commit()
    return MessageResponse(message="تم تعليم الإشعارات كمقروءة.")


@router.get(
    "/notifications/unread-count",
    response_model=dict,
    summary="Unread badge counts",
)
def unread_counts(db: DbSession, customer: CurrentCustomer) -> dict:
    from app.services import support_service

    return {
        "notifications": notification_service.unread_count(
            session=db, customer_id=customer.profile.id
        ),
        "chat": support_service.unread_chat_count(
            session=db, customer_id=customer.profile.id
        ),
    }


@router.post(
    "/devices",
    response_model=MessageResponse,
    status_code=201,
    summary="Register a push token",
)
def register_device(
    payload: DeviceTokenRequest, db: DbSession, customer: CurrentCustomer
) -> MessageResponse:
    notification_service.register_device_token(
        session=db,
        customer_id=customer.profile.id,
        token=payload.token,
        platform=payload.platform,
        app_version=payload.app_version,
    )
    db.commit()
    return MessageResponse(message="تم تسجيل الجهاز بنجاح.")


@router.post(
    "/analytics/events",
    response_model=MessageResponse,
    status_code=202,
    summary="Ingest a client analytics event",
)
def record_event(
    payload: RecordAnalyticsEventRequest, db: DbSession, customer: CurrentCustomer
) -> MessageResponse:
    analytics_service.record_event(
        session=db,
        event_name=payload.event_name,
        customer_id=customer.profile.id,
        request_id=payload.request_id,
        session_id=payload.session_id,
        platform=payload.platform,
        app_version=payload.app_version,
        properties=payload.properties,
        occurred_at=payload.occurred_at,
    )
    db.commit()
    return MessageResponse(message="تم التسجيل.")