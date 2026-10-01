"""Service request, media, annotation and quote contracts (§28, §64, §80)."""

from __future__ import annotations

import uuid
from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from app.core.enums import (
    AnnotationType,
    InspectionStatus,
    QuoteStatus,
    RequestStatus,
    Urgency,
)


class AddressSnapshotPayload(BaseModel):
    """Copied onto the request verbatim so history survives property edits (§61)."""

    model_config = ConfigDict(extra="forbid")

    governorate: str = Field(min_length=1, max_length=80)
    city: str = Field(min_length=1, max_length=80)
    zone: str | None = Field(default=None, max_length=120)
    district: str | None = Field(default=None, max_length=120)
    street: str | None = Field(default=None, max_length=255)
    building: str | None = Field(default=None, max_length=80)
    floor: str | None = Field(default=None, max_length=32)
    apartment: str | None = Field(default=None, max_length=32)
    landmark: str | None = Field(default=None, max_length=255)
    notes: str | None = Field(default=None, max_length=2000)
    latitude: Decimal = Field(ge=-90, le=90)
    longitude: Decimal = Field(ge=-180, le=180)
    contact_name: str | None = Field(default=None, max_length=160)
    contact_phone: str | None = Field(default=None, max_length=32)

    @model_validator(mode="after")
    def _require_contact_phone_if_named(self) -> "AddressSnapshotPayload":
        if self.contact_name and not self.contact_phone:
            raise ValueError("contact_phone is required when contact_name is provided")
        return self


class CreateServiceRequestRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    property_id: uuid.UUID
    category_id: uuid.UUID
    problem_type_id: uuid.UUID | None = None
    urgency: Urgency = Urgency.NORMAL
    inspection_only: bool = False
    problem_description: str = Field(min_length=10, max_length=4000)
    preferred_date: datetime | None = None
    preferred_time_window: str | None = Field(default=None, max_length=48)
    customer_notes: str | None = Field(default=None, max_length=2000)
    address: AddressSnapshotPayload
    expected_duration_minutes: int | None = Field(default=None, ge=15, le=1440)
    idempotency_key: str | None = Field(default=None, max_length=80)

    @field_validator("preferred_date")
    @classmethod
    def _future_or_today(cls, value: datetime | None) -> datetime | None:
        if value is None:
            return None
        if value.tzinfo is None:
            raise ValueError("preferred_date must be timezone-aware")
        return value


class SubmitServiceRequestRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    idempotency_key: str | None = Field(default=None, max_length=80)


class AnnotationPayload(BaseModel):
    """Normalized geometry, 0..1 relative to the stored image (§80)."""

    model_config = ConfigDict(extra="forbid")

    annotation_type: AnnotationType
    geometry: dict
    note: str | None = Field(default=None, max_length=255)

    @model_validator(mode="after")
    def _validate_normalised(self) -> "AnnotationPayload":
        geometry = self.geometry
        for axis in ("x", "y"):
            if axis in geometry:
                value = geometry[axis]
                if not isinstance(value, (int, float)) or not 0.0 <= float(value) <= 1.0:
                    raise ValueError(f"geometry.{axis} must be a number within [0, 1]")
        return self


class CreateAnnotationRequest(AnnotationPayload):
    pass


class AnnotationResponse(AnnotationPayload):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    media_id: uuid.UUID
    request_id: uuid.UUID
    created_at: datetime


class RequestMediaResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    kind: str
    mime_type: str
    size_bytes: int
    width: int
    height: int
    sort_order: int
    url: str | None = None
    annotations: list[AnnotationResponse] = Field(default_factory=list)
    created_at: datetime


class UploadedMediaBatch(BaseModel):
    media: list[RequestMediaResponse]


class ExpectedArrival(BaseModel):
    start: datetime
    end: datetime


class TechnicianSummary(BaseModel):
    """First name + role only. No phone, no photo, no direct contact (§9, §65)."""

    display_name: str
    company_label_ar: str = "فريق الخدمة"


class RequestEventResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    event_type: str
    from_status: RequestStatus | None = None
    to_status: RequestStatus | None = None
    occurred_at: datetime
    actor_type: str
    note: str | None = None


