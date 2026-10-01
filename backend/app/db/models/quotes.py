"""Versioned quotes. Old revisions are superseded, never destroyed (§64)."""

from __future__ import annotations

import uuid
from datetime import datetime
from decimal import Decimal

from sqlalchemy import Boolean, DateTime, ForeignKey, Index, Integer, Numeric, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.enums import QuoteStatus, Urgency
from app.db.base import (
    Base,
    GUID,
    TimestampMixin,
    UUIDPrimaryKeyMixin,
    enum_column,
)


class Quote(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """One immutable revision of the price offered to the customer."""

    __tablename__ = "quotes"

    request_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("service_requests.id", ondelete="CASCADE"), nullable=False, index=True
    )
    revision_number: Mapped[int] = mapped_column(Integer, nullable=False)
    status: Mapped[QuoteStatus] = mapped_column(
        enum_column(QuoteStatus), default=QuoteStatus.DRAFT, nullable=False, index=True
    )
    urgency: Mapped[Urgency] = mapped_column(enum_column(Urgency), default=Urgency.NORMAL)

    service_cost: Mapped[Decimal] = mapped_column(Numeric(10, 2), default=Decimal("0"))
    materials_cost: Mapped[Decimal] = mapped_column(Numeric(10, 2), default=Decimal("0"))
    urgency_fee: Mapped[Decimal] = mapped_column(Numeric(10, 2), default=Decimal("0"))
    inspection_fee: Mapped[Decimal] = mapped_column(Numeric(10, 2), default=Decimal("0"))
    discount: Mapped[Decimal] = mapped_column(Numeric(10, 2), default=Decimal("0"))
    subtotal: Mapped[Decimal] = mapped_column(Numeric(10, 2), default=Decimal("0"))
    total: Mapped[Decimal] = mapped_column(Numeric(10, 2), default=Decimal("0"))
    deposit_amount: Mapped[Decimal] = mapped_column(Numeric(10, 2), default=Decimal("0"))
    estimated_duration_minutes: Mapped[int] = mapped_column(Integer, default=120, nullable=False)

    notes: Mapped[str | None] = mapped_column(Text)
    internal_notes: Mapped[str | None] = mapped_column(Text)
    requires_deposit: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    created_by_id: Mapped[uuid.UUID | None] = mapped_column(GUID(), index=True)
    sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    viewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    decided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    decided_by_customer_id: Mapped[uuid.UUID | None] = mapped_column(GUID())
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    supersedes_quote_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("quotes.id", ondelete="SET NULL")
    )

    request: Mapped["ServiceRequest"] = relationship(back_populates="quotes")  # noqa: F821
    items: Mapped[list[QuoteItem]] = relationship(
        back_populates="quote", cascade="all, delete-orphan", order_by="QuoteItem.position"
    )
    revisions: Mapped[list[QuoteRevision]] = relationship(
        back_populates="quote",
        cascade="all, delete-orphan",
        foreign_keys="QuoteRevision.quote_id",
    )

    __table_args__ = (
        Index("uq_quotes_request_revision", "request_id", "revision_number"),
        Index("ix_quotes_request_status", "request_id", "status"),
    )


class QuoteRevision(Base):
    """Snapshot of a revision's header totals, kept for reporting/audit (§64)."""

    __tablename__ = "quote_revisions"

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True)
    quote_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("quotes.id", ondelete="CASCADE"), nullable=False, index=True
    )
    revision_number: Mapped[int] = mapped_column(Integer, nullable=False)
    previous_total: Mapped[Decimal | None] = mapped_column(Numeric(10, 2))
    new_total: Mapped[Decimal] = mapped_column(Numeric(10, 2), nullable=False)
    change_reason: Mapped[str | None] = mapped_column(String(400))
    created_by_id: Mapped[uuid.UUID | None] = mapped_column(GUID())
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)

    quote: Mapped[Quote] = relationship(back_populates="revisions", foreign_keys=[quote_id])


class QuoteItem(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "quote_items"

    quote_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("quotes.id", ondelete="CASCADE"), nullable=False, index=True
    )
    position: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    label_ar: Mapped[str] = mapped_column(String(200), nullable=False)
    quantity: Mapped[Decimal] = mapped_column(Numeric(10, 2), default=Decimal("1"))
    unit_price: Mapped[Decimal] = mapped_column(Numeric(10, 2), default=Decimal("0"))
    line_total: Mapped[Decimal] = mapped_column(Numeric(10, 2), default=Decimal("0"))
    item_type: Mapped[str] = mapped_column(String(32), default="SERVICE", nullable=False)

    quote: Mapped[Quote] = relationship(back_populates="items")