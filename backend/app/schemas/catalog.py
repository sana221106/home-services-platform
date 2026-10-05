"""Catalogue, properties and coverage contracts (§29, §31)."""

from __future__ import annotations

import uuid
from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


class ProblemTypeResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    code: str
    name_ar: str
    name_en: str
    description_ar: str | None = None
    sort_order: int
    requires_inspection_default: bool = False
    default_duration_minutes: int
    hint_ar: str | None = None


class ServiceCategoryResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    code: str
    name_ar: str
    name_en: str
    description_ar: str | None = None
    icon_key: str
    color_hex: str
    soft_background_hex: str
    sort_order: int
    estimated_duration_minutes: int
    requires_inspection_default: bool = False


class ServiceCategoryWithProblems(ServiceCategoryResponse):
    problems: list[ProblemTypeResponse] = Field(default_factory=list)


class PaymentMethodOption(BaseModel):
    code: str
    label_ar: str
    instructions_ar: str | None = None
    requires_proof: bool = True


class CoverageZoneResponse(BaseModel):
    """An area the platform currently serves.

    The app picks from this list instead of asking the customer to type a
    governorate and city that have to match the database literally: the address
    form stays free Arabic text while the geography that decides coverage comes
    from the server (§29).
    """

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    code: str
    name_ar: str
    governorate: str
    city: str
    district: str | None = None

    # Nullable because the columns allow it. A served area without a centre
    # cannot be matched to a point, so it is reported honestly as null rather
    # than as 0,0, which would point at the Gulf of Guinea (§30).
    center_latitude: Decimal | None = None
    center_longitude: Decimal | None = None
    radius_km: Decimal | None = None


class GeocodeResult(BaseModel):
    """One address search hit, already matched to a coverage zone.

    `zone_code` is null when the coordinates fall outside every served area, so
    the app can say so before the customer fills in the rest of the form
    instead of failing at submit time.
    """

    display_name: str
    latitude: float
    longitude: float
    street: str | None = None
    district: str | None = None
    city: str | None = None
    governorate: str | None = None
    zone_code: str | None = None
    zone_name_ar: str | None = None


# ------------------------------------------------------------------ properties


class PropertyBase(BaseModel):
    label: str = Field(min_length=1, max_length=120)
    property_type: str = Field(default="apartment", max_length=48)
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
    is_default: bool = False


class CreatePropertyRequest(PropertyBase):
    contact_name: str | None = Field(default=None, max_length=160)
    contact_phone: str | None = Field(default=None, max_length=32)


class UpdatePropertyRequest(BaseModel):
    label: str | None = Field(default=None, min_length=1, max_length=120)
    property_type: str | None = Field(default=None, max_length=48)
    governorate: str | None = Field(default=None, max_length=80)
    city: str | None = Field(default=None, max_length=80)
    zone: str | None = Field(default=None, max_length=120)
    district: str | None = Field(default=None, max_length=120)
    street: str | None = Field(default=None, max_length=255)
    building: str | None = Field(default=None, max_length=80)
    floor: str | None = Field(default=None, max_length=32)
    apartment: str | None = Field(default=None, max_length=32)
    landmark: str | None = Field(default=None, max_length=255)
    notes: str | None = Field(default=None, max_length=2000)
    latitude: Decimal | None = Field(default=None, ge=-90, le=90)
    longitude: Decimal | None = Field(default=None, ge=-180, le=180)
    is_default: bool | None = None
    contact_name: str | None = Field(default=None, max_length=160)
    contact_phone: str | None = Field(default=None, max_length=32)


class PropertyContactResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    contact_name: str
    phone: str
    relation: str | None = None
    is_primary: bool


class PropertyResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    label: str
    property_type: str
    governorate: str
    city: str
    zone: str | None = None
    district: str | None = None
    street: str | None = None
    building: str | None = None
    floor: str | None = None
    apartment: str | None = None
    landmark: str | None = None
    notes: str | None = None
    latitude: Decimal | None = None
    longitude: Decimal | None = None
    is_default: bool
    created_at: datetime
    contacts: list[PropertyContactResponse] = Field(default_factory=list)


class PropertyContactRequest(BaseModel):
    contact_name: str = Field(min_length=1, max_length=160)
    phone: str = Field(min_length=6, max_length=32)
    relation: str | None = Field(default=None, max_length=48)
    is_primary: bool = False


# --------------------------------------------------------------- maintenance


class RecurringIssueResponse(BaseModel):
    category_code: str
    category_name_ar: str
    occurrence_count: int
    first_seen_on: datetime
    last_seen_on: datetime
    related_request_ids: list[uuid.UUID] = Field(default_factory=list)
    severity_note_ar: str | None = None


class MaintenanceHistoryItemResponse(BaseModel):
    request_id: uuid.UUID
    reference_code: str
    category_code: str
    category_name_ar: str
    category_icon_key: str
    category_color_hex: str
    problem_code: str | None = None
    customer_description: str | None = None
    diagnosis: str | None = None
    resolution: str | None = None
    price: Decimal | None = None
    materials_summary: str | None = None
    media: list[str] = Field(default_factory=list)
    served_on: datetime
    had_complaint: bool = False
    had_rework: bool = False
    is_completed: bool = True
    recurrence_index: int = 1
    technician_internal_label: str | None = None


class PropertyHistoryResponse(BaseModel):
    property_id: uuid.UUID
    property_label: str
    total_records: int
    completed_count: int
    total_spent: Decimal
    items: list[MaintenanceHistoryItemResponse]
    recurring_issues: list[RecurringIssueResponse] = Field(default_factory=list)
    last_service_on: datetime | None = None
    next_recommended_service_on: datetime | None = None


class MaintenanceRecordCreate(BaseModel):
    """Internal write path used by the order service on completion."""

    model_config = ConfigDict(extra="forbid")

    property_id: uuid.UUID
    request_id: uuid.UUID
    customer_id: uuid.UUID
    category_code: str
    problem_code: str | None = None
    customer_description: str | None = None
    diagnosis: str | None = None
    resolution: str | None = None
    price: Decimal | None = None
    materials_summary: str | None = None
    technician_id: uuid.UUID | None = None
    media_references: list[str] = Field(default_factory=list)
    inspection_findings: dict | None = None
    had_complaint: bool = False
    had_rework: bool = False
    is_completed: bool = True
    served_on: datetime
    recurrence_group_key: str | None = None
    recurrence_index: int = 1
    related_request_id: uuid.UUID | None = None

    @field_validator("served_on")
    @classmethod
    def _tz_aware(cls, value: datetime) -> datetime:
        if value.tzinfo is None:
            raise ValueError("served_on must be timezone-aware")
        return value

    @model_validator(mode="after")
    def _check_numbers(self) -> MaintenanceRecordCreate:
        if self.recurrence_index < 1:
            raise ValueError("recurrence_index must be >= 1")
        return self