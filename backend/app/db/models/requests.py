"""Service request core: the request, its media, annotations, address snapshot
and the immutable event/status history (§61, §63)."""

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
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.enums import InspectionStatus, MediaKind, RequestStatus, Urgency
from app.db.base import (
    GUID,
    Base,
    JSONType,
    SoftDeleteMixin,
    TimestampMixin,
    UUIDPrimaryKeyMixin,
    enum_column,
)

if TYPE_CHECKING:
    from app.db.models.identity import CustomerProfile
    from app.db.models.properties import Property
    from app.db.models.quotes import Quote
    from app.db.models.workforce import Assignment


class ServiceRequest(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "service_requests"

    reference_code: Mapped[str] = mapped_column(
        String(24), unique=True, nullable=False, index=True
    )
    customer_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("customer_profiles.id", ondelete="CASCADE"), nullable=False, index=True
    )
    property_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("properties.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    category_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("service_categories.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    problem_type_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("problem_types.id", ondelete="RESTRICT"), index=True
    )

    status: Mapped[RequestStatus] = mapped_column(
        enum_column(RequestStatus), default=RequestStatus.DRAFT, nullable=False, index=True
    )
    urgency: Mapped[Urgency] = mapped_column(
        enum_column(Urgency), default=Urgency.NORMAL, nullable=False
    )
    inspection_only: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    inspection_required: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    problem_description: Mapped[str] = mapped_column(Text, nullable=False)
    preferred_date: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    preferred_time_window: Mapped[str | None] = mapped_column(String(48))
    customer_notes: Mapped[str | None] = mapped_column(Text)
    submitted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    cancelled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    closed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    review_started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    inspection_status: Mapped[InspectionStatus | None] = mapped_column(
        enum_column(InspectionStatus), default=None
    )

    has_complaint: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    has_rework: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    rated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    internal_notes_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)

    customer: Mapped[CustomerProfile] = relationship(foreign_keys=[customer_id])  # noqa: F821
    property: Mapped[Property] = relationship(foreign_keys=[property_id])  # noqa: F821
    address_snapshot: Mapped[OrderAddressSnapshot | None] = relationship(
        back_populates="request", uselist=False, cascade="all, delete-orphan"
    )
    media: Mapped[list[RequestMedia]] = relationship(
        back_populates="request", cascade="all, delete-orphan"
    )
    events: Mapped[list[RequestEvent]] = relationship(
        back_populates="request", cascade="all, delete-orphan", order_by="RequestEvent.occurred_at"
    )
    status_history: Mapped[list[RequestStatusHistory]] = relationship(
        back_populates="request", cascade="all, delete-orphan"
    )
    quotes: Mapped[list[Quote]] = relationship(
        back_populates="request", cascade="all, delete-orphan"
    )
    assignments: Mapped[list[Assignment]] = relationship(
        back_populates="request", cascade="all, delete-orphan"
    )
    inspection: Mapped[Inspection | None] = relationship(
        back_populates="request", uselist=False, cascade="all, delete-orphan"
    )

    __table_args__ = (
        Index("ix_service_requests_customer_status", "customer_id", "status"),
        Index("ix_service_requests_status_submitted", "status", "submitted_at"),
        Index("ix_service_requests_property_created", "property_id", "created_at"),
    )


class OrderAddressSnapshot(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Immutable copy of the service address taken at submission time (§61)."""

    __tablename__ = "order_address_snapshots"

    request_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("service_requests.id", ondelete="CASCADE"), unique=True, nullable=False
    )
    governorate: Mapped[str] = mapped_column(String(80), nullable=False)
    city: Mapped[str] = mapped_column(String(80), nullable=False, index=True)
    zone: Mapped[str | None] = mapped_column(String(120), index=True)
    # Canonical served area, resolved from the request's coordinates at submit
    # time. Nullable so an out-of-coverage request can still be stored (§30).
    zone_code: Mapped[str | None] = mapped_column(String(60), index=True)
    district: Mapped[str | None] = mapped_column(String(120), index=True)
    street: Mapped[str | None] = mapped_column(String(255))
    building: Mapped[str | None] = mapped_column(String(80))
    floor: Mapped[str | None] = mapped_column(String(32))
    apartment: Mapped[str | None] = mapped_column(String(32))
    landmark: Mapped[str | None] = mapped_column(String(255))
    notes: Mapped[str | None] = mapped_column(Text)
    latitude: Mapped[Decimal] = mapped_column(Numeric(9, 6), nullable=False)
    longitude: Mapped[Decimal] = mapped_column(Numeric(9, 6), nullable=False)
    contact_name: Mapped[str | None] = mapped_column(String(160))
    contact_phone: Mapped[str | None] = mapped_column(String(32))

    request: Mapped[ServiceRequest] = relationship(back_populates="address_snapshot")


class RequestMedia(UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin, Base):
    """Metadata only — binary lives in private object storage (§79)."""

    __tablename__ = "request_media"

    request_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("service_requests.id", ondelete="CASCADE"), nullable=False, index=True
    )
    kind: Mapped[MediaKind] = mapped_column(
        enum_column(MediaKind), default=MediaKind.IMAGE, nullable=False
    )
    storage_path: Mapped[str] = mapped_column(String(512), nullable=False)
    storage_provider: Mapped[str] = mapped_column(String(32), default="local", nullable=False)
    mime_type: Mapped[str] = mapped_column(String(64), nullable=False)
    size_bytes: Mapped[int] = mapped_column(Integer, nullable=False)
    width: Mapped[int] = mapped_column(Integer, nullable=False)
    height: Mapped[int] = mapped_column(Integer, nullable=False)
    checksum_sha256: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    sort_order: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    uploaded_by_id: Mapped[uuid.UUID | None] = mapped_column(GUID())
    captured_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    request: Mapped[ServiceRequest] = relationship(back_populates="media")
    annotations: Mapped[list[PhotoAnnotation]] = relationship(
        back_populates="media", cascade="all, delete-orphan"
    )

    __table_args__ = (Index("ix_request_media_request_sort", "request_id", "sort_order"),)


class PhotoAnnotation(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Normalized-coordinate annotation geometry (§80)."""

    __tablename__ = "photo_annotations"

    media_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("request_media.id", ondelete="CASCADE"), nullable=False, index=True
    )
    request_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("service_requests.id", ondelete="CASCADE"), nullable=False, index=True
    )
    annotation_type: Mapped[str] = mapped_column(String(24), nullable=False)
    geometry: Mapped[dict] = mapped_column(JSONType, nullable=False)
    note: Mapped[str | None] = mapped_column(String(255))
    created_by_id: Mapped[uuid.UUID | None] = mapped_column(GUID())

    media: Mapped[RequestMedia] = relationship(back_populates="annotations")


