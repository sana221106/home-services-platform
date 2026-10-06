"""Home dashboard aggregation and the customer 360 view (§20, §74, §79).

Every number the Home and Profile screens show is resolved here so the client
never derives totals from lists it happens to have loaded (§20).
"""

from __future__ import annotations

import uuid
from datetime import timedelta
from decimal import Decimal
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.enums import ComplaintStatus, RequestStatus
from app.db.models.catalog import ServiceCategory
from app.db.models.finance import Deposit, Payment, PaymentStatus
from app.db.models.properties import Property
from app.db.models.requests import ServiceRequest
from app.services import analytics_service, notification_service, support_service
from app.utils.time import hours_between, now_utc


def home_payload(session: Session, *, customer_id: uuid.UUID) -> dict[str, Any]:
    counts = _status_counts(session, customer_id=customer_id)
    active = counts.get("active", 0)
    awaiting_payment = counts.get(RequestStatus.PAYMENT_PENDING.value, 0)
    awaiting_payment += counts.get(RequestStatus.PAYMENT_VERIFICATION.value, 0)
    awaiting_rating = counts.get(RequestStatus.AWAITING_RATING.value, 0)
    open_quotes = counts.get(RequestStatus.AWAITING_CUSTOMER_APPROVAL.value, 0)
    open_quotes += counts.get(RequestStatus.QUOTE_SENT.value, 0)

    categories = list(
        session.execute(
            select(ServiceCategory)
            .where(ServiceCategory.is_active.is_(True), ServiceCategory.deleted_at.is_(None))
            .order_by(ServiceCategory.sort_order.asc())
        ).scalars()
    )

    active_rows = list(
        session.execute(
            select(ServiceRequest)
            .where(ServiceRequest.customer_id == customer_id, _is_active_filter())
            .order_by(ServiceRequest.updated_at.desc())
            .limit(3)
        ).scalars()
    )

    return {
        "greeting": {
            "active_requests": active,
            "awaiting_payment": awaiting_payment,
            "awaiting_rating": awaiting_rating,
            "open_quotes": open_quotes,
        },
        "categories": [
            {
                "id": category.id,
                "code": category.code,
                "name_ar": category.name_ar,
                "icon_key": category.icon_key,
                "color_hex": category.color_hex,
            }
            for category in categories
        ],
        "quick_actions": [
            {"code": "NEW_REQUEST", "label_ar": "طلب خدمة جديد"},
            {"code": "PAYMENT", "label_ar": "الدفع"},
            {"code": "TRACK", "label_ar": "تتبع طلب"},
            {"code": "SUPPORT", "label_ar": "الدعم الفني"},
        ],
        "active_requests": [
            {
                "request_id": row.id,
                "reference_code": row.reference_code,
                "status": row.status,
                "category_name_ar": _category_name(session, row.category_id),
                "next_step_ar": _next_step_ar(RequestStatus(row.status)),
            }
            for row in active_rows
        ],
        "unread_notifications": notification_service.unread_count(
            session, customer_id=customer_id
        ),
        "unread_chat": support_service.unread_chat_count(
            session, customer_id=customer_id
        ),
    }


def _is_active_filter():  # noqa: ANN202
    return ServiceRequest.status.in_(
        [
            RequestStatus.SUBMITTED,
            RequestStatus.UNDER_REVIEW,
            RequestStatus.QUOTE_PREPARATION,
            RequestStatus.QUOTE_SENT,
            RequestStatus.AWAITING_CUSTOMER_APPROVAL,
            RequestStatus.QUOTE_REJECTED,
            RequestStatus.NEED_MORE_INFORMATION,
            RequestStatus.INSPECTION_SCHEDULED,
            RequestStatus.INSPECTION_IN_PROGRESS,
            RequestStatus.INSPECTION_COMPLETED,
            RequestStatus.PAYMENT_PENDING,
            RequestStatus.PAYMENT_VERIFICATION,
            RequestStatus.TECHNICIAN_ASSIGNED,
            RequestStatus.ON_THE_WAY,
            RequestStatus.ARRIVED,
            RequestStatus.WORK_IN_PROGRESS,
            RequestStatus.SERVICE_COMPLETED,
            RequestStatus.AWAITING_RATING,
        ]
    )


def _status_counts(session: Session, *, customer_id: uuid.UUID) -> dict[str, int]:
    rows = session.execute(
        select(ServiceRequest.status, func.count(ServiceRequest.id))
        .where(ServiceRequest.customer_id == customer_id)
        .group_by(ServiceRequest.status)
    ).all()
    counts = {RequestStatus(status).value: int(total) for status, total in rows}
    counts["active"] = sum(
        total for status, total in counts.items() if status not in {"closed", "cancelled"}
    )
    return counts


def _category_name(session: Session, category_id: uuid.UUID) -> str:
    category = session.get(ServiceCategory, category_id)
    return category.name_ar if category else ""


