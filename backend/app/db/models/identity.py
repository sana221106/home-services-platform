"""Identity & access tables: users, customers, staff, roles, permissions."""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.enums import StaffRole
from app.db.base import Base, GUID, SoftDeleteMixin, TimestampMixin, UUIDPrimaryKeyMixin


class User(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Supabase-mirrored auth identity. Password/OTP material lives here only
    when the platform runs its own credential path (Supabase Auth disabled)."""

    __tablename__ = "users"

    phone: Mapped[str] = mapped_column(String(32), unique=True, nullable=False, index=True)
    phone_country_code: Mapped[str] = mapped_column(String(8), default="+20", nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    is_staff: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    supabase_user_id: Mapped[str | None] = mapped_column(String(128), unique=True)
    failed_login_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)

    customer_profile: Mapped[CustomerProfile | None] = relationship(
        back_populates="user", uselist=False, cascade="all, delete-orphan"
    )
    staff_user: Mapped[StaffUser | None] = relationship(
        back_populates="user", uselist=False, cascade="all, delete-orphan"
    )


class CustomerProfile(UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin, Base):
    __tablename__ = "customer_profiles"

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False
    )
    full_name: Mapped[str] = mapped_column(String(160), nullable=False)
    email: Mapped[str | None] = mapped_column(String(255))
    avatar_url: Mapped[str | None] = mapped_column(String(512))
    preferred_language: Mapped[str] = mapped_column(String(8), default="ar", nullable=False)

    user: Mapped[User] = relationship(back_populates="customer_profile")
    properties: Mapped[list["Property"]] = relationship(  # noqa: F821
        back_populates="owner", cascade="all, delete-orphan"
    )

    __table_args__ = (Index("ix_customer_profiles_user_id", "user_id"),)


class StaffUser(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "staff_users"

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False
    )
    employee_code: Mapped[str] = mapped_column(String(32), unique=True, nullable=False)
    full_name: Mapped[str] = mapped_column(String(160), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    password_hash: Mapped[str | None] = mapped_column(String(255))

    user: Mapped[User] = relationship(back_populates="staff_user")
    roles: Mapped[list[StaffRoleAssignment]] = relationship(
        back_populates="staff", cascade="all, delete-orphan"
    )


class Role(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "roles"

    code: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    name_ar: Mapped[str] = mapped_column(String(120), nullable=False)
    description: Mapped[str | None] = mapped_column(String(400))

    assignments: Mapped[list[StaffRoleAssignment]] = relationship(
        back_populates="role", cascade="all, delete-orphan"
    )
    permissions: Mapped[list[RolePermission]] = relationship(
        back_populates="role", cascade="all, delete-orphan"
    )


class PermissionRecord(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "permissions"

    code: Mapped[str] = mapped_column(String(96), unique=True, nullable=False)
    description: Mapped[str | None] = mapped_column(String(400))

    roles: Mapped[list[RolePermission]] = relationship(
        back_populates="permission", cascade="all, delete-orphan"
    )


class RolePermission(Base):
    __tablename__ = "role_permissions"

    role_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("roles.id", ondelete="CASCADE"), primary_key=True
    )
    permission_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("permissions.id", ondelete="CASCADE"), primary_key=True
    )

    role: Mapped[Role] = relationship(back_populates="permissions")
    permission: Mapped[PermissionRecord] = relationship(back_populates="roles")


class StaffRoleAssignment(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "staff_roles"

    staff_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("staff_users.id", ondelete="CASCADE"), nullable=False
    )
    role_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("roles.id", ondelete="CASCADE"), nullable=False
    )

    staff: Mapped[StaffUser] = relationship(back_populates="roles")
    role: Mapped[Role] = relationship(back_populates="assignments")

    __table_args__ = (
        UniqueConstraint("staff_id", "role_id", name="staff_roles_staff_id_role_id"),
    )


class OtpChallenge(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Phone -> OTP challenge (§4). Codes are stored hashed."""

    __tablename__ = "otp_challenges"

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    code_hash: Mapped[str] = mapped_column(String(128), nullable=False)
    attempts: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    max_attempts: Mapped[int] = mapped_column(Integer, default=5, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    ip_address: Mapped[str | None] = mapped_column(String(64))

    __table_args__ = (Index("ix_otp_challenges_user_active", "user_id", "consumed_at"),)


class RefreshToken(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Hashed refresh tokens, revocable on logout (§91)."""

    __tablename__ = "refresh_tokens"

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    token_hash: Mapped[str] = mapped_column(String(128), unique=True, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    device_id: Mapped[str | None] = mapped_column(String(128))

    __table_args__ = (Index("ix_refresh_tokens_user_active", "user_id", "revoked_at"),)


class OtpDeliveryLog(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "otp_delivery_logs"

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    provider: Mapped[str] = mapped_column(String(32), default="log_only", nullable=False)
    destination_masked: Mapped[str] = mapped_column(String(32), nullable=False)
    delivered: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    failure_reason: Mapped[str | None] = mapped_column(String(255))


SEED_ROLES: tuple[StaffRole, ...] = tuple(StaffRole)