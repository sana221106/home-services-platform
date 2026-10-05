"""Customer 360, technician management and catalogue administration (§74, §78)."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select

from app.api.dependencies import AuthenticatedStaff, DbSession, require
from app.core.enums import Permission
from app.db.models.catalog import (
    CancellationPolicy,
    CoverageZone,
    PricingRule,
    ProblemType,
    ServiceCategory,
)
from app.db.models.identity import CustomerProfile, User
from app.db.models.requests import ServiceRequest
from app.db.models.workforce import (
    Technician,
    TechnicianSkill,
    TechnicianZone,
)
from app.schemas.admin import (
    CreateTechnicianRequest,
    PricingPreviewRequest,
    PricingPreviewResponse,
    TechnicianListItem,
    UpdateTechnicianRequest,
    UpsertCancellationPolicyRequest,
    UpsertCoverageZoneRequest,
    UpsertPricingRuleRequest,
    UpsertProblemTypeRequest,
    UpsertServiceCategoryRequest,
)
from app.schemas.catalog import (
    ProblemTypeResponse,
    ServiceCategoryResponse,
)
from app.schemas.common import MessageResponse
from app.schemas.support import ReviewResponse
from app.services import audit_service, dashboard_service, pricing_service

router = APIRouter(prefix="/staff", tags=["staff-directory"])

CustomerReadGuard = Annotated[AuthenticatedStaff, Depends(require(Permission.CUSTOMER_READ))]
CustomerPiiGuard = Annotated[AuthenticatedStaff, Depends(require(Permission.CUSTOMER_READ_PII))]
TechnicianReadGuard = Annotated[AuthenticatedStaff, Depends(require(Permission.TECHNICIAN_READ))]
TechnicianWriteGuard = Annotated[AuthenticatedStaff, Depends(require(Permission.TECHNICIAN_WRITE))]
CatalogGuard = Annotated[AuthenticatedStaff, Depends(require(Permission.CATALOG_WRITE))]
PricingGuard = Annotated[AuthenticatedStaff, Depends(require(Permission.PRICING_WRITE))]


# ------------------------------------------------------------------ customers


@router.get(
    "/customers",
    response_model=list[dict],
    summary="Customer directory with funnel stage",
)
def list_customers(
    db: DbSession,
    _staff: CustomerReadGuard,
    search: str | None = Query(default=None, max_length=64),
    limit: int = Query(default=50, ge=1, le=200),
) -> list[dict]:
    stmt = select(CustomerProfile, User.phone).join(User, User.id == CustomerProfile.user_id)
    if search:
        stmt = stmt.where(
            (CustomerProfile.full_name.ilike(f"%{search}%"))
            | (User.phone.ilike(f"%{search}%"))
        )
    rows = list(db.execute(stmt.order_by(CustomerProfile.created_at.desc()).limit(limit)).all())
    result: list[dict] = []
    for profile, phone in rows:
        requests_count = int(
            db.execute(
                select(func.count(ServiceRequest.id)).where(
                    ServiceRequest.customer_id == profile.id
                )
            ).scalar_one()
        )
        result.append(
            {
                "id": profile.id,
                "full_name": profile.full_name,
                "phone": phone,
                "created_at": profile.created_at,
                "requests_count": requests_count,
                "segment": dashboard_service._segment(
                    db, customer_id=profile.id
                ),
            }
        )
    return result


@router.get(
    "/customers/{customer_id}/360",
    response_model=dict,
    summary="Customer 360 for call-centre staff",
)
def customer_360(
    customer_id: uuid.UUID, db: DbSession, staff: CustomerPiiGuard
) -> dict:
    return dashboard_service.customer_360(
        db, customer_id=customer_id, staff_id=staff.staff.id
    )


# ----------------------------------------------------------------- technicians


@router.get(
    "/technicians",
    response_model=list[TechnicianListItem],
    summary="Technician roster",
)
def list_technicians(
    db: DbSession, _staff: TechnicianReadGuard
) -> list[TechnicianListItem]:
    rows = list(db.execute(select(Technician).order_by(Technician.name)).scalars())
    result: list[TechnicianListItem] = []
    for technician in rows:
        skills = list(
            db.execute(
                select(TechnicianSkill).where(
                    TechnicianSkill.technician_id == technician.id
                )
            ).scalars()
        )
        zones = list(
            db.execute(
                select(TechnicianZone).where(
                    TechnicianZone.technician_id == technician.id
                )
            ).scalars()
        )
        result.append(
            TechnicianListItem(
                id=technician.id,
                name=technician.name,
                phone=technician.phone,
                active=technician.active,
                status=technician.status,
                base_zone_id=technician.base_zone_id,
                total_assignments=technician.total_assignments,
                completed_assignments=technician.completed_assignments,
                late_arrivals=technician.late_arrivals,
                no_show_count=technician.no_show_count,
                skill_category_ids=[skill.category_id for skill in skills],
                zone_ids=[zone.zone_id for zone in zones],
            )
        )
    return result


@router.post(
    "/technicians",
    response_model=TechnicianListItem,
    status_code=201,
    summary="Create a technician",
)
def create_technician(
    payload: CreateTechnicianRequest,
    db: DbSession,
    staff: TechnicianWriteGuard,
) -> TechnicianListItem:
    technician = Technician(
        name=payload.name,
        phone=payload.phone,
        national_id=payload.national_id,
        base_zone_id=payload.base_zone_id,
        notes=payload.notes,
    )
    db.add(technician)
    db.flush()
    for category_id in payload.skill_category_ids:
        db.add(TechnicianSkill(technician_id=technician.id, category_id=category_id))
    for zone_id in payload.zone_ids:
        db.add(TechnicianZone(technician_id=technician.id, zone_id=zone_id))
    audit_service.record_audit(
        db,
        actor_id=staff.staff.id,
        actor_role=staff.roles[0] if staff.roles else None,
        action="TECHNICIAN_CREATED",
        entity="technician",
        entity_id=technician.id,
        after={"name": technician.name},
    )
    db.commit()
    return _technician_item(db, technician)


@router.patch(
    "/technicians/{technician_id}",
    response_model=TechnicianListItem,
    summary="Update a technician",
)
def update_technician(
    technician_id: uuid.UUID,
    payload: UpdateTechnicianRequest,
    db: DbSession,
    staff: TechnicianWriteGuard,
) -> TechnicianListItem:
    from app.core.exceptions import NotFoundError

    technician = db.get(Technician, technician_id)
    if technician is None:
        raise NotFoundError("Technician not found.")
    data = payload.model_dump(exclude_unset=True)
    skill_ids = data.pop("skill_category_ids", None)
    zone_ids = data.pop("zone_ids", None)
    for key, value in data.items():
        setattr(technician, key, value)
    if skill_ids is not None:
        for row in list(
            db.execute(
                select(TechnicianSkill).where(
                    TechnicianSkill.technician_id == technician.id
                )
            ).scalars()
        ):
            db.delete(row)
        for category_id in skill_ids:
            db.add(TechnicianSkill(technician_id=technician.id, category_id=category_id))
    if zone_ids is not None:
        for zone_row in list(
            db.execute(
                select(TechnicianZone).where(
                    TechnicianZone.technician_id == technician.id
                )
            ).scalars()
        ):
            db.delete(zone_row)
        for zone_id in zone_ids:
            db.add(TechnicianZone(technician_id=technician.id, zone_id=zone_id))
    db.commit()
    return _technician_item(db, technician)


def _technician_item(db: DbSession, technician: Technician) -> TechnicianListItem:
    skills = list(
        db.execute(
            select(TechnicianSkill).where(TechnicianSkill.technician_id == technician.id)
        ).scalars()
    )
    zones = list(
        db.execute(
            select(TechnicianZone).where(TechnicianZone.technician_id == technician.id)
        ).scalars()
    )
    return TechnicianListItem(
        id=technician.id,
        name=technician.name,
        phone=technician.phone,
        active=technician.active,
        status=technician.status,
        base_zone_id=technician.base_zone_id,
        total_assignments=technician.total_assignments,
        completed_assignments=technician.completed_assignments,
        late_arrivals=technician.late_arrivals,
        no_show_count=technician.no_show_count,
        skill_category_ids=[skill.category_id for skill in skills],
        zone_ids=[zone.zone_id for zone in zones],
    )


# ------------------------------------------------------------------ catalogue


@router.post(
    "/categories",
    response_model=ServiceCategoryResponse,
    status_code=201,
    summary="Create or update a service category",
)
def upsert_category(
    payload: UpsertServiceCategoryRequest, db: DbSession, _staff: CatalogGuard
) -> ServiceCategoryResponse:
    row = db.execute(
        select(ServiceCategory).where(ServiceCategory.code == payload.code)
    ).scalar_one_or_none()
    if row is None:
        row = ServiceCategory(code=payload.code)
        db.add(row)
    for key, value in payload.model_dump().items():
        setattr(row, key, value)
    db.commit()
    return ServiceCategoryResponse.model_validate(row)


@router.post(
    "/categories/{category_id}/problems",
    response_model=ProblemTypeResponse,
    status_code=201,
    summary="Create or update a problem type",
)
def upsert_problem(
    category_id: uuid.UUID,
    payload: UpsertProblemTypeRequest,
    db: DbSession,
    _staff: CatalogGuard,
) -> ProblemTypeResponse:
    row = db.execute(
        select(ProblemType).where(
            ProblemType.category_id == category_id, ProblemType.code == payload.code
        )
    ).scalar_one_or_none()
    if row is None:
        row = ProblemType(category_id=category_id, code=payload.code)
        db.add(row)
    for key, value in payload.model_dump().items():
        setattr(row, key, value)
    db.commit()
    return ProblemTypeResponse.model_validate(row)


@router.post(
    "/pricing-rules",
    response_model=dict,
    status_code=201,
    summary="Create a pricing rule (time-bounded, never client-edited)",
)
def upsert_pricing_rule(
    payload: UpsertPricingRuleRequest, db: DbSession, _staff: PricingGuard
) -> dict:
    rule = PricingRule(
        category_id=payload.category_id,
        problem_type_id=payload.problem_type_id,
        zone_id=payload.zone_id,
        base_service_cost=payload.base_service_cost,
        materials_cost=payload.materials_cost,
        urgency_multiplier=payload.urgency_multiplier,
        urgent_flat_fee=payload.urgent_flat_fee,
        inspection_fee=payload.inspection_fee,
        deposit_percent=payload.deposit_percent,
        estimated_duration_minutes=payload.estimated_duration_minutes,
        valid_from=payload.valid_from,
        valid_to=payload.valid_to,
        notes=payload.notes,
    )
    db.add(rule)
    db.commit()
    return {"id": str(rule.id), "valid_from": rule.valid_from}


@router.post(
    "/pricing/preview",
    response_model=PricingPreviewResponse,
    summary="Preview a server-computed estimate",
)
def pricing_preview(
    payload: PricingPreviewRequest, db: DbSession, _staff: PricingGuard
) -> PricingPreviewResponse:
    from decimal import Decimal

    from app.utils.time import now_utc

    rule = pricing_service.resolve_pricing_rule(
        db,
        category_id=payload.category_id,
        problem_type_id=payload.problem_type_id,
        zone_id=payload.zone_id,
        at=now_utc(),
    )
    estimate = pricing_service.calculate_estimate(
        db,
        category_id=payload.category_id,
        problem_type_id=payload.problem_type_id,
        zone_id=payload.zone_id,
        urgency_multiplier=pricing_service.urgency_multiplier_for(payload.urgency),
        urgent_flat_fee=pricing_service.urgency_flat_fee_for(payload.urgency),
        inspection_only=payload.inspection_only,
        at=now_utc(),
    )
    return PricingPreviewResponse(
        service_cost=Decimal(str(estimate["service_cost"])),
        materials_cost=Decimal(str(estimate["materials_cost"])),
        urgency_fee=Decimal(str(estimate["urgency_fee"])),
        inspection_fee=Decimal(str(estimate["inspection_fee"])),
        deposit_percent=rule.deposit_percent if rule else Decimal("0"),
        estimated_duration_minutes=int(Decimal(str(estimate["estimated_duration_minutes"]))),
        matched_rule_id=rule.id if rule else None,
    )


@router.post(
    "/coverage-zones",
    response_model=dict,
    status_code=201,
    summary="Add a coverage zone",
)
def upsert_zone(
    payload: UpsertCoverageZoneRequest, db: DbSession, _staff: CatalogGuard
) -> dict:
    zone = CoverageZone(
        code=payload.code,
        name_ar=payload.name_ar,
        governorate=payload.governorate,
        city=payload.city,
        district=payload.district,
        center_latitude=payload.center_latitude,
        center_longitude=payload.center_longitude,
        radius_km=payload.radius_km,
        is_active=payload.is_active,
        urgent_multiplier=payload.urgent_multiplier,
    )
    db.add(zone)
    db.commit()
    return {"id": str(zone.id), "code": zone.code}


@router.post(
    "/cancellation-policies",
    response_model=dict,
    status_code=201,
    summary="Add a cancellation policy",
)
def upsert_cancellation_policy(
    payload: UpsertCancellationPolicyRequest, db: DbSession, _staff: CatalogGuard
) -> dict:
    policy = CancellationPolicy(
        name_ar=payload.name_ar,
        window_minutes=payload.window_minutes,
        refund_percent=payload.refund_percent,
        requires_approval=payload.requires_approval,
        is_active=payload.is_active,
    )
    db.add(policy)
    db.commit()
    return {"id": str(policy.id), "refund_percent": str(policy.refund_percent)}


@router.get(
    "/reviews", response_model=list[ReviewResponse], summary="Reviews for moderation"
)
def pending_reviews(db: DbSession, _staff: CustomerReadGuard) -> list[ReviewResponse]:
    from app.db.models.support import Review

    rows = list(db.execute(select(Review).limit(50)).scalars())
    return [ReviewResponse.model_validate(row) for row in rows]


_ = MessageResponse
