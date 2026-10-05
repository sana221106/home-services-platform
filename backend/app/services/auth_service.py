"""Authentication and session lifecycle (§4, §90, §91).

Credentials are stored hashed; refresh tokens are stored as SHA-256 digests and
revoked on logout. Ownership checks never trust a client-supplied identifier.
"""

from __future__ import annotations

import hashlib
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session, selectinload

from app.core.config import settings
from app.core.enums import Permission, StaffRole
from app.core.exceptions import (
    AuthenticationError,
    InvalidCredentialsError,
    NotFoundError,
    OtpAttemptsExceededError,
    OtpExpiredError,
    PermissionDeniedError,
)
from app.core.logging import get_logger
from app.core.permissions import permissions_for_roles
from app.core.security import generate_otp, hash_refresh_token, token_service, verify_password
from app.db.models.identity import (
    CustomerProfile,
    OtpChallenge,
    OtpDeliveryLog,
    PermissionRecord,
    RefreshToken,
    Role,
    RolePermission,
    StaffRoleAssignment,
    StaffUser,
    User,
)
from app.utils.time import ensure_aware, now_utc

log = get_logger(__name__)


@dataclass(frozen=True, slots=True)
class AuthenticatedCustomer:
    user: User
    profile: CustomerProfile


@dataclass(frozen=True, slots=True)
class AuthenticatedStaff:
    user: User
    staff: StaffUser
    roles: tuple[str, ...]
    permissions: frozenset[str]


@dataclass(frozen=True, slots=True)
class IssuedTokens:
    access_token: str
    refresh_token: str
    expires_in: int
    expires_at: datetime


def _hash_otp(code: str) -> str:
    return hashlib.sha256(f"otp:{code}".encode()).hexdigest()


def normalise_phone(phone: str) -> str:
    cleaned = phone.strip().replace(" ", "").replace("-", "")
    return cleaned if cleaned.startswith("+") else f"+{cleaned.lstrip('0') or '0'}"


def _refresh_expiry() -> datetime:
    return now_utc() + timedelta(days=settings.refresh_token_ttl_days)


# ------------------------------------------------------------------ customer


def find_or_create_user(session: Session, *, phone: str) -> tuple[User, bool]:
    normalised = normalise_phone(phone)
    user = session.execute(select(User).where(User.phone == normalised)).scalar_one_or_none()
    if user is not None:
        return user, False
    user = User(phone=normalised, phone_country_code="+20")
    session.add(user)
    session.flush()
    return user, True


def start_otp(
    session: Session, *, phone: str, ip_address: str | None = None
) -> tuple[User, bool, int]:
    """Create a challenge and return ``(user, is_new_customer, ttl_seconds)``."""
    user, _created = find_or_create_user(session, phone=phone)
    if not user.is_active:
        raise AuthenticationError("This account is not active.", code="ACCOUNT_INACTIVE")

    code = generate_otp()
    session.add(
        OtpChallenge(
            user_id=user.id,
            code_hash=_hash_otp(code),
            expires_at=now_utc() + timedelta(minutes=settings.otp_ttl_minutes),
            max_attempts=settings.otp_max_attempts,
            ip_address=ip_address,
        )
    )
    session.flush()

    masked = f"{user.phone[:4]}***{user.phone[-3:]}"
    session.add(
        OtpDeliveryLog(
            user_id=user.id,
            provider="log_only",
            destination_masked=masked,
            delivered=True,
        )
    )
    session.flush()

    if settings.debug:
        # Development only: the OTP reaches the log, never the API response (§93).
        log.info("otp_issued", phone_masked=masked, otp_debug_value=code)

    return user, True, settings.otp_ttl_minutes * 60


