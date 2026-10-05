"""Order tracking / dispatch contracts (§30, §66)."""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.core.enums import AssignmentStatus, RequestStatus
from app.schemas.requests import (
    ExpectedArrival,
    RequestEventResponse,
    TechnicianSummary,
)


class OrderStatusChip(BaseModel):
    status: RequestStatus
    label_ar: str
    is_terminal: bool
    is_actionable_by_customer: bool


class OrderTrackingResponse(BaseModel):
    """V1 deliberately exposes an expected arrival *range*, never live GPS (§10)."""

    request_id: uuid.UUID
    reference_code: str
    status: RequestStatus
    status_label_ar: str
    status_description_ar: str
    urgency: str
    expected_arrival: ExpectedArrival | None = None
    actual_arrival: datetime | None = None
    work_started_at: datetime | None = None
    work_completed_at: datetime | None = None
    service_completed_at: datetime | None = None
    technician: TechnicianSummary | None = None
    address_summary_ar: str | None = None
    events: list[RequestEventResponse] = Field(default_factory=list)
    can_cancel: bool
    can_open_complaint: bool
    can_rate: bool


class OrderListItem(BaseModel):
    request_id: uuid.UUID
    reference_code: str
    status: RequestStatus
    status_label_ar: str
    category_name_ar: str
    category_icon_key: str
    urgency: str
    property_label: str
    created_at: datetime
    submitted_at: datetime | None = None
    completed_at: datetime | None = None
    total: str | None = None
    has_complaint: bool = False
    has_unread_updates: bool = False


class AssignmentResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    request_id: uuid.UUID
    technician_id: uuid.UUID
    technician_name: str
    assigned_at: datetime
    expected_arrival_start: datetime | None = None
    expected_arrival_end: datetime | None = None
    actual_arrival: datetime | None = None
    work_started_at: datetime | None = None
    work_completed_at: datetime | None = None
    status: AssignmentStatus
    cancelled_reason: str | None = None


class AssignTechnicianRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    technician_id: uuid.UUID
    expected_arrival_start: datetime
    expected_arrival_end: datetime | None = None
    notes: str | None = Field(default=None, max_length=1000)

    @field_validator("expected_arrival_start")
    @classmethod
    def _tz_aware(cls, value: datetime) -> datetime:
        if value.tzinfo is None:
            raise ValueError("expected_arrival_start must be timezone-aware")
        return value


class TechnicianCandidate(BaseModel):
    id: uuid.UUID
    name: str
    active: bool
    status: str
    matched_skills: list[str]
    matched_zones: list[str]
    current_workload: int
    next_free_at: datetime | None = None
    is_available: bool
    score: int


class DispatchCandidatesResponse(BaseModel):
    request_id: uuid.UUID
    required_skill_category_id: uuid.UUID
    required_zone_id: uuid.UUID | None = None
    candidates: list[TechnicianCandidate]