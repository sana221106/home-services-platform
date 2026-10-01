"""Payment, deposit, refund and cancellation-preview logic (§11-§13, §32).

Authority rules enforced here:

* a customer submission only ever produces ``VERIFICATION_PENDING``;
* ``VERIFIED`` requires a staff actor with ``payment:verify``;
* refund amounts are bounded by the captured amount minus what was already
  refunded, so a double refund is impossible even under a retry;
* every money mutation runs in a single transaction (§138).
"""

from __future__ import annotations

import uuid
from datetime import timedelta
from decimal import Decimal
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.enums import (
    AuditAction,
    DepositStatus,
    NotificationType,
    PaymentMethod,
    PaymentStatus,
    QuoteStatus,
    RefundStatus,
    RequestStatus,
)
from app.core.exceptions import ConflictError, NotFoundError, ValidationError
from app.core.logging import get_logger
from app.db.models.finance import Cancellation, Deposit, Payment, PaymentProof, Refund
from app.db.models.quotes import Quote
from app.db.models.requests import ServiceRequest
from app.services import analytics_service, notification_service, pricing_service, request_service
from app.services.analytics_service import AnalyticsEventName
from app.services.audit_service import record_audit
from app.utils.time import ensure_aware, now_utc

log = get_logger(__name__)

TWO_PLACES = Decimal("0.01")


def _q(value: Decimal) -> Decimal:
    return Decimal(value).quantize(TWO_PLACES)


# ------------------------------------------------------------------- queries


def payments_for_request(session: Session, *, request_id: uuid.UUID) -> list[Payment]:
    return list(
        session.execute(
            select(Payment).where(Payment.request_id == request_id).order_by(Payment.created_at.asc())
        ).scalars()
    )


def deposit_for_request(session: Session, *, request_id: uuid.UUID) -> Deposit | None:
    return session.execute(
        select(Deposit).where(Deposit.request_id == request_id)
    ).scalar_one_or_none()


def accepted_quote(session: Session, *, request_id: uuid.UUID) -> Quote | None:
    return session.execute(
        select(Quote)
        .where(Quote.request_id == request_id, Quote.status == QuoteStatus.ACCEPTED)
        .order_by(Quote.revision_number.desc())
        .limit(1)
    ).scalar_one_or_none()


def outstanding_amount(session: Session, *, request_id: uuid.UUID) -> Decimal:
    total = Decimal("0")
    quote = accepted_quote(session, request_id=request_id)
    if quote is not None:
        total = Decimal(quote.total)
    verified = Decimal("0")
    for payment in payments_for_request(session, request_id=request_id):
        if payment.status in {PaymentStatus.VERIFIED, PaymentStatus.PARTIALLY_REFUNDED}:
            verified += Decimal(payment.amount) - Decimal(payment.amount_refunded)
    return _q(max(Decimal("0"), total - verified))


# ------------------------------------------------------------ customer submit