class RequestEvent(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Append-only timeline powering customer UI, call centre and audit (§63)."""

    __tablename__ = "request_events"

    request_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("service_requests.id", ondelete="CASCADE"), nullable=False, index=True
    )
    event_type: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    from_status: Mapped[RequestStatus | None] = mapped_column(enum_column(RequestStatus), default=None)
    to_status: Mapped[RequestStatus | None] = mapped_column(enum_column(RequestStatus), default=None)
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    actor_type: Mapped[str] = mapped_column(String(24), default="system", nullable=False)
    actor_id: Mapped[uuid.UUID | None] = mapped_column(GUID())
    actor_role: Mapped[str | None] = mapped_column(String(64))
    correlation_id: Mapped[str | None] = mapped_column(String(64), index=True)
    payload: Mapped[dict | None] = mapped_column(JSONType, default=None)
    note: Mapped[str | None] = mapped_column(String(400))

    request: Mapped[ServiceRequest] = relationship(back_populates="events")

    __table_args__ = (Index("ix_request_events_request_occurred", "request_id", "occurred_at"),)


class RequestStatusHistory(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "request_status_history"

    request_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("service_requests.id", ondelete="CASCADE"), nullable=False, index=True
    )
    from_status: Mapped[RequestStatus | None] = mapped_column(enum_column(RequestStatus), default=None)
    to_status: Mapped[RequestStatus] = mapped_column(
        enum_column(RequestStatus), nullable=False
    )
    changed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    changed_by_id: Mapped[uuid.UUID | None] = mapped_column(GUID())
    changed_by_role: Mapped[str | None] = mapped_column(String(64))
    reason: Mapped[str | None] = mapped_column(String(400))

    request: Mapped[ServiceRequest] = relationship(back_populates="status_history")


class Inspection(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "inspections"

    request_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("service_requests.id", ondelete="CASCADE"), unique=True, nullable=False
    )
    status: Mapped[InspectionStatus] = mapped_column(
        enum_column(InspectionStatus), default=InspectionStatus.PENDING, nullable=False, index=True
    )
    scheduled_start: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    scheduled_end: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    assigned_technician_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("technicians.id", ondelete="SET NULL"), index=True
    )
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    fee: Mapped[Decimal | None] = mapped_column(Numeric(10, 2))

    request: Mapped[ServiceRequest] = relationship(back_populates="inspection")
    report: Mapped[InspectionReport | None] = relationship(
        back_populates="inspection", uselist=False, cascade="all, delete-orphan"
    )


class InspectionReport(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "inspection_reports"

    inspection_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("inspections.id", ondelete="CASCADE"), unique=True, nullable=False
    )
    diagnosis: Mapped[str] = mapped_column(Text, nullable=False)
    problem_description: Mapped[str | None] = mapped_column(Text)
    required_work: Mapped[str | None] = mapped_column(Text)
    required_materials: Mapped[str | None] = mapped_column(Text)
    estimated_duration_minutes: Mapped[int | None] = mapped_column(Integer)
    proposed_price: Mapped[Decimal | None] = mapped_column(Numeric(10, 2))
    internal_notes: Mapped[str | None] = mapped_column(Text)
    media_references: Mapped[list | None] = mapped_column(JSONType, default=None)
    completed_by_id: Mapped[uuid.UUID | None] = mapped_column(GUID())
    qc_reviewed_by_id: Mapped[uuid.UUID | None] = mapped_column(GUID())
    qc_reviewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    qc_passed: Mapped[bool | None] = mapped_column(Boolean)

    inspection: Mapped[Inspection] = relationship(back_populates="report")


__all__ = [
    "Inspection",
    "InspectionReport",
    "OrderAddressSnapshot",
    "PhotoAnnotation",
    "RequestEvent",
    "RequestMedia",
    "RequestStatusHistory",
    "ServiceRequest",
]