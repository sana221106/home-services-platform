"""Customer-owned properties and property contacts."""

from __future__ import annotations

import uuid
from decimal import Decimal

from sqlalchemy import Boolean, ForeignKey, Index, Numeric, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, GUID, SoftDeleteMixin, TimestampMixin, UUIDPrimaryKeyMixin


class Property(UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin, Base):
    __tablename__ = "properties"

    customer_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("customer_profiles.id", ondelete="CASCADE"), nullable=False, index=True
    )
    label: Mapped[str] = mapped_column(String(120), nullable=False)
    is_default: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    property_type: Mapped[str] = mapped_column(String(48), default="apartment", nullable=False)
    governorate: Mapped[str] = mapped_column(String(80), nullable=False)
    city: Mapped[str] = mapped_column(String(80), nullable=False)
    zone: Mapped[str | None] = mapped_column(String(120))
    district: Mapped[str | None] = mapped_column(String(120))
    street: Mapped[str | None] = mapped_column(String(255))
    building: Mapped[str | None] = mapped_column(String(80))
    floor: Mapped[str | None] = mapped_column(String(32))
    apartment: Mapped[str | None] = mapped_column(String(32))
    landmark: Mapped[str | None] = mapped_column(String(255))
    notes: Mapped[str | None] = mapped_column(Text)
    latitude: Mapped[Decimal | None] = mapped_column(Numeric(9, 6))
    longitude: Mapped[Decimal | None] = mapped_column(Numeric(9, 6))

    owner: Mapped["CustomerProfile"] = relationship(  # noqa: F821
        back_populates="properties"
    )
    contacts: Mapped[list[PropertyContact]] = relationship(
        back_populates="property", cascade="all, delete-orphan"
    )

    __table_args__ = (
        Index("ix_properties_customer_id_is_default", "customer_id", "is_default"),
        Index("ix_properties_geo", "governorate", "city", "district"),
    )


class PropertyContact(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "property_contacts"

    property_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("properties.id", ondelete="CASCADE"), nullable=False, index=True
    )
    contact_name: Mapped[str] = mapped_column(String(160), nullable=False)
    phone: Mapped[str] = mapped_column(String(32), nullable=False)
    relation: Mapped[str | None] = mapped_column(String(48))
    is_primary: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    property: Mapped[Property] = relationship(back_populates="contacts")