def submit_customer_payment(
    session: Session,
    *,
    request: ServiceRequest,
    customer_id: uuid.UUID,
    method: PaymentMethod,
    amount: Decimal,
    reference_number: str | None,
    is_deposit: bool,
    idempotency_key: str | None,
) -> Payment:
    """Customer submits *evidence of payment*. Status becomes
    ``VERIFICATION_PENDING`` — never ``VERIFIED`` (§13)."""
    if request.customer_id != customer_id:
        raise NotFoundError("Request not found.")
    if request.status not in {
        RequestStatus.DEPOSIT_PENDING,
        RequestStatus.DEPOSIT_VERIFICATION,
        RequestStatus.PAYMENT_PENDING,
        RequestStatus.PAYMENT_VERIFICATION,
    }:
        raise ConflictError(
            "Payment is not open for this request.",
            code="PAYMENT_NOT_OPEN",
            details={"status": request.status.value},
        )
    if method == PaymentMethod.CASH and reference_number:
        raise ValidationError("A reference number is not applicable to cash payments.")
    if method != PaymentMethod.CASH and not reference_number:
        raise ValidationError("A transfer reference number is required.")

    if idempotency_key:
        existing = session.execute(
            select(Payment).where(
                Payment.request_id == request.id,
                Payment.idempotency_key == idempotency_key,
            )
        ).scalar_one_or_none()
        if existing is not None:
            return existing

    due = outstanding_amount(session, request_id=request.id)
    quote = accepted_quote(session, request_id=request.id)
    ceiling = Decimal(quote.total) if quote is not None else due
    if is_deposit:
        deposit = deposit_for_request(session, request_id=request.id)
        ceiling = Decimal(deposit.required_amount) if deposit is not None else ceiling
    if _q(amount) > _q(ceiling) + Decimal("0.01"):
        raise ValidationError(
            "The submitted amount exceeds the amount due.",
            details={"submitted": str(_q(amount)), "max": str(_q(ceiling))},
        )

    payment = Payment(
        request_id=request.id,
        customer_id=customer_id,
        amount=_q(amount),
        method=method,
        status=PaymentStatus.VERIFICATION_PENDING,
        reference_number=(reference_number or None),
        is_deposit=is_deposit,
        recorded_by_id=customer_id,
        recorded_at=now_utc(),
        idempotency_key=idempotency_key,
    )
    session.add(payment)
    try:
        session.flush()
    except IntegrityError as exc:
        session.rollback()
        raise ConflictError(
            "This payment submission was already processed.", code="IDEMPOTENCY_CONFLICT"
        ) from exc

    if is_deposit:
        deposit = deposit_for_request(session, request_id=request.id)
        if deposit is not None:
            deposit.paid_amount = _q(Decimal(deposit.paid_amount) + _q(amount))
            deposit.status = DepositStatus.SUBMITTED

    analytics_service.record_event(
        session,
        event_name=AnalyticsEventName.PAYMENT_RECORDED,
        customer_id=customer_id,
        request_id=request.id,
        properties={"amount": str(_q(amount)), "method": method.value},
    )
    notification_service.enqueue(
        session,
        customer_id=customer_id,
        request_id=request.id,
        type_=NotificationType.PAYMENT_REQUIRED,
        title_ar="تم استلام بيانات الدفع",
        body_ar="جارٍ التحقق من الدفع من فريق الحسابات.",
    )
    session.flush()
    return payment


def add_payment_proof(
    session: Session,
    *,
    payment: Payment,
    customer_id: uuid.UUID,
    content: bytes,
    declared_mime: str | None,
    filename: str | None,
) -> PaymentProof:
    from app.services.media_service import (
        build_payment_proof_path,
        make_storage_client,
        validate_image,
    )

    if payment.customer_id != customer_id:
        raise NotFoundError("Payment not found.")
    validated = validate_image(content, declared_mime=declared_mime, filename=filename)
    proof_id = uuid.uuid4()
    path = build_payment_proof_path(
        customer_id=customer_id,
        payment_id=payment.id,
        extension=validated.extension,
        proof_id=proof_id,
    )
    make_storage_client().write(path, validated.content)
    proof = PaymentProof(
        id=proof_id,
        payment_id=payment.id,
        storage_path=path,
        mime_type=validated.mime_type,
        size_bytes=validated.size_bytes,
        checksum_sha256=validated.checksum_sha256,
        uploaded_by_id=customer_id,
    )
    session.add(proof)
    session.flush()
    return proof


# ---------------------------------------------------------------- finance ops


def record_payment_by_staff(
    session: Session,
    *,
    request: ServiceRequest,
    staff_id: uuid.UUID,
    staff_role: str | None,
    amount: Decimal,
    method: PaymentMethod,
    reference_number: str | None,
    is_deposit: bool,
    notes: str | None,
    idempotency_key: str | None,
) -> Payment:
    if idempotency_key:
        existing = session.execute(
            select(Payment).where(
                Payment.request_id == request.id,
                Payment.idempotency_key == idempotency_key,
            )
        ).scalar_one_or_none()
        if existing is not None:
            return existing

    payment = Payment(
        request_id=request.id,
        customer_id=request.customer_id,
        amount=_q(amount),
        method=method,
        status=PaymentStatus.VERIFICATION_PENDING,
        reference_number=reference_number or None,
        is_deposit=is_deposit,
        recorded_by_id=staff_id,
        recorded_at=now_utc(),
        notes=notes,
        idempotency_key=idempotency_key,
    )
    session.add(payment)
    session.flush()
    return payment