class InspectionSummary(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    status: InspectionStatus
    scheduled_start: datetime | None = None
    scheduled_end: datetime | None = None
    completed_at: datetime | None = None


class ServiceRequestResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    reference_code: str
    customer_id: uuid.UUID
    property_id: uuid.UUID
    category_id: uuid.UUID
    category_name_ar: str
    category_icon_key: str
    problem_type_id: uuid.UUID | None = None
    problem_name_ar: str | None = None
    status: RequestStatus
    urgency: Urgency
    inspection_only: bool
    inspection_required: bool
    problem_description: str
    preferred_date: datetime | None = None
    preferred_time_window: str | None = None
    customer_notes: str | None = None
    created_at: datetime
    submitted_at: datetime | None = None
    completed_at: datetime | None = None
    has_complaint: bool = False
    has_rework: bool = False
    rated_at: datetime | None = None
    media_count: int = 0
    expected_arrival: ExpectedArrival | None = None
    technician: TechnicianSummary | None = None
    address_summary_ar: str | None = None


class ServiceRequestDetailResponse(ServiceRequestResponse):
    media: list[RequestMediaResponse] = Field(default_factory=list)
    address: AddressSnapshotPayload | None = None
    inspection: InspectionSummary | None = None
    has_unread_updates: bool = False


class TimelineResponse(BaseModel):
    request_id: uuid.UUID
    status: RequestStatus
    events: list[RequestEventResponse]


class CancelRequestRequest(BaseModel):
    reason_note: str | None = Field(default=None, max_length=1000)


class CancellationPreviewResponse(BaseModel):
    """Server-computed so the client never invents refund policy (§12)."""

    request_id: uuid.UUID
    deposit_required: Decimal
    deposit_paid: Decimal
    refund_percent: Decimal
    refundable_amount: Decimal
    deduction_amount: Decimal
    requires_approval: bool
    policy_note_ar: str | None = None


# --------------------------------------------------------------------- quotes


class QuoteItemResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    position: int
    label_ar: str
    quantity: Decimal
    unit_price: Decimal
    line_total: Decimal
    item_type: str


class QuoteResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    request_id: uuid.UUID
    revision_number: int
    status: QuoteStatus
    urgency: Urgency
    service_cost: Decimal
    materials_cost: Decimal
    urgency_fee: Decimal
    inspection_fee: Decimal
    discount: Decimal
    subtotal: Decimal
    total: Decimal
    deposit_amount: Decimal
    requires_deposit: bool
    estimated_duration_minutes: int
    notes: str | None = None
    created_at: datetime
    sent_at: datetime | None = None
    viewed_at: datetime | None = None
    decided_at: datetime | None = None
    expires_at: datetime | None = None
    items: list[QuoteItemResponse] = Field(default_factory=list)


class AcceptQuoteRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    idempotency_key: str | None = Field(default=None, max_length=80)
    accepted_revision: int


class RejectQuoteRequest(BaseModel):
    reason: str | None = Field(default=None, max_length=1000)


class AdminQuoteItemRequest(BaseModel):
    label_ar: str = Field(min_length=1, max_length=200)
    quantity: Decimal = Field(default=Decimal("1"), gt=0, le=999)
    unit_price: Decimal = Field(default=Decimal("0"), ge=0, le=1_000_000)
    item_type: str = Field(default="SERVICE", max_length=32)


class CreateQuoteRequest(BaseModel):
    """Server recomputes every total; only the components are accepted (§64)."""

    model_config = ConfigDict(extra="forbid")

    service_cost: Decimal = Field(default=Decimal("0"), ge=0, le=1_000_000)
    materials_cost: Decimal = Field(default=Decimal("0"), ge=0, le=1_000_000)
    urgency_fee: Decimal = Field(default=Decimal("0"), ge=0, le=1_000_000)
    inspection_fee: Decimal = Field(default=Decimal("0"), ge=0, le=1_000_000)
    discount: Decimal = Field(default=Decimal("0"), ge=0, le=1_000_000)
    estimated_duration_minutes: int = Field(default=120, ge=15, le=1440)
    notes: str | None = Field(default=None, max_length=2000)
    internal_notes: str | None = Field(default=None, max_length=2000)
    expires_in_hours: int = Field(default=72, ge=1, le=720)
    send_immediately: bool = True
    items: list[AdminQuoteItemRequest] = Field(default_factory=list)
    idempotency_key: str | None = Field(default=None, max_length=80)