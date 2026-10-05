"""Admin / operations contracts (§71, §73, §74, §114)."""

from __future__ import annotations

import uuid
from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field

from app.core.enums import (
    AuditAction,
    RequestStatus,
    TechnicianStatus,
    Urgency,
)
from app.schemas.catalog import PropertyResponse
from app.schemas.finance import PaymentSummaryResponse
from app.schemas.orders import AssignmentResponse
from app.schemas.requests import (
    AddressSnapshotPayload,
    QuoteResponse,
    RequestMediaResponse,
)
from app.schemas.support import ComplaintResponse, ReviewResponse


class AdminRequestListItem(BaseModel):
    id: uuid.UUID
    reference_code: str
    status: RequestStatus
    urgency: Urgency
    inspection_only: bool
    inspection_required: bool
    category_name_ar: str
    problem_name_ar: str | None = None
    property_label: str
    customer_name: str
    customer_phone: str
    zone_summary: str | None = None
    created_at: datetime
    submitted_at: datetime | None = None
    sla_age_minutes: int | None = None
    current_quote_total: Decimal | None = None
    assigned_technician_name: str | None = None


class AdminRequestDetail(AdminRequestListItem):
    problem_description: str
    customer_notes: str | None = None
    address: AddressSnapshotPayload | None = None
    media: list[RequestMediaResponse] = Field(default_factory=list)
    quotes: list[QuoteResponse] = Field(default_factory=list)
    current_quote: QuoteResponse | None = None
    assignments: list[AssignmentResponse] = Field(default_factory=list)
    complaint: ComplaintResponse | None = None
    payments: list[PaymentSummaryResponse] = Field(default_factory=list)
    internal_notes: list[str] = Field(default_factory=list)
    ai_suggestion: AiSuggestionSummary | None = None
    funnels: dict[str, str | None] = Field(default_factory=dict)


class AdminStartReviewRequest(BaseModel):
    note: str | None = Field(default=None, max_length=1000)


class AdminRequestInfoRequest(BaseModel):
    message: str = Field(min_length=5, max_length=2000)


class AdminStatusChangeRequest(BaseModel):
    status: RequestStatus
    reason: str | None = Field(default=None, max_length=1000)
    force: bool = Field(default=False)
    idempotency_key: str | None = Field(default=None, max_length=80)


class AdminInspectionScheduleRequest(BaseModel):
    scheduled_start: datetime
    scheduled_end: datetime | None = None
    technician_id: uuid.UUID | None = None
    fee: Decimal | None = Field(default=None, ge=0, le=100000)


class AdminInspectionCompleteRequest(BaseModel):
    diagnosis: str = Field(min_length=5, max_length=4000)
    problem_description: str | None = Field(default=None, max_length=4000)
    required_work: str | None = Field(default=None, max_length=4000)
    required_materials: str | None = Field(default=None, max_length=4000)
    estimated_duration_minutes: int | None = Field(default=None, ge=15, le=1440)
    proposed_price: Decimal | None = Field(default=None, ge=0, le=1_000_000)
    internal_notes: str | None = Field(default=None, max_length=4000)
    qc_passed: bool | None = None


class AdminQcReviewRequest(BaseModel):
    qc_passed: bool
    notes: str | None = Field(default=None, max_length=4000)


class AdminCancelRequest(BaseModel):
    reason: str = Field(min_length=3, max_length=100)
    reason_note: str | None = Field(default=None, max_length=1000)
    apply_discount: Decimal = Field(default=Decimal("0"), ge=0, le=1_000_000)


# ------------------------------------------------------------------ customers


class CustomerListItem(BaseModel):
    id: uuid.UUID
    full_name: str
    phone: str
    created_at: datetime
    properties_count: int
    requests_count: int
    completed_count: int
    total_spent: Decimal
    last_request_at: datetime | None = None
    has_open_complaint: bool = False
    funnel_stage: str


class Customer360Response(BaseModel):
    customer_id: uuid.UUID
    full_name: str
    phone: str
    email: str | None = None
    member_since: datetime
    properties: list[PropertyResponse]
    requests: list[AdminRequestListItem]
    payments: list[PaymentSummaryResponse]
    complaints: list[ComplaintResponse]
    reviews: list[ReviewResponse]
    conversations: list[dict] = Field(default_factory=list)
    call_logs: list[dict] = Field(default_factory=list)
    internal_notes: list[dict] = Field(default_factory=list)
    notifications: list[dict] = Field(default_factory=list)
    timeline: list[dict] = Field(default_factory=list)
    funnel: dict[str, str | None] = Field(default_factory=dict)
    stop_reason: str | None = None
    sla_age_minutes: int | None = None
    escalation_required: bool = False
    next_follow_up_at: datetime | None = None


