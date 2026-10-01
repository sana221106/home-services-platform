"""Declarative base, shared column mixins and enum helpers (§60).

Conventions enforced here so every business table gets the same guarantees:
UUID primary keys, timezone-aware ``created_at``/``updated_at``, and a
JSON column type that works on both PostgreSQL and SQLite (test harness).
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import DateTime, Enum as SAEnum, MetaData, String, func
from sqlalchemy.dialects.postgresql import JSONB, UUID as PGUUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy.types import JSON, TypeDecorator, Uuid

NAMING_CONVENTION = {
    "ix": "ix_%(column_0_label)s",
    "uq": "uq_%(table_name)s_%(column_0_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}


class GUID(TypeDecorator[uuid.UUID]):
    """UUID column that renders natively on PostgreSQL and as CHAR(32) elsewhere."""

    impl = Uuid(as_uuid=True)
    cache_ok = True

    def load_dialect_impl(self, dialect: Any) -> Any:
        if dialect.name == "postgresql":
            return dialect.type_descriptor(PGUUID(as_uuid=True))
        return dialect.type_descriptor(Uuid(as_uuid=True))


#: JSONB on PostgreSQL, JSON on other dialects (the SQLite test harness).
JSONType = JSONB().with_variant(JSON(), "sqlite")


def enum_column(enum_cls: type, name: str | None = None, **kwargs: Any) -> SAEnum:
    """Native PostgreSQL enum with a plain-text fallback for SQLite tests."""
    return SAEnum(
        enum_cls,
        name=name or f"{enum_cls.__name__.lower()}_enum",
        native_enum=False,
        validate_strings=True,
        values_callable=lambda e: [member.value for member in e],
        **kwargs,
    )


class Base(DeclarativeBase):
    metadata = MetaData(naming_convention=NAMING_CONVENTION)
    type_annotation_map = {dict[str, Any]: JSONType, uuid.UUID: GUID}


def utcnow() -> datetime:
    return datetime.now(UTC)


class UUIDPrimaryKeyMixin:
    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )


class SoftDeleteMixin:
    """Archival instead of hard delete for business records (§141)."""

    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)

    @property
    def is_deleted(self) -> bool:
        return self.deleted_at is not None


class ActorMixin:
    created_by_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True)
    created_by_role: Mapped[str | None] = mapped_column(String(64), nullable=True)


__all__ = [
    "ActorMixin",
    "Base",
    "GUID",
    "JSONType",
    "NAMING_CONVENTION",
    "SoftDeleteMixin",
    "TimestampMixin",
    "UUIDPrimaryKeyMixin",
    "enum_column",
    "utcnow",
]