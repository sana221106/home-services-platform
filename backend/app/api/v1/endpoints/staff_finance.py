"""Finance endpoints: record, verify, refund (§68, §76).

Verification and refund approval are separated so a single role cannot both
record and approve its own entry (§76).
"""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select

from app.api.dependencies import AuthenticatedStaff, DbSession, require
from app.core.enums import Permission
from app.db.models.finance import Payment
from app.schemas.finance import (
    AdminRecordPaymentRequest,
    AdminVerifyPaymentRequest,
    CreateRefundRequest,
    DepositResponse,
    PaymentSummaryResponse,
    RefundResponse,
)
from app.services import audit_service, payment_service, request_service

router = APIRouter(prefix="/staff", tags=["staff-finance"])

ReadGuard = Annotated[AuthenticatedStaff, Depends(require(Permission.PAYMENT_READ))]
RecordGuard = Annotated[AuthenticatedStaff, Depends(require(Permission.PAYMENT_RECORD))]
VerifyGuard = Annotated[AuthenticatedStaff, Depends(require(Permission.PAYMENT_VERIFY))]
RefundApproveGuard = Annotated[AuthenticatedStaff, Depends(require(Permission.REFUND_APPROVE))]


@router.get(
    "/payments",
    response_model=list[PaymentSummaryResponse],
    summary="Payments awaiting verification",
)
def list_payments(
    db: DbSession,
    _staff: ReadGuard,
    limit: int = Query(default=50, ge=1, le=200),
) -> list[PaymentSummaryResponse]:
    rows = list(
        db.execute(
            select(Payment).order_by(Payment.created_at.desc()).limit(limit)
        ).scalars()
    )
    return [PaymentSummaryResponse.model_validate(row) for row in rows]


@router.post(
    "/requests/{request_id}/payments",
    response_model=PaymentSummaryResponse,
    status_code=201,
    summary="Record a payment taken outside the app",
)
def record_payment(
    request_id: uuid.UUID,
    payload: AdminRecordPaymentRequest,
    db: DbSession,
    staff: RecordGuard,
) -> PaymentSummaryResponse:
    request = request_service.get_request_for_staff(db, request_id=request_id)
    payment = payment_service.record_payment_by_staff(
        db,
        request=request,
        staff_id=staff.staff.id,
        staff_role=staff.roles[0] if staff.roles else None,
        amount=payload.amount,
        method=payload.method,
        reference_number=payload.reference_number,
        is_deposit=payload.is_deposit,
        notes=payload.notes,
        idempotency_key=payload.idempotency_key,
    )
    audit_service.record_audit(
        db,
        actor_id=staff.staff.id,
        actor_role=staff.roles[0] if staff.roles else None,
        action="PAYMENT_RECORDED",
        entity="payment",
        entity_id=payment.id,
        after={"amount": str(payload.amount), "method": payload.method.value},
    )
    db.commit()
    return PaymentSummaryResponse.model_validate(payment)


@router.post(
    "/payments/{payment_id}/verify",
    response_model=PaymentSummaryResponse,
    summary="Verify or reject submitted payment evidence",
)
def verify_payment(
    payment_id: uuid.UUID,
    payload: AdminVerifyPaymentRequest,
    db: DbSession,
    staff: VerifyGuard,
) -> PaymentSummaryResponse:
    payment = db.get(Payment, payment_id)
    if payment is None:
        from app.core.exceptions import NotFoundError

        raise NotFoundError("Payment not found.")
    updated = payment_service.verify_payment(
        db,
        payment=payment,
        staff_id=staff.staff.id,
        staff_role=staff.roles[0] if staff.roles else None,
        approved=payload.approved,
        rejection_reason=payload.rejection_reason,
    )
    audit_service.record_audit(
        db,
        actor_id=staff.staff.id,
        actor_role=staff.roles[0] if staff.roles else None,
        action="PAYMENT_VERIFIED" if payload.approved else "PAYMENT_REJECTED",
        entity="payment",
        entity_id=payment.id,
        after={"status": updated.status.value},
    )
    db.commit()
    return PaymentSummaryResponse.model_validate(updated)


@router.post(
    "/refunds",
    response_model=RefundResponse,
    status_code=201,
    summary="Raise a refund (requires a separate approval to process)",
)
def create_refund(
    payload: CreateRefundRequest,
    db: DbSession,
    staff: RecordGuard,
) -> RefundResponse:
    payment = db.get(Payment, payload.payment_id)
    if payment is None:
        from app.core.exceptions import NotFoundError

        raise NotFoundError("Payment not found.")
    refund = payment_service.create_refund(
        db,
        payment=payment,
        staff_id=staff.staff.id,
        staff_role=staff.roles[0] if staff.roles else None,
        amount=payload.amount,
        reason=payload.reason,
        idempotency_key=payload.idempotency_key,
    )
    db.commit()
    return RefundResponse.model_validate(refund)


@router.post(
    "/refunds/{refund_id}/process",
    response_model=RefundResponse,
    summary="Approve and process an approved refund",
)
def process_refund(
    refund_id: uuid.UUID, db: DbSession, staff: RefundApproveGuard
) -> RefundResponse:
    from app.db.models.finance import Refund

    refund = db.get(Refund, refund_id)
    if refund is None:
        from app.core.exceptions import NotFoundError

        raise NotFoundError("Refund not found.")
    payment_service.approve_refund(
        db,
        refund=refund,
        staff_id=staff.staff.id,
        staff_role=staff.roles[0] if staff.roles else None,
    )
    updated = payment_service.process_refund(
        db,
        refund=refund,
        staff_id=staff.staff.id,
        staff_role=staff.roles[0] if staff.roles else None,
    )
    audit_service.record_audit(
        db,
        actor_id=staff.staff.id,
        actor_role=staff.roles[0] if staff.roles else None,
        action="REFUND_PROCESSED",
        entity="refund",
        entity_id=refund.id,
        after={"amount": str(updated.amount), "status": updated.status.value},
    )
    db.commit()
    return RefundResponse.model_validate(updated)


@router.get(
    "/requests/{request_id}/deposit",
    response_model=DepositResponse | None,
    summary="Deposit state for a request",
)
def deposit(
    request_id: uuid.UUID, db: DbSession, _staff: ReadGuard
) -> DepositResponse | None:
    from app.db.models.finance import Deposit

    row = db.execute(
        select(Deposit).where(Deposit.request_id == request_id)
    ).scalar_one_or_none()
    if row is None:
        return None
    return DepositResponse(
        request_id=row.request_id,
        required_amount=row.required_amount,
        paid_amount=row.paid_amount,
        refunded_amount=row.refunded_amount,
        status=row.status,
        due_at=row.due_at,
    )