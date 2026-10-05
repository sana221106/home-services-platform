"""Service catalogue, coverage zones, pricing rules, cancellation policies."""

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

from app.db.base import (
    GUID,
    Base,
    JSONType,
    SoftDeleteMixin,
    TimestampMixin,
    UUIDPrimaryKeyMixin,
)

if TYPE_CHECKING:  # pragma: no cover - import cycle broken for type checkers only
    from app.db.models.workforce import TechnicianZone


class ServiceCategory(UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin, Base):
    """Admin-manageable service catalogue — new categories require no app
    release, only a seed row (§2)."""

    __tablename__ = "service_categories"

    code: Mapped[str] = mapped_column(String(48), unique=True, nullable=False, index=True)
    name_ar: Mapped[str] = mapped_column(String(120), nullable=False)
    name_en: Mapped[str] = mapped_column(String(120), nullable=False)
    description_ar: Mapped[str | None] = mapped_column(Text)
    icon_key: Mapped[str] = mapped_column(String(48), nullable=False, default="wrench")
    color_hex: Mapped[str] = mapped_column(String(9), default="#2557D6", nullable=False)
    soft_background_hex: Mapped[str] = mapped_column(String(9), default="#EEF4FF", nullable=False)
    sort_order: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    requires_inspection_default: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    estimated_duration_minutes: Mapped[int] = mapped_column(Integer, default=120, nullable=False)

    problem_types: Mapped[list[ProblemType]] = relationship(
        back_populates="category", cascade="all, delete-orphan", order_by="ProblemType.sort_order"
    )
    pricing_rules: Mapped[list[PricingRule]] = relationship(
        back_populates="category", cascade="all, delete-orphan"
    )


class ProblemType(UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin, Base):
    __tablename__ = "problem_types"

    category_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("service_categories.id", ondelete="CASCADE"), nullable=False, index=True
    )
    code: Mapped[str] = mapped_column(String(64), nullable=False)
    name_ar: Mapped[str] = mapped_column(String(160), nullable=False)
    name_en: Mapped[str] = mapped_column(String(160), nullable=False)
    description_ar: Mapped[str | None] = mapped_column(Text)
    sort_order: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    requires_inspection_default: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    default_duration_minutes: Mapped[int] = mapped_column(Integer, default=90, nullable=False)
    hint_ar: Mapped[str | None] = mapped_column(String(255))

    category: Mapped[ServiceCategory] = relationship(back_populates="problem_types")

    __table_args__ = (UniqueConstraint("category_id", "code", name="uq_problem_types_category_id_code"),)


class CoverageZone(UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin, Base):
    __tablename__ = "coverage_zones"

    code: Mapped[str] = mapped_column(String(48), unique=True, nullable=False)
    name_ar: Mapped[str] = mapped_column(String(120), nullable=False)
    governorate: Mapped[str] = mapped_column(String(80), nullable=False, index=True)
    city: Mapped[str] = mapped_column(String(80), nullable=False, index=True)
    district: Mapped[str | None] = mapped_column(String(120), index=True)
    center_latitude: Mapped[Decimal | None] = mapped_column(Numeric(9, 6))
    center_longitude: Mapped[Decimal | None] = mapped_column(Numeric(9, 6))
    radius_km: Mapped[Decimal | None] = mapped_column(Numeric(6, 2))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    urgent_multiplier: Mapped[Decimal] = mapped_column(Numeric(5, 2), default=Decimal("1.00"))

    technician_zones: Mapped[list[TechnicianZone]] = relationship(  # noqa: F821
        back_populates="zone", cascade="all, delete-orphan"
    )


class PricingRule(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Server-authoritative pricing. Flutter never computes money (§8, §120)."""

    __tablename__ = "pricing_rules"

    category_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("service_categories.id", ondelete="CASCADE"), index=True
    )
    problem_type_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("problem_types.id", ondelete="CASCADE"), index=True
    )
    zone_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("coverage_zones.id", ondelete="CASCADE"), index=True
    )
    base_service_cost: Mapped[Decimal] = mapped_column(Numeric(10, 2), default=Decimal("0"))
    materials_cost: Mapped[Decimal] = mapped_column(Numeric(10, 2), default=Decimal("0"))
    urgency_multiplier: Mapped[Decimal] = mapped_column(Numeric(5, 2), default=Decimal("1.00"))
    urgent_flat_fee: Mapped[Decimal] = mapped_column(Numeric(10, 2), default=Decimal("0"))
    inspection_fee: Mapped[Decimal] = mapped_column(Numeric(10, 2), default=Decimal("0"))
    deposit_percent: Mapped[Decimal] = mapped_column(Numeric(5, 2), default=Decimal("0"))
    estimated_duration_minutes: Mapped[int] = mapped_column(Integer, default=120, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    valid_from: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    valid_to: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    notes: Mapped[str | None] = mapped_column(String(400))

    category: Mapped[ServiceCategory | None] = relationship(back_populates="pricing_rules")

    __table_args__ = (
        Index(
            "ix_pricing_rules_lookup",
            "category_id",
            "problem_type_id",
            "zone_id",
            "is_active",
        ),
    )


class CancellationPolicy(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Time-window deposit refund policy (§12). Not hardcoded in clients."""

    __tablename__ = "cancellation_policies"

    name_ar: Mapped[str] = mapped_column(String(120), nullable=False)
    window_minutes: Mapped[int] = mapped_column(Integer, nullable=False)
    refund_percent: Mapped[Decimal] = mapped_column(Numeric(5, 2), nullable=False)
    requires_approval: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    rules: Mapped[dict | None] = mapped_column(JSONType, default=None)

    __table_args__ = (Index("ix_cancellation_policies_window", "window_minutes"),)


class ServiceAreaSnapshot(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Denormalised geography captured at request time for §18 analytics."""

    __tablename__ = "service_area_snapshots"

    request_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("service_requests.id", ondelete="CASCADE"), unique=True, nullable=False
    )
    latitude: Mapped[Decimal] = mapped_column(Numeric(9, 6), nullable=False)
    longitude: Mapped[Decimal] = mapped_column(Numeric(9, 6), nullable=False)
    governorate: Mapped[str] = mapped_column(String(80), nullable=False, index=True)
    city: Mapped[str] = mapped_column(String(80), nullable=False, index=True)
    zone: Mapped[str | None] = mapped_column(String(120), index=True)
    district: Mapped[str | None] = mapped_column(String(120), index=True)
    zone_id: Mapped[uuid.UUID | None] = mapped_column(GUID(), index=True)
