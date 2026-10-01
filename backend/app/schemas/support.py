"""Complaints, reviews, chat, support, notifications and profile (§14, §15, §16)."""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.core.enums import (
    ComplaintReason,
    ComplaintStatus,
    NotificationType,
    ReviewStatus,
)


# ----------------------------------------------------------------- complaints


class ComplaintCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: uuid.UUID | None = None
    reason: ComplaintReason
    description: str = Field(min_length=10, max_length=4000)
    idempotency_key: str | None = Field(default=None, max_length=80)


class ComplaintResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    reference_code: str
    request_id: uuid.UUID | None = None
    reason: ComplaintReason
    description: str
    status: ComplaintStatus
    resolution: str | None = None
    created_at: datetime
    resolved_at: datetime | None = None
    closed_at: datetime | None = None
    requires_rework: bool = False
    attachment_urls: list[str] = Field(default_factory=list)


class ComplaintAssignRequest(BaseModel):
    employee_id: uuid.UUID


class ComplaintResolveRequest(BaseModel):
    resolution: str = Field(min_length=5, max_length=4000)
    requires_rework: bool = False
    schedule_rework_at: datetime | None = None


class ComplaintStatusChangeRequest(BaseModel):
    status: ComplaintStatus
    note: str | None = Field(default=None, max_length=1000)


# -------------------------------------------------------------------- reviews


class ReviewCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: uuid.UUID
    rating: int = Field(ge=1, le=5)
    text: str | None = Field(default=None, max_length=2000)
    has_image: bool = False
    idempotency_key: str | None = Field(default=None, max_length=80)


class ReviewResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    request_id: uuid.UUID
    rating: int
    text: str | None = None
    publication_status: ReviewStatus
    image_url: str | None = None
    created_at: datetime


class ModerateReviewRequest(BaseModel):
    status: ReviewStatus
    note: str | None = Field(default=None, max_length=400)


# ----------------------------------------------------------------------- chat


class MessageAttachmentRequest(BaseModel):
    storage_path: str
    mime_type: str
    size_bytes: int


class SendMessageRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    body: str = Field(min_length=1, max_length=4000)
    attachment_ids: list[uuid.UUID] = Field(default_factory=list)
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)

    @field_validator("body")
    @classmethod
    def _trim(cls, value: str) -> str:
        trimmed = value.strip()
        if not trimmed:
            raise ValueError("body must not be blank")
        return trimmed


class MessageResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    conversation_id: uuid.UUID
    sender_type: str
    body: str
    sent_at: datetime
    attachment_urls: list[str] = Field(default_factory=list)


class ConversationResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    request_id: uuid.UUID | None = None
    subject: str | None = None
    is_open: bool
    last_message_at: datetime | None = None
    last_message_preview: str | None = None
    unread_count: int = 0


class StartConversationRequest(BaseModel):
    request_id: uuid.UUID | None = None
    subject: str | None = Field(default=None, max_length=200)
    first_message: str = Field(min_length=1, max_length=4000)


# ------------------------------------------------------------------- support


class SupportContact(BaseModel):
    code: str
    label_ar: str
    phone: str
    available_hours_ar: str | None = None


class SupportPageResponse(BaseModel):
    contacts: list[SupportContact]
    availability_note_ar: str
    can_chat: bool


class LogCallRequest(BaseModel):
    direction: str = Field(default="outbound", max_length=16)
    outcome: str | None = Field(default=None, max_length=32)
    duration_seconds: int | None = Field(default=None, ge=0, le=86400)
    notes: str | None = Field(default=None, max_length=4000)
    next_follow_up_at: datetime | None = None


# ------------------------------------------------------------ notifications


class NotificationResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    request_id: uuid.UUID | None = None
    type: NotificationType
    title_ar: str
    body_ar: str
    payload: dict | None = None
    is_read: bool
    read_at: datetime | None = None
    created_at: datetime


class MarkNotificationsReadRequest(BaseModel):
    ids: list[uuid.UUID] | None = None


class DeviceTokenRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    token: str = Field(min_length=16, max_length=255)
    platform: str = Field(default="android", max_length=16)
    app_version: str | None = Field(default=None, max_length=32)


# ------------------------------------------------------------------- profile


class UpdateProfileRequest(BaseModel):
    full_name: str | None = Field(default=None, min_length=2, max_length=160)
    email: str | None = Field(default=None, max_length=255)
    preferred_language: str | None = Field(default=None, max_length=8)


class ProfileResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    full_name: str
    phone: str
    email: str | None = None
    avatar_url: str | None = None
    preferred_language: str = "ar"
    properties_count: int = 0
    requests_count: int = 0
    completed_orders_count: int = 0
    member_since: datetime | None = None


class RecordAnalyticsEventRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    event_name: str = Field(min_length=2, max_length=64)
    request_id: uuid.UUID | None = None
    session_id: str | None = Field(default=None, max_length=64)
    platform: str | None = Field(default=None, max_length=16)
    app_version: str | None = Field(default=None, max_length=32)
    properties: dict | None = None
    occurred_at: datetime | None = None