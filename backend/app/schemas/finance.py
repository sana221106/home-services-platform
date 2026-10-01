"""Payment, deposit, refund and invoice contracts (§32, §67, §13)."""

from __future__ import annotations

import uuid
from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field

from app.core.enums import DepositStatus, PaymentMethod, PaymentStatus, RefundStatus


class PaymentSummaryResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    request_id: uuid.UUID
    amount: Decimal
    method: PaymentMethod
    status: PaymentStatus
    reference_number: str | None = None
    is_deposit: bool
    amount_refunded: Decimal
    recorded_at: datetime | None = None
    verified_at: datetime | None = None
    rejection_reason: str | None = None
    proof_url: str | None = None


class DepositResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    request_id: uuid.UUID
    required_amount: Decimal
    paid_amount: Decimal
    refunded_amount: Decimal
    status: DepositStatus
    due_at: datetime | None = None


class PaymentViewResponse(BaseModel):
    """Everything the Payment screen needs, in one round trip."""

    request_id: uuid.UUID
    reference_code: str
    quote_total: Decimal | None = None
    deposit: DepositResponse | None = None
    payments: list[PaymentSummaryResponse] = Field(default_factory=list)
    amount_due: Decimal
    methods: list[str]
    support_phone: str
    instructions_ar: str | None = None


class SubmitPaymentRequest(BaseModel):
    """Customer submits *evidence*. It never asserts a verified state (§13)."""

    model_config = ConfigDict(extra="forbid")

    method: PaymentMethod
    amount: Decimal = Field(gt=0, le=1_000_000)
    reference_number: str | None = Field(default=None, max_length=64)
    is_deposit: bool = False
    idempotency_key: str | None = Field(default=None, max_length=80)


class UploadPaymentProofRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    payment_id: uuid.UUID


class AdminRecordPaymentRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: uuid.UUID
    amount: Decimal = Field(gt=0, le=1_000_000)
    method: PaymentMethod
    reference_number: str | None = Field(default=None, max_length=64)
    is_deposit: bool = False
    notes: str | None = Field(default=None, max_length=1000)
    idempotency_key: str | None = Field(default=None, max_length=80)


class AdminVerifyPaymentRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    approved: bool = True
    rejection_reason: str | None = Field(default=None, max_length=400)
    idempotency_key: str | None = Field(default=None, max_length=80)


class RefundResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    payment_id: uuid.UUID
    amount: Decimal
    reason: str
    status: RefundStatus
    approved_at: datetime | None = None
    processed_at: datetime | None = None


class CreateRefundRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    payment_id: uuid.UUID
    amount: Decimal = Field(gt=0, le=1_000_000)
    reason: str = Field(min_length=3, max_length=400)
    idempotency_key: str | None = Field(default=None, max_length=80)


class InvoiceResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    request_id: uuid.UUID
    number: str
    subtotal: Decimal
    discount: Decimal
    tax: Decimal
    total: Decimal
    issued_at: datetime


class ReceiptResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    number: str
    amount: Decimal
    issued_at: datetime
    receipt_number: str | None = None