def verify_otp(
    session: Session,
    *,
    phone: str,
    code: str,
    full_name: str | None = None,
) -> tuple[AuthenticatedCustomer, IssuedTokens]:
    normalised = normalise_phone(phone)
    user = session.execute(select(User).where(User.phone == normalised)).scalar_one_or_none()
    if user is None:
        raise InvalidCredentialsError()

    challenge = session.execute(
        select(OtpChallenge)
        .where(OtpChallenge.user_id == user.id, OtpChallenge.consumed_at.is_(None))
        .order_by(OtpChallenge.created_at.desc())
        .limit(1)
    ).scalar_one_or_none()
    if challenge is None:
        raise OtpExpiredError()

    now = now_utc()
    if ensure_aware(challenge.expires_at) <= now:
        raise OtpExpiredError()

    if challenge.attempts >= challenge.max_attempts:
        raise OtpAttemptsExceededError()

    if challenge.code_hash != _hash_otp(code):
        challenge.attempts += 1
        session.flush()
        raise InvalidCredentialsError()

    challenge.consumed_at = now
    user.last_login_at = now
    user.failed_login_count = 0

    profile = session.execute(
        select(CustomerProfile).where(CustomerProfile.user_id == user.id)
    ).scalar_one_or_none()
    if profile is None:
        profile = CustomerProfile(
            user_id=user.id,
            full_name=(full_name or f"عميل {normalised[-4:]}").strip()[:160],
        )
        session.add(profile)
        session.flush()
    elif full_name and not profile.full_name:
        profile.full_name = full_name.strip()[:160]

    tokens = _issue_tokens(session, user=user, customer_id=profile.id)
    return AuthenticatedCustomer(user=user, profile=profile), tokens


def _issue_tokens(
    session: Session, *, user: User, customer_id: uuid.UUID | None
) -> IssuedTokens:
    access_token, expires_at = token_service.create_access_token(
        subject=str(user.id),
        customer_id=str(customer_id) if customer_id else None,
    )
    refresh_token = token_service.create_refresh_token(
        subject=str(user.id), customer_id=str(customer_id) if customer_id else None
    )
    session.add(
        RefreshToken(
            user_id=user.id,
            token_hash=hash_refresh_token(refresh_token),
            expires_at=_refresh_expiry(),
        )
    )
    session.flush()
    return IssuedTokens(
        access_token=access_token,
        refresh_token=refresh_token,
        expires_in=settings.access_token_ttl_minutes * 60,
        expires_at=expires_at,
    )


def refresh_session(session: Session, *, refresh_token: str) -> IssuedTokens:
    claims = token_service.decode(refresh_token, expected_type="refresh")
    stored = session.execute(
        select(RefreshToken).where(RefreshToken.token_hash == hash_refresh_token(refresh_token))
    ).scalar_one_or_none()
    if stored is None or stored.revoked_at is not None:
        raise AuthenticationError("Session expired. Please sign in again.", code="TOKEN_REVOKED")
    if ensure_aware(stored.expires_at) <= now_utc():
        raise AuthenticationError("Session expired. Please sign in again.", code="TOKEN_EXPIRED")

    user = session.get(User, uuid.UUID(claims.subject))
    if user is None or not user.is_active:
        raise AuthenticationError()

    profile = session.execute(
        select(CustomerProfile).where(CustomerProfile.user_id == user.id)
    ).scalar_one_or_none()
    if profile is None:
        raise AuthenticationError("Customer profile missing.")

    stored.revoked_at = now_utc()
    return _issue_tokens(session, user=user, customer_id=profile.id)


def revoke_refresh_token(session: Session, *, refresh_token: str | None) -> None:
    if not refresh_token:
        return
    stored = session.execute(
        select(RefreshToken).where(RefreshToken.token_hash == hash_refresh_token(refresh_token))
    ).scalar_one_or_none()
    if stored is not None and stored.revoked_at is None:
        stored.revoked_at = now_utc()
        session.flush()


def revoke_all_for_user(session: Session, *, user_id: uuid.UUID) -> None:
    for token in session.execute(
        select(RefreshToken).where(
            RefreshToken.user_id == user_id, RefreshToken.revoked_at.is_(None)
        )
    ).scalars():
        token.revoked_at = now_utc()
    session.flush()


def get_customer_by_id(session: Session, *, customer_id: uuid.UUID) -> AuthenticatedCustomer:
    profile = session.get(CustomerProfile, customer_id)
    if profile is None or profile.deleted_at is not None:
        raise NotFoundError("Customer not found.")
    user = session.get(User, profile.user_id)
    if user is None:
        raise NotFoundError("Customer not found.")
    return AuthenticatedCustomer(user=user, profile=profile)


# --------------------------------------------------------------------- staff