NEXT_STEP_AR = {
    RequestStatus.SUBMITTED: "تم استلام طلبك وجارٍ مراجعته.",
    RequestStatus.UNDER_REVIEW: "جارٍ مراجعة طلبك وتحديد التفاصيل.",
    RequestStatus.QUOTE_PREPARATION: "جارٍ إعداد عرض السعر.",
    RequestStatus.QUOTE_SENT: "تم إرسال عرض السعر، بانتظار قرارك.",
    RequestStatus.AWAITING_CUSTOMER_APPROVAL: "بانتظار موافقتك على عرض السعر.",
    RequestStatus.QUOTE_REJECTED: "تم رفض العرض، جارٍ إعداد عرض بديل.",
    RequestStatus.NEED_MORE_INFORMATION: "نحتاج منك معلومات إضافية.",
    RequestStatus.INSPECTION_SCHEDULED: "تم جدولة المعاينة.",
    RequestStatus.INSPECTION_IN_PROGRESS: "المعاينة جارية الآن.",
    RequestStatus.INSPECTION_COMPLETED: "اكتملت المعاينة.",
    RequestStatus.PAYMENT_PENDING: "في انتظار الدفع.",
    RequestStatus.PAYMENT_VERIFICATION: "جارٍ التحقق من الدفع.",
    RequestStatus.TECHNICIAN_ASSIGNED: "تم تعيين فني من فريق الخدمة.",
    RequestStatus.ON_THE_WAY: "الفني في الطريق إليك.",
    RequestStatus.ARRIVED: "وصل الفني إلى موقع الخدمة.",
    RequestStatus.WORK_IN_PROGRESS: "العمل جارٍ التنفيذ.",
    RequestStatus.SERVICE_COMPLETED: "تم إنجاز الخدمة.",
    RequestStatus.AWAITING_RATING: "قيّم تجربتك من فضلك.",
    RequestStatus.PAID: "تمت العملية بنجاح.",
    RequestStatus.CLOSED: "طلب مكتمل.",
    RequestStatus.CANCELLED: "تم إلغاء الطلب.",
    RequestStatus.DRAFT: "لم يتم إرسال الطلب بعد.",
    RequestStatus.INSPECTION_REQUIRED: "المعاينة مطلوبة قبل عرض السعر.",
    RequestStatus.DEPOSIT_PENDING: "في انتظار الدفع المقدم.",
    RequestStatus.DEPOSIT_VERIFICATION: "جارٍ التحقق من الدفع المقدم.",
    RequestStatus.CONFIRMED: "تم تأكيد الحجز.",
    RequestStatus.TECHNICIAN_ASSIGNMENT_PENDING: "في انتظار تعيين فني من فريق الخدمة.",
    RequestStatus.COMPLAINT_OPEN: "تم استلام شكوى حول هذا الطلب.",
    RequestStatus.COMPLAINT_UNDER_REVIEW: "الشكوى قيد المراجعة.",
    RequestStatus.REVISIT_SCHEDULED: "تمت جدولة زيارة إصلاح.",
    RequestStatus.RESOLVED: "تم حل المشكلة.",
}


def _next_step_ar(status: RequestStatus) -> str:
    return NEXT_STEP_AR.get(status, "")


def profile_payload(session: Session, *, customer_id: uuid.UUID, phone: str, created_at=None) -> dict[str, Any]:
    return {
        "phone": phone,
        "properties_count": int(
            session.execute(
                select(func.count(Property.id)).where(
                    Property.customer_id == customer_id, Property.deleted_at.is_(None)
                )
            ).scalar_one()
        ),
        "requests_count": int(
            session.execute(
                select(func.count(ServiceRequest.id)).where(
                    ServiceRequest.customer_id == customer_id
                )
            ).scalar_one()
        ),
        "completed_orders_count": int(
            session.execute(
                select(func.count(ServiceRequest.id)).where(
                    ServiceRequest.customer_id == customer_id,
                    ServiceRequest.status
                    == RequestStatus.CLOSED,
                    ServiceRequest.has_complaint.is_(False),
                )
            ).scalar_one()
        ),
        "member_since": created_at,
    }