def verify_payment(
    session: Session,
    *,
    payment: Payment,
    staff_id: uuid.UUID,
    staff_role: str | None,
    approved: bool,
    rejection_reason: str | None,
) -> Payment:
    """Finance verification. Idempotent: verifying twice is a no-op, not a
    double credit (§139)."""
    if payment.status in {PaymentStatus.VERIFIED, PaymentStatus.REJECTED}:
        raise ConflictError(
            "This payment has already been decided.",
            code="PAYMENT_ALREADY_DECIDED",
            details={"status": payment.status.value},
        )
    if not approved and not rejection_reason:
        raise ValidationError("A reason is required when rejecting a payment.")

    before = {"status": payment.status.value}
    if approved:
        payment.status = PaymentStatus.VERIFIED
        payment.verified_by_id = staff_id
        payment.verified_at = now_utc()
    else:
        payment.status = PaymentStatus.REJECTED
        payment.verified_by_id = staff_id
        payment.verified_at = now_utc()
        payment.rejection_reason = rejection_reason

    request = session.get(ServiceRequest, payment.request_id)
    if request is None:
        raise NotFoundError("Request not found.")

    if payment.is_deposit:
        deposit = deposit_for_request(session, request_id=request.id)
        if deposit is not None:
            if approved:
                deposit.status = DepositStatus.VERIFIED
            elif deposit.status == DepositStatus.SUBMITTED:
                deposit.status = DepositStatus.REJECTED

    if approved:
        due = outstanding_amount(session, request_id=request.id)
        if due <= Decimal("0.00"):
            _advance_to_paid(session, request=request, staff_id=staff_id, staff_role=staff_role)
        elif payment.is_deposit and request.status == RequestStatus.DEPOSIT_VERIFICATION:
            request_service.transition_request(
                session,
                request=request,
                target=RequestStatus.CONFIRMED,
                actor_type="staff",
                actor_id=staff_id,
                actor_role=staff_role,
                event_type="DEPOSIT_VERIFIED",
                note_ar="تم تأكيد العربون",
            )

    record_audit(
        session,
        action=AuditAction.PAYMENT_VERIFICATION,
        entity="payment",
        entity_id=payment.id,
        actor_id=staff_id,
        actor_role=staff_role,
        before=before,
        after={"status": payment.status.value, "amount": str(payment.amount)},
    )
    analytics_service.record_event(
        session,
        event_name=AnalyticsEventName.PAYMENT_VERIFIED,
        customer_id=request.customer_id,
        request_id=request.id,
        properties={"amount": str(payment.amount), "approved": approved},
    )
    notification_service.enqueue(
        session,
        customer_id=request.customer_id,
        request_id=request.id,
        type_=NotificationType.PAYMENT_CONFIRMED if approved else NotificationType.PAYMENT_REQUIRED,
        title_ar="تم تأكيد الدفع" if approved else "لم يتم تأكيد الدفع",
        body_ar=(
            "تم التحقق من الدفع بنجاح."
            if approved
            else "لم يتم تأكيد الدفع. يرجى مراجعة البيانات والمحاولة مرة أخرى."
        ),
    )
    session.flush()
    return payment


def _advance_to_paid(
    session: Session, *, request: ServiceRequest, staff_id: uuid.UUID, staff_role: str | None
) -> None:
    if request.status in {RequestStatus.PAYMENT_PENDING, RequestStatus.PAYMENT_VERIFICATION}:
        request_service.transition_request(
            session,
            request=request,
            target=RequestStatus.PAID,
            actor_type="staff",
            actor_id=staff_id,
            actor_role=staff_role,
            event_type="PAYMENT_VERIFIED",
            note_ar="تم استلام الدفع بالكامل",
        )


