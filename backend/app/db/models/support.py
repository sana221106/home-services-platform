"""Support & quality: conversations, messages, call logs, complaints, rework,
reviews, notifications, device tokens and internal staff notes."""

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
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.enums import (
    ComplaintReason,
    ComplaintStatus,
    FollowUpOutcome,
    NotificationType,
    ReviewStatus,
)
from app.db.base import (
    GUID,
    Base,
    JSONType,
    TimestampMixin,
    UUIDPrimaryKeyMixin,
    enum_column,
)


class Conversation(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Platform support threads only — never technician <-> customer (§16)."""

    __tablename__ = "conversations"

    customer_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("customer_profiles.id", ondelete="CASCADE"), nullable=False, index=True
    )
    request_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("service_requests.id", ondelete="SET NULL"), index=True
    )
    subject: Mapped[str | None] = mapped_column(String(200))
    is_open: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False, index=True)
    last_message_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    assigned_staff_id: Mapped[uuid.UUID | None] = mapped_column(GUID(), index=True)

    messages: Mapped[list[Message]] = relationship(
        back_populates="conversation", cascade="all, delete-orphan", order_by="Message.sent_at"
    )


class Message(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "messages"

    conversation_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("conversations.id", ondelete="CASCADE"), nullable=False, index=True
    )
    sender_type: Mapped[str] = mapped_column(String(16), nullable=False)
    sender_id: Mapped[uuid.UUID | None] = mapped_column(GUID(), index=True)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    sent_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    latitude: Mapped[Decimal | None] = mapped_column(Numeric(9, 6))
    longitude: Mapped[Decimal | None] = mapped_column(Numeric(9, 6))
    correlation_id: Mapped[str | None] = mapped_column(String(64))

    conversation: Mapped[Conversation] = relationship(back_populates="messages")
    attachments: Mapped[list[MessageAttachment]] = relationship(
        back_populates="message", cascade="all, delete-orphan"
    )

    __table_args__ = (Index("ix_messages_conversation_sent", "conversation_id", "sent_at"),)


class MessageAttachment(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "message_attachments"

    message_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("messages.id", ondelete="CASCADE"), nullable=False, index=True
    )
    storage_path: Mapped[str] = mapped_column(String(512), nullable=False)
    mime_type: Mapped[str] = mapped_column(String(64), nullable=False)
    size_bytes: Mapped[int] = mapped_column(Integer, nullable=False)
    checksum_sha256: Mapped[str] = mapped_column(String(64), nullable=False)
    kind: Mapped[str] = mapped_column(String(24), default="IMAGE", nullable=False)

    message: Mapped[Message] = relationship(back_populates="attachments")


class SupportCallLog(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Call-centre interaction log — the input to Customer 360 funnel insight."""

    __tablename__ = "support_call_logs"

    customer_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("customer_profiles.id", ondelete="CASCADE"), nullable=False, index=True
    )
    request_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("service_requests.id", ondelete="SET NULL"), index=True
    )
    agent_id: Mapped[uuid.UUID] = mapped_column(GUID(), index=True)
    direction: Mapped[str] = mapped_column(String(16), default="outbound", nullable=False)
    outcome: Mapped[FollowUpOutcome | None] = mapped_column(
        enum_column(FollowUpOutcome), default=None
    )
    duration_seconds: Mapped[int | None] = mapped_column(Integer)
    notes: Mapped[str | None] = mapped_column(Text)
    called_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    next_follow_up_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    escalation_required: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    __table_args__ = (Index("ix_support_call_logs_customer_called", "customer_id", "called_at"),)