def customer_360(
    session: Session, *, customer_id: uuid.UUID, staff_id: uuid.UUID
) -> dict[str, Any]:
    """Internal single-page customer view for call-centre staff (§74)."""
    from app.db.models.identity import CustomerProfile
    from app.db.models.support import Complaint, Conversation, Review
    from app.services import complaint_service, request_service

    profile = session.get(CustomerProfile, customer_id)
    rows, _total = request_service.list_requests_for_customer(
        session, customer_id=customer_id, page=1, per_page=20
    )
    properties = list(
        session.execute(
            select(Property).where(
                Property.customer_id == customer_id, Property.deleted_at.is_(None)
            )
        ).scalars()
    )
    complaints, complaint_total = complaint_service.list_for_customer(
        session, customer_id=customer_id, page=1, per_page=20
    )
    conversations = list(
        session.execute(
            select(Conversation)
            .where(Conversation.customer_id == customer_id)
            .order_by(Conversation.last_message_at.desc())
            .limit(5)
        ).scalars()
    )
    reviews = list(
        session.execute(
            select(Review)
            .where(Review.customer_id == customer_id)
            .order_by(Review.created_at.desc())
            .limit(10)
        ).scalars()
    )
    open_complaints = int(
        session.execute(
            select(func.count(Complaint.id)).where(
                Complaint.customer_id == customer_id,
                Complaint.status.notin_(
                    [ComplaintStatus.RESOLVED, ComplaintStatus.CLOSED]
                ),
            )
        ).scalar_one()
    )
    outstanding = _outstanding_payments(session, customer_id=customer_id)
    segment = _segment(session, customer_id=customer_id)

    return {
        "customer": {
            "id": profile.id if profile else customer_id,
            "full_name": profile.full_name if profile else "",
            "phone": ((profile.user.phone or "") if profile and profile.user else ""),
            "email": profile.email if profile else None,
            "created_at": profile.created_at if profile else None,
        },
        "segment": segment,
        "totals": {
            "requests": analytics_service.completed_since(
                session, customer_id=customer_id
            ),
            "completed_orders": int(
                session.execute(
                    select(func.count(ServiceRequest.id)).where(
                        ServiceRequest.customer_id == customer_id,
                        ServiceRequest.status.in_(
                            [RequestStatus.CLOSED, RequestStatus.PAID, RequestStatus.AWAITING_RATING]
                        ),
                    )
                ).scalar_one()
            ),
            "total_spent": str(analytics_service.total_spent_by_customer(
                session, customer_id=customer_id
            )),
            "open_complaints": open_complaints,
            "outstanding_payments": str(outstanding),
        },
        "properties": [
            {
                "id": prop.id,
                "label": prop.label,
                "city": prop.city,
                "zone": prop.zone,
                "is_default": prop.is_default,
            }
            for prop in properties
        ],
        "requests": [
            {
                "id": row.id,
                "reference_code": row.reference_code,
                "status": row.status,
                "category_id": row.category_id,
                "created_at": row.created_at,
                "completed_at": row.completed_at,
                "has_complaint": row.has_complaint,
                "has_rework": row.has_rework,
            }
            for row in rows
        ],
        "complaints": [
            {
                "id": complaint.id,
                "reference_code": complaint.reference_code,
                "reason": complaint.reason,
                "status": complaint.status,
                "created_at": complaint.created_at,
                "requires_rework": complaint.requires_rework,
            }
            for complaint in complaints
        ],
        "conversations": [
            {
                "id": conversation.id,
                "subject": conversation.subject,
                "is_open": conversation.is_open,
                "last_message_at": conversation.last_message_at,
            }
            for conversation in conversations
        ],
        "reviews": [
            {
                "id": review.id,
                "rating": review.rating,
                "text": review.text,
                "created_at": review.created_at,
                "publication_status": review.publication_status,
            }
            for review in reviews
        ],
        "requested_by_staff_id": staff_id,
        "generated_at": now_utc(),
    }


def _outstanding_payments(session: Session, *, customer_id: uuid.UUID) -> Decimal:
    rows = session.execute(
        select(Payment.amount, Payment.amount_refunded)
        .join(ServiceRequest, ServiceRequest.id == Payment.request_id)
        .where(
            ServiceRequest.customer_id == customer_id,
            Payment.status.in_(
                [PaymentStatus.PENDING, PaymentStatus.VERIFICATION_PENDING, PaymentStatus.VERIFIED]
            ),
        )
    ).all()
    total = Decimal("0.00")
    for amount, refunded in rows:
        total += Decimal(amount or 0) - Decimal(refunded or 0)
    return total


def _segment(session: Session, *, customer_id: uuid.UUID) -> str:
    completed = analytics_service.completed_since(session, customer_id=customer_id)
    complaints = int(
        session.execute(
            select(func.count(ServiceRequest.id)).where(
                ServiceRequest.customer_id == customer_id,
                ServiceRequest.has_complaint.is_(True),
            )
        ).scalar_one()
    )
    if complaints > 0 and completed >= complaints * 2:
        return "AT_RISK"
    if completed >= 5:
        return "LOYAL"
    if completed == 0:
        return "NEW"
    return "ACTIVE"


def deposits_pending(session: Session, *, customer_id: uuid.UUID) -> list[Deposit]:
    """Open deposit obligations for the call centre follow-up queue."""
    return list(
        session.execute(
            select(Deposit)
            .join(ServiceRequest, ServiceRequest.id == Deposit.request_id)
            .where(
                ServiceRequest.customer_id == customer_id,
                Deposit.status.in_(["PENDING", "PARTIAL", "PAID"]),
            )
        ).scalars()
    )


def overdue_follow_ups(session: Session, *, hours: int = 24) -> list[dict[str, Any]]:
    """Requests with no movement for ``hours`` - the call centre's SLA list."""
    from app.services import request_service

    cutoff = now_utc() - timedelta(hours=hours)
    rows = session.execute(
        request_service.requests_needing_follow_up(session, since=cutoff)
    ).scalars()
    return [
        {
            "request_id": row.id,
            "reference_code": row.reference_code,
            "status": row.status,
            "submitted_at": row.submitted_at,
            "stalled_hours": (
                hours_between(row.submitted_at, now_utc()) if row.submitted_at else None
            ),
        }
        for row in rows
    ]