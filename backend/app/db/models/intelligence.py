"""Audit, analytics events, AI classifications and the property maintenance
health record (§17, §18, §63, §69, §78, §113)."""

from __future__ import annotations

import uuid
from datetime import datetime
from decimal import Decimal

from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import (
    GUID,
    Base,
    JSONType,
    TimestampMixin,
    UUIDPrimaryKeyMixin,
)


class AuditLog(UUIDPrimaryKeyMixin, Base):
    """Immutable before/after record of every sensitive staff action (§78)."""

    __tablename__ = "audit_logs"

    actor_id: Mapped[uuid.UUID | None] = mapped_column(GUID(), index=True)
    actor_role: Mapped[str | None] = mapped_column(String(64), index=True)
    actor_type: Mapped[str] = mapped_column(String(24), default="staff", nullable=False)
    action: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    entity: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    entity_id: Mapped[uuid.UUID | None] = mapped_column(GUID(), index=True)
    before: Mapped[dict | None] = mapped_column(JSONType, default=None)
    after: Mapped[dict | None] = mapped_column(JSONType, default=None)
    correlation_id: Mapped[str | None] = mapped_column(String(64), index=True)
    ip_address: Mapped[str | None] = mapped_column(String(64))
    user_agent: Mapped[str | None] = mapped_column(String(255))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, index=True
    )

    __table_args__ = (Index("ix_audit_logs_entity_created", "entity", "entity_id", "created_at"),)


class AnalyticsEvent(UUIDPrimaryKeyMixin, Base):
    """Funnel instrumentation (§3, §113). Client-reported events are
    best-effort; server-derived events are authoritative."""

    __tablename__ = "analytics_events"

    event_name: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    source: Mapped[str] = mapped_column(String(16), default="client", nullable=False)
    customer_id: Mapped[uuid.UUID | None] = mapped_column(GUID(), index=True)
    request_id: Mapped[uuid.UUID | None] = mapped_column(GUID(), index=True)
    session_id: Mapped[str | None] = mapped_column(String(64), index=True)
    platform: Mapped[str | None] = mapped_column(String(16))
    app_version: Mapped[str | None] = mapped_column(String(32))
    properties: Mapped[dict | None] = mapped_column(JSONType, default=None)
    occurred_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, index=True
    )
    received_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (
        Index("ix_analytics_events_name_occurred", "event_name", "occurred_at"),
        Index("ix_analytics_events_customer_occurred", "customer_id", "occurred_at"),
    )


class AiClassification(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """AI suggestion plus the human decision, both preserved (§69)."""

    __tablename__ = "ai_classifications"

    request_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("service_requests.id", ondelete="CASCADE"), index=True
    )
    customer_id: Mapped[uuid.UUID | None] = mapped_column(GUID(), index=True)
    input_text_reference: Mapped[str | None] = mapped_column(Text)
    input_media_references: Mapped[list | None] = mapped_column(JSONType, default=None)

    predicted_category: Mapped[str | None] = mapped_column(String(64), index=True)
    predicted_problem: Mapped[str | None] = mapped_column(String(64))
    confidence: Mapped[Decimal | None] = mapped_column(Numeric(5, 4))
    inspection_recommended: Mapped[bool | None] = mapped_column(Boolean)

    model_provider: Mapped[str | None] = mapped_column(String(32))
    model_name: Mapped[str | None] = mapped_column(String(96))
    model_version: Mapped[str | None] = mapped_column(String(32))
    raw_metadata: Mapped[dict | None] = mapped_column(JSONType, default=None)
    error_code: Mapped[str | None] = mapped_column(String(64))
    latency_ms: Mapped[int | None] = mapped_column(Integer)

    human_approved_category: Mapped[str | None] = mapped_column(String(64))
    human_approved_problem: Mapped[str | None] = mapped_column(String(64))
    reviewed_by_id: Mapped[uuid.UUID | None] = mapped_column(GUID())
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    was_corrected: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)


class MaintenanceRecord(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Denormalised per-property service history — the product moat (§17)."""

    __tablename__ = "maintenance_records"

    property_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("properties.id", ondelete="CASCADE"), nullable=False, index=True
    )
    request_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("service_requests.id", ondelete="CASCADE"), unique=True, nullable=False
    )
    customer_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("customer_profiles.id", ondelete="CASCADE"), index=True
    )
    category_code: Mapped[str] = mapped_column(String(48), nullable=False, index=True)
    problem_code: Mapped[str | None] = mapped_column(String(64), index=True)
    customer_description: Mapped[str | None] = mapped_column(Text)
    diagnosis: Mapped[str | None] = mapped_column(Text)
    resolution: Mapped[str | None] = mapped_column(Text)
    price: Mapped[Decimal | None] = mapped_column(Numeric(10, 2))
    materials_summary: Mapped[str | None] = mapped_column(Text)
    technician_id: Mapped[uuid.UUID | None] = mapped_column(GUID(), index=True)
    media_references: Mapped[list | None] = mapped_column(JSONType, default=None)
    inspection_findings: Mapped[dict | None] = mapped_column(JSONType, default=None)
    had_complaint: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    had_rework: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    is_completed: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    served_on: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, index=True
    )
    recurrence_group_key: Mapped[str | None] = mapped_column(String(96), index=True)
    recurrence_index: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    related_request_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("service_requests.id", ondelete="SET NULL"), index=True
    )

    __table_args__ = (
        Index("ix_maintenance_records_property_served", "property_id", "served_on"),
        Index("ix_maintenance_records_recurrence", "recurrence_group_key", "recurrence_index"),
    )