def ensure_deposit(
    session: Session, *, request: ServiceRequest, quote: Quote
) -> Deposit | None:
    if not quote.requires_deposit or Decimal(quote.deposit_amount) <= 0:
        return None
    deposit = deposit_for_request(session, request_id=request.id)
    if deposit is not None:
        return deposit
    deposit = Deposit(
        request_id=request.id,
        required_amount=_q(quote.deposit_amount),
        status=DepositStatus.PENDING,
        due_at=now_utc() + timedelta(hours=48),    )
    session.add(deposit)
    session.flush()
    return deposit


def create_refund(
    session: Session,
    *,
    payment: Payment,
    staff_id: uuid.UUID,
    staff_role: str | None,
    amount: Decimal,
    reason: str,
    idempotency_key: str | None,
) -> Refund:
    if payment.status != PaymentStatus.VERIFIED:
        raise ConflictError(
            "Only a verified payment can be refunded.", code="PAYMENT_NOT_REFUNDABLE"
        )
    if idempotency_key:
        existing = session.execute(
            select(Refund).where(Refund.idempotency_key == idempotency_key)
        ).scalar_one_or_none()
        if existing is not None:
            return existing

    already = Decimal("0")
    for refund in payment.refunds:
        if refund.status in {RefundStatus.APPROVED, RefundStatus.PROCESSED}:
            already += Decimal(refund.amount)
    refundable = _q(Decimal(payment.amount) - Decimal(payment.amount_refunded) - already)
    if _q(amount) <= 0 or _q(amount) > refundable:
        raise ValidationError(
            "The refund amount exceeds the refundable balance.",
            details={"refundable": str(refundable)},
        )

    refund = Refund(
        payment_id=payment.id,
        amount=_q(amount),
        reason=reason,
        status=RefundStatus.PENDING,
        requested_by_id=staff_id,
        idempotency_key=idempotency_key,
    )
    session.add(refund)
    session.flush()
    record_audit(
        session,
        action=AuditAction.REFUND,
        entity="refund",
        entity_id=refund.id,
        actor_id=staff_id,
        actor_role=staff_role,
        after={"amount": str(refund.amount), "payment_id": str(payment.id)},
    )
    return refund


def approve_refund(
    session: Session, *, refund: Refund, staff_id: uuid.UUID, staff_role: str | None
) -> Refund:
    if refund.status != RefundStatus.PENDING:
        raise ConflictError("This refund has already been decided.", code="REFUND_DECIDED")
    refund.status = RefundStatus.APPROVED
    refund.approved_by_id = staff_id
    refund.approved_at = now_utc()
    session.flush()
    return refund


def process_refund(
    session: Session, *, refund: Refund, staff_id: uuid.UUID, staff_role: str | None
) -> Refund:
    if refund.status != RefundStatus.APPROVED:
        raise ConflictError(
            "This refund must be approved before processing.", code="REFUND_NOT_APPROVED"
        )
    payment = session.get(Payment, refund.payment_id)
    if payment is None:
        raise NotFoundError("Payment not found.")

    refund.status = RefundStatus.PROCESSED
    refund.processed_by_id = staff_id
    refund.processed_at = now_utc()
    payment.amount_refunded = _q(Decimal(payment.amount_refunded) + Decimal(refund.amount))

    if _q(Decimal(payment.amount_refunded)) >= _q(Decimal(payment.amount)):
        payment.status = PaymentStatus.REFUNDED
    else:
        payment.status = PaymentStatus.PARTIALLY_REFUNDED

    deposit = deposit_for_request(session, request_id=payment.request_id)
    if deposit is not None and payment.is_deposit:
        deposit.refunded_amount = _q(
            min(Decimal(deposit.refunded_amount) + Decimal(refund.amount), Decimal(deposit.paid_amount))
        )
        deposit.status = (
            DepositStatus.REFUNDED
            if deposit.refunded_amount >= deposit.paid_amount
            else DepositStatus.PARTIALLY_REFUNDED
        )

    request = session.get(ServiceRequest, payment.request_id)
    if request is not None:
        request_service.record_event(
            session,
            request_id=request.id,
            event_type="PAYMENT_REFUNDED",
            actor_type="staff",
            actor_id=staff_id,
            actor_role=staff_role,
            payload={"amount": str(refund.amount), "refund_id": str(refund.id)},
        )
    session.flush()
    return refund


