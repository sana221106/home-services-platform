"""Payment, deposit and refund endpoints for customers (§32, §67, §13)."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, File, UploadFile
from sqlalchemy import select

from app.api.dependencies import CurrentCustomer, DbSession
from app.core.exceptions import NotFoundError, ValidationError
from app.db.models.finance import Deposit, Payment, Refund
from app.schemas.common import MessageResponse
from app.schemas.finance import (
    DepositResponse,
    PaymentSummaryResponse,
    PaymentViewResponse,
    RefundResponse,
    SubmitPaymentRequest,
)
from app.services import payment_service, request_service

router = APIRouter(tags=["payments"])

SUPPORT_PHONE = "+201000000000"

METHOD_LABELS = {
    "CASH": "نقدًا",
    "VODAFONE_CASH": "فودافون كاش",
    "INSTAPAY": "إنستا باي",
    "BANK_TRANSFER": "تحويل بنكي",
}


def _owned(db: DbSession, request_id: uuid.UUID, customer):  # noqa: ANN001, ANN202
    return request_service.get_request_for_customer(
        db, request_id=request_id, customer_id=customer.profile.id
    )


@router.get(
    "/requests/{request_id}/payment",
    response_model=PaymentViewResponse,
    summary="Everything the Payment screen needs",
)
def payment_view(
    request_id: uuid.UUID, db: DbSession, customer: CurrentCustomer
) -> PaymentViewResponse:
    request = _owned(db, request_id, customer)
    quote = payment_service.accepted_quote(db, request_id=request.id)
    deposit = payment_service.deposit_for_request(db, request_id=request.id)
    payments = payment_service.payments_for_request(db, request_id=request.id)
    return PaymentViewResponse(
        request_id=request.id,
        reference_code=request.reference_code,
        quote_total=quote.total if quote else None,
        deposit=(
            DepositResponse(
                request_id=deposit.request_id,
                required_amount=deposit.required_amount,
                paid_amount=deposit.paid_amount,
                refunded_amount=deposit.refunded_amount,
                status=deposit.status,
                due_at=deposit.due_at,
            )
            if deposit
            else None
        ),
        payments=[
            PaymentSummaryResponse.model_validate(payment) for payment in payments
        ],
        amount_due=payment_service.outstanding_amount(db, request_id=request.id),
        methods=list(METHOD_LABELS.keys()),
        support_phone=SUPPORT_PHONE,
        instructions_ar=(
            "أرسل المبلغ ثم أدخل الرقم المرجعي من رسالة التحويل. "
            "يتم التحقق من الدفع من فريق الشركة."
        ),
    )


@router.post(
    "/requests/{request_id}/payments",
    response_model=PaymentSummaryResponse,
    status_code=201,
    summary="Submit payment evidence (never self-declares 'verified')",
)
def submit_payment(
    request_id: uuid.UUID,
    payload: SubmitPaymentRequest,
    db: DbSession,
    customer: CurrentCustomer,
) -> PaymentSummaryResponse:
    request = _owned(db, request_id, customer)
    payment = payment_service.submit_customer_payment(
        db,
        request=request,
        method=payload.method,
        amount=payload.amount,
        reference_number=payload.reference_number,
        is_deposit=payload.is_deposit,
        idempotency_key=payload.idempotency_key,
    )
    db.commit()
    return PaymentSummaryResponse.model_validate(payment)


@router.get(
    "/requests/{request_id}/payments",
    response_model=list[PaymentSummaryResponse],
    summary="Payment history for a request",
)
def list_payments(
    request_id: uuid.UUID, db: DbSession, customer: CurrentCustomer
) -> list[PaymentSummaryResponse]:
    _owned(db, request_id, customer)
    rows = payment_service.payments_for_request(db, request_id=request_id)
    return [PaymentSummaryResponse.model_validate(row) for row in rows]


@router.post(
    "/requests/{request_id}/payments/{payment_id}/proof",
    response_model=MessageResponse,
    status_code=201,
    summary="Attach a payment receipt image",
)
def attach_proof(
    request_id: uuid.UUID,
    payment_id: uuid.UUID,
    db: DbSession,
    customer: CurrentCustomer,
    file: Annotated[UploadFile, File(description="JPEG/PNG/WebP receipt image")],
) -> MessageResponse:
    _owned(db, request_id, customer)
    payment = db.execute(
        select(Payment).where(
            Payment.id == payment_id, Payment.request_id == request_id
        )
    ).scalar_one_or_none()
    if payment is None:
        raise NotFoundError("Payment not found.")
    content = file.file.read()
    if not content:
        raise ValidationError("The uploaded file is empty.")
    payment_service.add_payment_proof(
        db,
        payment=payment,
        customer_id=customer.profile.id,
        content=content,
        declared_mime=file.content_type,
        filename=file.filename,
    )
    db.commit()
    return MessageResponse(message="تم رفع إثبات الدفع بنجاح.")


@router.get(
    "/requests/{request_id}/refunds",
    response_model=list[RefundResponse],
    summary="Refunds for a request",
)
def request_refunds(
    request_id: uuid.UUID, db: DbSession, customer: CurrentCustomer
) -> list[RefundResponse]:
    _owned(db, request_id, customer)
    rows = list(
        db.execute(
            select(Refund)
            .join(Payment, Payment.id == Refund.payment_id)
            .where(Payment.request_id == request_id)
            .order_by(Refund.created_at.desc())
        ).scalars()
    )
    return [RefundResponse.model_validate(row) for row in rows]


@router.get(
    "/requests/{request_id}/deposit",
    response_model=DepositResponse | None,
    summary="Deposit obligation",
)
def deposit_summary(
    request_id: uuid.UUID, db: DbSession, customer: CurrentCustomer
) -> DepositResponse | None:
    _owned(db, request_id, customer)
    deposit = db.execute(
        select(Deposit).where(Deposit.request_id == request_id)
    ).scalar_one_or_none()
    if deposit is None:
        return None
    return DepositResponse(
        request_id=deposit.request_id,
        required_amount=deposit.required_amount,
        paid_amount=deposit.paid_amount,
        refunded_amount=deposit.refunded_amount,
        status=deposit.status,
        due_at=deposit.due_at,
    )