class CreateFollowUpTaskRequest(BaseModel):
    customer_id: uuid.UUID
    note: str = Field(min_length=3, max_length=2000)
    due_at: datetime


# --------------------------------------------------------------- technicians


class TechnicianSkillPayload(BaseModel):
    category_id: uuid.UUID


class TechnicianZonePayload(BaseModel):
    zone_id: uuid.UUID


class CreateTechnicianRequest(BaseModel):
    name: str = Field(min_length=2, max_length=160)
    phone: str = Field(min_length=6, max_length=32)
    national_id: str | None = Field(default=None, max_length=32)
    base_zone_id: uuid.UUID | None = None
    notes: str | None = Field(default=None, max_length=2000)
    skill_category_ids: list[uuid.UUID] = Field(default_factory=list)
    zone_ids: list[uuid.UUID] = Field(default_factory=list)


class UpdateTechnicianRequest(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=160)
    phone: str | None = Field(default=None, min_length=6, max_length=32)
    status: TechnicianStatus | None = None
    active: bool | None = None
    base_zone_id: uuid.UUID | None = None
    notes: str | None = Field(default=None, max_length=2000)
    skill_category_ids: list[uuid.UUID] | None = None
    zone_ids: list[uuid.UUID] | None = None


class TechnicianListItem(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    phone: str
    active: bool
    status: TechnicianStatus
    base_zone_id: uuid.UUID | None = None
    total_assignments: int
    completed_assignments: int
    late_arrivals: int
    no_show_count: int
    skill_category_ids: list[uuid.UUID] = Field(default_factory=list)
    zone_ids: list[uuid.UUID] = Field(default_factory=list)


# -------------------------------------------------------------- catalogue ops


class UpsertServiceCategoryRequest(BaseModel):
    code: str = Field(min_length=2, max_length=48, pattern=r"^[a-z0-9_]+$")
    name_ar: str = Field(min_length=2, max_length=120)
    name_en: str = Field(min_length=2, max_length=120)
    description_ar: str | None = Field(default=None, max_length=2000)
    icon_key: str = Field(default="wrench", max_length=48)
    color_hex: str = Field(default="#2557D6", pattern=r"^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$")
    soft_background_hex: str = Field(
        default="#EEF4FF", pattern=r"^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$"
    )
    sort_order: int = Field(default=0, ge=0, le=9999)
    is_active: bool = True
    requires_inspection_default: bool = False
    estimated_duration_minutes: int = Field(default=120, ge=15, le=1440)


class UpsertProblemTypeRequest(BaseModel):
    code: str = Field(min_length=2, max_length=64, pattern=r"^[a-z0-9_]+$")
    name_ar: str = Field(min_length=2, max_length=160)
    name_en: str = Field(min_length=2, max_length=160)
    description_ar: str | None = Field(default=None, max_length=2000)
    hint_ar: str | None = Field(default=None, max_length=255)
    sort_order: int = Field(default=0, ge=0, le=9999)
    is_active: bool = True
    requires_inspection_default: bool = False
    default_duration_minutes: int = Field(default=90, ge=15, le=1440)


class UpsertPricingRuleRequest(BaseModel):
    category_id: uuid.UUID
    problem_type_id: uuid.UUID | None = None
    zone_id: uuid.UUID | None = None
    base_service_cost: Decimal = Field(default=Decimal("0"), ge=0, le=1_000_000)
    materials_cost: Decimal = Field(default=Decimal("0"), ge=0, le=1_000_000)
    urgency_multiplier: Decimal = Field(default=Decimal("1.00"), ge=Decimal("1.00"), le=Decimal("5"))
    urgent_flat_fee: Decimal = Field(default=Decimal("0"), ge=0, le=1_000_000)
    inspection_fee: Decimal = Field(default=Decimal("0"), ge=0, le=1_000_000)
    deposit_percent: Decimal = Field(default=Decimal("0"), ge=0, le=Decimal("100"))
    estimated_duration_minutes: int = Field(default=120, ge=15, le=1440)
    valid_from: datetime
    valid_to: datetime | None = None
    notes: str | None = Field(default=None, max_length=400)


class UpsertCoverageZoneRequest(BaseModel):
    code: str = Field(min_length=2, max_length=48, pattern=r"^[a-z0-9_]+$")
    name_ar: str = Field(min_length=2, max_length=120)
    governorate: str = Field(min_length=2, max_length=80)
    city: str = Field(min_length=2, max_length=80)
    district: str | None = Field(default=None, max_length=120)
    center_latitude: Decimal | None = Field(default=None, ge=-90, le=90)
    center_longitude: Decimal | None = Field(default=None, ge=-180, le=180)
    radius_km: Decimal | None = Field(default=None, gt=0, le=500)
    is_active: bool = True
    urgent_multiplier: Decimal = Field(default=Decimal("1.00"), ge=Decimal("1.00"), le=Decimal("5"))


class UpsertCancellationPolicyRequest(BaseModel):
    name_ar: str = Field(min_length=2, max_length=120)
    window_minutes: int = Field(ge=0, le=20160)
    refund_percent: Decimal = Field(ge=0, le=Decimal("100"))
    requires_approval: bool = False
    is_active: bool = True


class PricingPreviewRequest(BaseModel):
    category_id: uuid.UUID
    problem_type_id: uuid.UUID | None = None
    zone_id: uuid.UUID | None = None
    urgency: Urgency = Urgency.NORMAL
    inspection_only: bool = False


class PricingPreviewResponse(BaseModel):
    service_cost: Decimal
    materials_cost: Decimal
    urgency_fee: Decimal
    inspection_fee: Decimal
    deposit_percent: Decimal
    estimated_duration_minutes: int
    matched_rule_id: uuid.UUID | None = None


# ------------------------------------------------------------- AI / analytics


class AiSuggestionSummary(BaseModel):
    id: uuid.UUID
    predicted_category: str | None = None
    predicted_problem: str | None = None
    confidence: Decimal | None = None
    inspection_recommended: bool | None = None
    model_provider: str | None = None
    model_name: str | None = None
    human_approved_category: str | None = None
    human_approved_problem: str | None = None
    was_corrected: bool = False
    created_at: datetime


class AiClassifyRequestRequest(BaseModel):
    request_id: uuid.UUID | None = None
    problem_description: str = Field(min_length=5, max_length=4000)
    category_id: uuid.UUID | None = None
    problem_type_id: uuid.UUID | None = None
    include_history: bool = True


class AiClassifyResponse(BaseModel):
    """Optional assistance only. Never a binding business decision (§82, §84)."""

    request_id: uuid.UUID | None = None
    predicted_category: str
    predicted_problem: str
    confidence: float
    inspection_recommended: bool
    model_provider: str
    model_name: str
    model_version: str | None = None
    available: bool = True
    reason_ar: str | None = None


class AiReviewDecisionRequest(BaseModel):
    approved_category_code: str = Field(min_length=2, max_length=64)
    approved_problem_code: str | None = Field(default=None, max_length=64)


class AuditLogResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    actor_id: uuid.UUID | None = None
    actor_role: str | None = None
    action: AuditAction | str
    entity: str
    entity_id: uuid.UUID | None = None
    before: dict | None = None
    after: dict | None = None
    correlation_id: str | None = None
    created_at: datetime


class FunnelBucket(BaseModel):
    stage: str
    label_ar: str
    count: int
    conversion_from_previous: float | None = None


class OverviewResponse(BaseModel):
    period_start: datetime
    period_end: datetime
    total_requests: int
    completed_orders: int
    completion_rate: float
    open_requests: int
    awaiting_quote: int
    awaiting_payment: int
    open_complaints: int
    average_quote_minutes: float | None = None
    average_arrival_minutes: float | None = None
    total_revenue: Decimal
    active_customers: int
    completed_orders_target: int = 30
    target_progress: float = 0.0


class AreaAnalyticsRow(BaseModel):
    governorate: str
    city: str
    zone: str | None = None
    district: str | None = None
    requests: int
    completed: int
    urgent: int
    inspections_required: int
    complaints: int
    revenue: Decimal
    avg_completion_hours: float | None = None


class CategoryAnalyticsRow(BaseModel):
    category_code: str
    category_name_ar: str
    requests: int
    completed: int
    revenue: Decimal
    avg_rating: float | None = None


class TechnicianUtilisationRow(BaseModel):
    technician_id: uuid.UUID
    technician_name: str
    assignments: int
    completed: int
    late: int
    no_shows: int
    utilisation_percent: float
    avg_completion_minutes: float | None = None


class ReportExportRequest(BaseModel):
    report: str = Field(max_length=64)
    start: datetime
    end: datetime
    format: str = Field(default="csv", pattern=r"^(csv|xlsx)$")


# ----------------------------------------------------------------- staff auth


class StaffLoginRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    email: str = Field(min_length=3, max_length=255)
    password: str = Field(min_length=8, max_length=128)


class TokenPairSchema(BaseModel):
    access_token: str
    refresh_token: str
    expires_in: int


class StaffProfileResponse(BaseModel):
    staff_id: uuid.UUID
    email: str
    full_name: str
    is_active: bool
    roles: list[str] = Field(default_factory=list)
    permissions: list[str] = Field(default_factory=list)


AdminRequestDetail.model_rebuild()