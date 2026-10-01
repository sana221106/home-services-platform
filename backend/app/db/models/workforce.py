"""Internal workforce: technicians, skills, zones, availability, assignments
and appointments. None of this is ever exposed to a customer (§9, §65, §66)."""

from __future__ import annotations

import uuid
from datetime import datetime, time

from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    Time,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.enums import AssignmentStatus, TechnicianStatus
from app.db.base import (
    Base,
    GUID,
    TimestampMixin,
    UUIDPrimaryKeyMixin,
    enum_column,
)


class Technician(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "technicians"

    name: Mapped[str] = mapped_column(String(160), nullable=False)
    phone: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
    national_id: Mapped[str | None] = mapped_column(String(32))
    active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False, index=True)
    status: Mapped[TechnicianStatus] = mapped_column(
        enum_column(TechnicianStatus), default=TechnicianStatus.ACTIVE, nullable=False
    )
    base_zone_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("coverage_zones.id", ondelete="SET NULL")
    )
    notes: Mapped[str | None] = mapped_column(Text)
    hire_date: Mapped[datetime | None] = mapped_column(Date)

    # Internal performance metrics (§65).
    total_assignments: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    completed_assignments: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    late_arrivals: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    no_show_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)

    skills: Mapped[list[TechnicianSkill]] = relationship(
        back_populates="technician", cascade="all, delete-orphan"
    )
    zones: Mapped[list[TechnicianZone]] = relationship(
        back_populates="technician", cascade="all, delete-orphan"
    )
    shifts: Mapped[list[TechnicianAvailability]] = relationship(
        back_populates="technician", cascade="all, delete-orphan"
    )

    __table_args__ = (Index("ix_technicians_active_status", "active", "status"),)


class TechnicianSkill(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "technician_skills"

    technician_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("technicians.id", ondelete="CASCADE"), nullable=False, index=True
    )
    category_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("service_categories.id", ondelete="CASCADE"), nullable=False, index=True
    )
    proficiency: Mapped[int] = mapped_column(Integer, default=1, nullable=False)

    technician: Mapped[Technician] = relationship(back_populates="skills")

    __table_args__ = (
        UniqueConstraint("technician_id", "category_id", name="uq_technician_skills_tech_category"),
    )


class TechnicianZone(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "technician_zones"

    technician_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("technicians.id", ondelete="CASCADE"), nullable=False, index=True
    )
    zone_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("coverage_zones.id", ondelete="CASCADE"), nullable=False, index=True
    )

    technician: Mapped[Technician] = relationship(back_populates="zones")
    zone: Mapped["CoverageZone"] = relationship(back_populates="technician_zones")  # noqa: F821

    __table_args__ = (
        UniqueConstraint("technician_id", "zone_id", name="uq_technician_zones_tech_zone"),
    )


class TechnicianAvailability(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Working shift + day-specific unavailability."""

    __tablename__ = "technician_availability"

    technician_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("technicians.id", ondelete="CASCADE"), nullable=False, index=True
    )
    weekday: Mapped[int] = mapped_column(Integer, nullable=False)
    start_time: Mapped[time] = mapped_column(Time, nullable=False)
    end_time: Mapped[time] = mapped_column(Time, nullable=False)
    is_available: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    date: Mapped[datetime | None] = mapped_column(Date)
    max_daily_assignments: Mapped[int] = mapped_column(Integer, default=8, nullable=False)

    technician: Mapped[Technician] = relationship(back_populates="shifts")

    __table_args__ = (
        Index("ix_technician_availability_lookup", "technician_id", "weekday", "date"),
    )


class Assignment(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Assignment history is preserved — rows are never overwritten (§66)."""

    __tablename__ = "assignments"

    request_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("service_requests.id", ondelete="CASCADE"), nullable=False, index=True
    )
    technician_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("technicians.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    assigned_by_id: Mapped[uuid.UUID | None] = mapped_column(GUID(), index=True)
    assigned_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    expected_arrival_start: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    expected_arrival_end: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    actual_arrival: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    work_started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    work_completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    status: Mapped[AssignmentStatus] = mapped_column(
        enum_column(AssignmentStatus), default=AssignmentStatus.ASSIGNED, nullable=False, index=True
    )
    is_current: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False, index=True)
    cancelled_reason: Mapped[str | None] = mapped_column(String(255))
    internal_notes: Mapped[str | None] = mapped_column(Text)

    request: Mapped["ServiceRequest"] = relationship(back_populates="assignments")  # noqa: F821
    technician: Mapped[Technician] = relationship()

    __table_args__ = (
        Index("ix_assignments_request_current", "request_id", "is_current"),
        Index("ix_assignments_technician_status", "technician_id", "status"),
    )


class Appointment(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "appointments"

    request_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("service_requests.id", ondelete="CASCADE"), nullable=False, index=True
    )
    assignment_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("assignments.id", ondelete="SET NULL")
    )
    scheduled_start: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    scheduled_end: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    actual_start: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    actual_end: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    status: Mapped[str] = mapped_column(String(32), default="SCHEDULED", nullable=False)
    notes: Mapped[str | None] = mapped_column(String(400))

    __table_args__ = (Index("ix_appointments_scheduled_start", "scheduled_start"),)