class Complaint(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Private complaint record. Never surfaced in a public feed (§15)."""

    __tablename__ = "complaints"

    request_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("service_requests.id", ondelete="SET NULL"), index=True
    )
    customer_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("customer_profiles.id", ondelete="CASCADE"), nullable=False, index=True
    )
    reference_code: Mapped[str] = mapped_column(String(24), unique=True, nullable=False, index=True)
    reason: Mapped[ComplaintReason] = mapped_column(enum_column(ComplaintReason), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[ComplaintStatus] = mapped_column(
        enum_column(ComplaintStatus), default=ComplaintStatus.OPEN, nullable=False, index=True
    )
    assigned_employee_id: Mapped[uuid.UUID | None] = mapped_column(GUID(), index=True)
    resolution: Mapped[str | None] = mapped_column(Text)
    internal_notes: Mapped[str | None] = mapped_column(Text)
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    closed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    requires_qc: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    requires_rework: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    sla_due_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    attachments: Mapped[list[ComplaintAttachment]] = relationship(
        back_populates="complaint", cascade="all, delete-orphan"
    )
    rework_visits: Mapped[list[ReworkVisit]] = relationship(
        back_populates="complaint", cascade="all, delete-orphan"
    )

    __table_args__ = (Index("ix_complaints_status_created", "status", "created_at"),)


class ComplaintAttachment(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "complaint_attachments"

    complaint_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("complaints.id", ondelete="CASCADE"), nullable=False, index=True
    )
    storage_path: Mapped[str] = mapped_column(String(512), nullable=False)
    mime_type: Mapped[str] = mapped_column(String(64), nullable=False)
    size_bytes: Mapped[int] = mapped_column(Integer, nullable=False)
    checksum_sha256: Mapped[str] = mapped_column(String(64), nullable=False)

    complaint: Mapped[Complaint] = relationship(back_populates="attachments")


class ReworkVisit(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "rework_visits"

    complaint_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("complaints.id", ondelete="CASCADE"), nullable=False, index=True
    )
    request_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("service_requests.id", ondelete="SET NULL"), index=True
    )
    technician_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("technicians.id", ondelete="SET NULL"), index=True
    )
    scheduled_start: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    work_performed: Mapped[str | None] = mapped_column(Text)
    cost: Mapped[Decimal | None] = mapped_column(Numeric(10, 2))
    waived_charge: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    qc_passed: Mapped[bool | None] = mapped_column(Boolean)
    status: Mapped[str] = mapped_column(String(32), default="PLANNED", nullable=False)

    complaint: Mapped[Complaint] = relationship(back_populates="rework_visits")


class Review(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Rating is about the service/company, not a public technician profile (§14)."""

    __tablename__ = "reviews"

    request_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("service_requests.id", ondelete="CASCADE"), nullable=False, index=True
    )
    customer_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("customer_profiles.id", ondelete="CASCADE"), nullable=False, index=True
    )
    rating: Mapped[int] = mapped_column(Integer, nullable=False)
    text: Mapped[str | None] = mapped_column(Text)
    image_storage_path: Mapped[str | None] = mapped_column(String(512))
    publication_status: Mapped[ReviewStatus] = mapped_column(
        enum_column(ReviewStatus), default=ReviewStatus.PENDING, nullable=False, index=True
    )
    moderated_by_id: Mapped[uuid.UUID | None] = mapped_column(GUID())
    moderated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    moderation_note: Mapped[str | None] = mapped_column(String(400))

    __table_args__ = (UniqueConstraint("request_id", name="uq_reviews_request_id"),)


class Notification(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "notifications"

    customer_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("customer_profiles.id", ondelete="CASCADE"), nullable=False, index=True
    )
    request_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("service_requests.id", ondelete="CASCADE"), index=True
    )
    type: Mapped[NotificationType] = mapped_column(
        enum_column(NotificationType), nullable=False, index=True
    )
    title_ar: Mapped[str] = mapped_column(String(200), nullable=False)
    body_ar: Mapped[str] = mapped_column(Text, nullable=False)
    payload: Mapped[dict | None] = mapped_column(JSONType, default=None)
    is_read: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False, index=True)
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    push_sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    push_failure_reason: Mapped[str | None] = mapped_column(String(255))

    __table_args__ = (Index("ix_notifications_customer_created", "customer_id", "created_at"),)


class DeviceToken(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "device_tokens"

    customer_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("customer_profiles.id", ondelete="CASCADE"), nullable=False, index=True
    )
    token: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    platform: Mapped[str] = mapped_column(String(16), default="android", nullable=False)
    app_version: Mapped[str | None] = mapped_column(String(32))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class StaffNote(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Internal-only note, attached to a customer, request or complaint."""

    __tablename__ = "staff_notes"

    body: Mapped[str] = mapped_column(Text, nullable=False)
    author_id: Mapped[uuid.UUID] = mapped_column(GUID(), nullable=False, index=True)
    author_role: Mapped[str | None] = mapped_column(String(64))
    customer_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("customer_profiles.id", ondelete="CASCADE"), index=True
    )
    request_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("service_requests.id", ondelete="CASCADE"), index=True
    )
    complaint_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("complaints.id", ondelete="CASCADE"), index=True
    )
    is_pinned: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)