def load_staff_permissions(
    session: Session, *, staff_id: uuid.UUID
) -> tuple[tuple[str, ...], frozenset[str]]:
    role_codes = tuple(
        session.execute(
            select(Role.code)
            .select_from(StaffRoleAssignment)
            .join(Role, Role.id == StaffRoleAssignment.role_id)
            .where(StaffRoleAssignment.staff_id == staff_id)
        ).scalars()
    )
    permission_codes = tuple(
        session.execute(
            select(PermissionRecord.code)
            .select_from(StaffRoleAssignment)
            .join(Role, Role.id == StaffRoleAssignment.role_id)
            .join(RolePermission, RolePermission.role_id == Role.id)
            .join(PermissionRecord, PermissionRecord.id == RolePermission.permission_id)
            .where(StaffRoleAssignment.staff_id == staff_id)
            .distinct()
        ).scalars()
    )
    if not permission_codes and role_codes:
        known = {StaffRole(code) for code in role_codes if code in StaffRole.__members__}
        permission_codes = tuple(sorted(str(item) for item in permissions_for_roles(known)))
    return role_codes, frozenset(permission_codes)


def authenticate_staff(
    session: Session, *, email: str, password: str
) -> tuple[AuthenticatedStaff, IssuedTokens]:
    identifier = email.strip().lower()
    staff = session.execute(
        select(StaffUser)
        .options(selectinload(StaffUser.user))
        .join(User, User.id == StaffUser.user_id)
        .where(
            or_(
                func.lower(User.phone) == identifier,
                func.lower(StaffUser.employee_code) == identifier,
            )
        )
    ).scalars().first()

    if staff is None or staff.user is None or not staff.is_active or not staff.user.is_active:
        raise InvalidCredentialsError("Invalid staff credentials.")
    if not staff.password_hash:
        raise InvalidCredentialsError("Staff password is not provisioned.")
    if not verify_password(password, staff.password_hash):
        staff.user.failed_login_count += 1
        session.flush()
        raise InvalidCredentialsError("Invalid staff credentials.")

    roles, permissions = load_staff_permissions(session, staff_id=staff.id)
    staff.user.last_login_at = now_utc()
    staff.user.failed_login_count = 0

    access_token, expires_at = token_service.create_access_token(
        subject=str(staff.user.id),
        roles=roles,
        permissions=tuple(sorted(permissions)),
        staff_id=str(staff.id),
    )
    refresh_token = token_service.create_refresh_token(subject=str(staff.user.id))
    session.add(
        RefreshToken(
            user_id=staff.user.id,
            token_hash=hash_refresh_token(refresh_token),
            expires_at=_refresh_expiry(),
        )
    )
    session.flush()

    tokens = IssuedTokens(
        access_token=access_token,
        refresh_token=refresh_token,
        expires_in=settings.access_token_ttl_minutes * 60,
        expires_at=expires_at,
    )
    return (
        AuthenticatedStaff(user=staff.user, staff=staff, roles=roles, permissions=permissions),
        tokens,
    )


def authenticate_staff_by_token(
    session: Session, *, access_token: str
) -> AuthenticatedStaff:
    claims = token_service.decode(access_token, expected_type="access")
    if not claims.staff_id:
        raise AuthenticationError("This token is not a staff session.")
    staff = session.execute(
        select(StaffUser).options(selectinload(StaffUser.user)).where(StaffUser.id == uuid.UUID(claims.staff_id))
    ).scalar_one_or_none()
    if staff is None or staff.user is None or not staff.is_active or not staff.user.is_active:
        raise AuthenticationError("Staff account is inactive.")
    roles, permissions = load_staff_permissions(session, staff_id=staff.id)
    return AuthenticatedStaff(
        user=staff.user, staff=staff, roles=roles, permissions=permissions
    )


def require_permission(staff: AuthenticatedStaff, permission: Permission) -> None:
    if StaffRole.SUPER_ADMIN.value in staff.roles:
        return
    if permission.value not in staff.permissions:
        raise PermissionDeniedError(
            "You do not have permission to perform this action.",
            details={"required": permission.value},
        )


def staff_email(staff: AuthenticatedStaff) -> str:
    """Best available contact identity for audit attribution."""
    return staff.staff.employee_code or str(staff.staff.id)