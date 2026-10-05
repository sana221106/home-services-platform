"""Money: payments, proofs, deposits, refunds, cancellations, invoices, receipts.

The client can never assert a verified payment (§13, §120). Everything here is
written by backend services under explicit transaction control (§138).
"""

from __future__ import annotations

import uuid
from datetime import datetime
from decimal import Decimal
from typing import TYPE_CHECKING

from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.enums import (
    CancellationReason,
    DepositStatus,
    PaymentMethod,
    PaymentStatus,
    RefundStatus,
)
from app.db.base import (
    GUID,
    Base,
    TimestampMixin,
    UUIDPrimaryKeyMixin,
    enum_column,
)

if TYPE_CHECKING:  # pragma: no cover - import cycle broken for type checkers only
    from app.db.models.requests import ServiceRequest


class Payment(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "payments"

    request_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("service_requests.id", ondelete="CASCADE"), nullable=False, index=True
    )
    amount: Mapped[Decimal] = mapped_column(Numeric(10, 2), nullable=False)
    method: Mapped[PaymentMethod] = mapped_column(
        enum_column(PaymentMethod), nullable=False
    )
    status: Mapped[PaymentStatus] = mapped_column(
        enum_column(PaymentStatus), default=PaymentStatus.PENDING, nullable=False, index=True
    )
    reference_number: Mapped[str | None] = mapped_column(String(64), index=True)
    is_deposit: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    customer_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("customer_profiles.id", ondelete="CASCADE"), nullable=False, index=True
    )
    recorded_by_id: Mapped[uuid.UUID | None] = mapped_column(GUID(), index=True)
    verified_by_id: Mapped[uuid.UUID | None] = mapped_column(GUID(), index=True)
    recorded_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    rejection_reason: Mapped[str | None] = mapped_column(String(400))
    idempotency_key: Mapped[str | None] = mapped_column(String(80), index=True)
    amount_refunded: Mapped[Decimal] = mapped_column(
        Numeric(10, 2), default=Decimal("0"), nullable=False
    )
    notes: Mapped[str | None] = mapped_column(Text)

    request: Mapped[ServiceRequest] = relationship()  # noqa: F821
    proofs: Mapped[list[PaymentProof]] = relationship(
        back_populates="payment", cascade="all, delete-orphan"
    )
    refunds: Mapped[list[Refund]] = relationship(back_populates="payment")

    __table_args__ = (
        Index("ix_payments_request_status", "request_id", "status"),
        Index("ix_payments_customer_created", "customer_id", "created_at"),
    )


class PaymentProof(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "payment_proofs"

    payment_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("payments.id", ondelete="CASCADE"), nullable=False, index=True
    )
    storage_path: Mapped[str] = mapped_column(String(512), nullable=False)
    mime_type: Mapped[str] = mapped_column(String(64), nullable=False)
    size_bytes: Mapped[int] = mapped_column(Integer, nullable=False)
    checksum_sha256: Mapped[str] = mapped_column(String(64), nullable=False)
    uploaded_by_id: Mapped[uuid.UUID | None] = mapped_column(GUID())

    payment: Mapped[Payment] = relationship(back_populates="proofs")


class Deposit(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "deposits"

    request_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("service_requests.id", ondelete="CASCADE"), nullable=False, index=True
    )
    payment_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("payments.id", ondelete="SET NULL"), index=True
    )
    required_amount: Mapped[Decimal] = mapped_column(Numeric(10, 2), nullable=False)
    paid_amount: Mapped[Decimal] = mapped_column(Numeric(10, 2), default=Decimal("0"))
    refunded_amount: Mapped[Decimal] = mapped_column(Numeric(10, 2), default=Decimal("0"))
    status: Mapped[DepositStatus] = mapped_column(
        enum_column(DepositStatus), default=DepositStatus.PENDING, nullable=False, index=True
    )
    policy_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("cancellation_policies.id", ondelete="SET NULL"), index=True
    )
    due_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    __table_args__ = (UniqueConstraint("request_id", name="uq_deposits_request_id"),)


class Refund(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "refunds"

    payment_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("payments.id", ondelete="CASCADE"), nullable=False, index=True
    )
    amount: Mapped[Decimal] = mapped_column(Numeric(10, 2), nullable=False)
    reason: Mapped[str] = mapped_column(String(400), nullable=False)
    status: Mapped[RefundStatus] = mapped_column(
        enum_column(RefundStatus), default=RefundStatus.PENDING, nullable=False, index=True
    )
    policy_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("cancellation_policies.id", ondelete="SET NULL"), index=True
    )
    requested_by_id: Mapped[uuid.UUID | None] = mapped_column(GUID())
    approved_by_id: Mapped[uuid.UUID | None] = mapped_column(GUID())
    processed_by_id: Mapped[uuid.UUID | None] = mapped_column(GUID())
    approved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    processed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    idempotency_key: Mapped[str | None] = mapped_column(String(80), index=True)

    payment: Mapped[Payment] = relationship(back_populates="refunds")


class Cancellation(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "cancellations"

    request_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("service_requests.id", ondelete="CASCADE"), nullable=False, index=True
    )
    reason: Mapped[CancellationReason] = mapped_column(
        enum_column(CancellationReason), nullable=False
    )
    reason_note: Mapped[str | None] = mapped_column(String(400))
    cancelled_by_id: Mapped[uuid.UUID | None] = mapped_column(GUID())
    cancelled_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    refund_percent_applied: Mapped[Decimal] = mapped_column(Numeric(5, 2), default=Decimal("0"))
    approved_by_id: Mapped[uuid.UUID | None] = mapped_column(GUID())
    discount_applied: Mapped[Decimal] = mapped_column(
        Numeric(10, 2), default=Decimal("0"), nullable=False
    )

    __table_args__ = (UniqueConstraint("request_id", name="uq_cancellations_request_id"),)


class Invoice(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "invoices"

    request_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("service_requests.id", ondelete="CASCADE"), nullable=False, index=True
    )
    number: Mapped[str] = mapped_column(String(40), unique=True, nullable=False)
    subtotal: Mapped[Decimal] = mapped_column(Numeric(10, 2), default=Decimal("0"))
    discount: Mapped[Decimal] = mapped_column(Numeric(10, 2), default=Decimal("0"))
    tax: Mapped[Decimal] = mapped_column(Numeric(10, 2), default=Decimal("0"))
    total: Mapped[Decimal] = mapped_column(Numeric(10, 2), default=Decimal("0"))
    issued_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    quote_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("quotes.id", ondelete="SET NULL"), index=True
    )


class Receipt(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "receipts"

    number: Mapped[str] = mapped_column(String(40), unique=True, nullable=False)
    invoice_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("invoices.id", ondelete="SET NULL"), index=True
    )
    payment_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("payments.id", ondelete="SET NULL"), index=True
    )
    amount: Mapped[Decimal] = mapped_column(Numeric(10, 2), nullable=False)
    issued_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    issued_to_customer_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("customer_profiles.id", ondelete="SET NULL"), index=True
    )
    receipt_number: Mapped[str | None] = mapped_column(String(80))