# -------------------------------------------------------- cancellation policy


def preview_cancellation(
    session: Session, *, request: ServiceRequest
) -> dict[str, Any]:
    """Server-computed refund preview so the client never invents policy (§12)."""
    deposit = deposit_for_request(session, request_id=request.id)
    required = Decimal(deposit.required_amount) if deposit is not None else Decimal("0.00")
    paid = Decimal(deposit.paid_amount) if deposit is not None else Decimal("0.00")

    booked_at = request.preferred_date or request.submitted_at or request.created_at
    minutes_since = max(
        0,
        int((now_utc() - ensure_aware(booked_at)).total_seconds() // 60),
    )
    policy = pricing_service.resolve_cancellation_policy(
        session, minutes_since_booking=minutes_since
    )
    refund_percent = Decimal(policy.refund_percent) if policy is not None else Decimal("0")
    requires_approval = bool(policy.requires_approval) if policy is not None else False

    refundable = _q(paid * refund_percent / Decimal("100"))
    deduction = _q(paid - refundable)

    return {
        "request_id": request.id,
        "deposit_required": _q(required),
        "deposit_paid": _q(paid),
        "refund_percent": refund_percent,
        "refundable_amount": refundable,
        "deduction_amount": deduction,
        "requires_approval": requires_approval,
        "policy_note_ar": policy.name_ar if policy is not None else None,
    }


def apply_cancellation_refund(
    session: Session,
    *,
    request: ServiceRequest,
    cancellation: Cancellation,
    staff_id: uuid.UUID,
    staff_role: str | None,
) -> None:
    """After a cancellation, verify-then-refund any captured deposit according to
    the policy window (§11, §12)."""
    deposit = deposit_for_request(session, request_id=request.id)
    if deposit is None or Decimal(deposit.paid_amount) <= 0:
        return
    payments = [
        payment
        for payment in payments_for_request(session, request_id=request.id)
        if payment.is_deposit and payment.status == PaymentStatus.VERIFIED
    ]
    if not payments:
        return
    payment = payments[-1]
    booked_at = request.preferred_date or request.submitted_at or request.created_at
    minutes_since = max(0, int((now_utc() - ensure_aware(booked_at)).total_seconds() // 60))
    policy = pricing_service.resolve_cancellation_policy(
        session, minutes_since_booking=minutes_since
    )
    if policy is None:
        return
    amount = _q(Decimal(deposit.paid_amount) * Decimal(policy.refund_percent) / Decimal("100"))
    if amount <= 0:
        return
    refund = create_refund(
        session,
        payment=payment,
        staff_id=staff_id,
        staff_role=staff_role,
        amount=amount,
        reason=f"إلغاء الطلب وفق سياسة الإلغاء: {policy.name_ar}",
        idempotency_key=f"cancel:{cancellation.id}",
    )
    approve_refund(session, refund=refund, staff_id=staff_id, staff_role=staff_role)
    process_refund(session, refund=refund, staff_id=staff_id, staff_role=staff_role)


def payments_pagination_total(session: Session, *, request_id: uuid.UUID) -> int:
    return int(
        session.execute(
            select(func.count(Payment.id)).where(Payment.request_id == request_id)
        ).scalar_one()
        or 0
    )


DEFAULT_METHODS = [PaymentMethod.CASH, PaymentMethod.VODAFONE_CASH, PaymentMethod.INSTAPAY]
