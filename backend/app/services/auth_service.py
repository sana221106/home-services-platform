"""Authentication and session lifecycle (§4, §90, §91).

Credentials are stored hashed; refresh tokens are stored as SHA-256 digests and
revoked on logout. Ownership checks never trust a client-supplied identifier.
"""

from __future__ import annotations

import hashlib
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta

from google.auth.transport.requests import Request as GoogleAuthRequest
from google.oauth2 import id_token
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
from app.services import email_service
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


def normalise_email(email: str) -> str:
    """Case-fold only. ``Example@Gmail.com`` and ``example@gmail.com`` are the
    same mailbox, and the unique index on :attr:`User.email` has to agree."""
    return email.strip().lower()


def _refresh_expiry() -> datetime:
    return now_utc() + timedelta(days=settings.refresh_token_ttl_days)


# ------------------------------------------------------------------ customer


def find_or_create_user(
    session: Session, *, email: str, phone: str | None = None
) -> tuple[User, bool]:
    """Land the customer on the one row they already own.

    The email is the identity. The phone is contact detail: whatever number is
    typed now wins so a correction actually sticks, but a blank field never
    clears one already on file — "optional" must not mean "deleted when skipped".
    """
    normalised = normalise_email(email)
    user = session.execute(select(User).where(User.email == normalised)).scalar_one_or_none()
    if user is not None:
        if phone:
            user.phone = normalise_phone(phone)
            session.flush()
        return user, False

    user = User(
        email=normalised,
        phone=normalise_phone(phone) if phone else None,
        phone_country_code="+20",
    )
    session.add(user)
    session.flush()
    return user, True


def start_otp(
    session: Session,
    *,
    email: str,
    phone: str | None = None,
    ip_address: str | None = None,
) -> tuple[User, bool, int]:
    """Create a challenge and return ``(user, is_new_customer, ttl_seconds)``.

    The name deliberately is not taken here: nothing about this request has been
    verified yet, so no profile row is written until the code comes back. The
    caller carries the name forward and hands it to :func:`verify_otp`.
    """
    user, _created = find_or_create_user(session, email=email, phone=phone)
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

    destination = normalise_email(email)
    masked = email_service.mask_email(destination)
    # The transport owns routing and raises before a successful delivery is
    # recorded, including when Gmail is selected but credentials are missing.
    email_service.send_verification_code(
        destination, code=code, ttl_minutes=settings.otp_ttl_minutes
    )
    provider = settings.email_otp_provider if settings.email_configured else "log_only"

    session.add(
        OtpDeliveryLog(
            user_id=user.id,
            provider=provider,
            destination_masked=masked,
            delivered=True,
        )
    )
    session.flush()

    return user, True, settings.otp_ttl_minutes * 60


def verify_otp(
    session: Session,
    *,
    email: str,
    code: str,
    full_name: str | None = None,
) -> tuple[AuthenticatedCustomer, IssuedTokens]:
    normalised = normalise_email(email)
    user = session.execute(select(User).where(User.email == normalised)).scalar_one_or_none()
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
    if not user.email:
        user.email = normalised

    profile = session.execute(
        select(CustomerProfile).where(CustomerProfile.user_id == user.id)
    ).scalar_one_or_none()
    if profile is None:
        profile = CustomerProfile(
            user_id=user.id,
            full_name=(full_name or "").strip()[:160] or "عميل جديد",
            email=normalised,
        )
        session.add(profile)
        session.flush()
    else:
        if full_name and not profile.full_name:
            profile.full_name = full_name.strip()[:160]
        if not profile.email:
            profile.email = normalised

    tokens = _issue_tokens(session, user=user, customer_id=profile.id)
    return AuthenticatedCustomer(user=user, profile=profile), tokens


#: Google signs tokens from either of these; both are accepted because the SDK
#: reports the accounts host differently across versions.
GOOGLE_ISSUERS = frozenset({"https://accounts.google.com", "accounts.google.com"})


def _verify_google_id_token(id_token_value: str) -> dict[str, object]:
    """Validate a Google-issued ID token and return its claims.

    A token Google minted for another application is still a perfectly valid
    Google token, so the signature alone is not enough: the audience has to be
    one of ours or anyone could sign into this platform with their own Google
    app's token.
    """
    if not settings.google_client_ids:
        raise AuthenticationError(
            "Google sign-in is not configured.", code="GOOGLE_NOT_CONFIGURED"
        )

    # One message for every check below: telling the client which claim failed
    # would hand an attacker a checklist, and the honest one is always the same.
    rejected = InvalidCredentialsError("Google could not verify this sign-in.")
    try:
        claims: dict[str, object] = id_token.verify_oauth2_token(
            id_token_value, GoogleAuthRequest()
        )
    except ValueError as exc:  # google-auth reports every rejection as ValueError
        log.info("google_id_token_rejected", reason=str(exc))
        raise rejected from exc

    if claims.get("iss") not in GOOGLE_ISSUERS:
        raise rejected
    if claims.get("aud") not in settings.google_client_ids:
        raise rejected
    if claims.get("email_verified") is False:
        raise rejected
    if not claims.get("sub"):
        raise rejected
    return claims


def google_sign_in(
    session: Session, *, id_token_value: str
) -> tuple[AuthenticatedCustomer, IssuedTokens]:
    """Sign a customer in with the ID token their Google session produced.

    The customer carries no phone here, which is exactly why the phone column
    became nullable: inventing one would have leaked it into their own profile.
    """
    claims = _verify_google_id_token(id_token_value)
    sub = str(claims["sub"])
    email = str(claims.get("email") or "").strip().lower() or None
    name = str(claims.get("name") or "").strip()[:160]
    picture = str(claims.get("picture") or "").strip()[:512] or None

    user = session.execute(
        select(User).where(User.google_sub == sub)
    ).scalar_one_or_none()

    if user is None and email:
        # The same person may have arrived through the OTP path first, so both
        # the address on their user row and the one on a profile created before
        # `users.email` existed are accepted as the link.
        user = session.execute(select(User).where(User.email == email)).scalar_one_or_none()
        if user is None:
            user = (
                session.execute(
                    select(User)
                    .join(CustomerProfile, CustomerProfile.user_id == User.id)
                    .where(func.lower(CustomerProfile.email) == email)
                )
                .scalars()
                .first()
            )
        if user is not None:
            user.google_sub = sub

    is_new = user is None
    if user is None:
        user = User(google_sub=sub, email=email)  # phone stays NULL by design
        session.add(user)
        session.flush()
    elif email and not user.email:
        user.email = email

    if not user.is_active:
        raise AuthenticationError("This account is not active.", code="ACCOUNT_INACTIVE")

    user.last_login_at = now_utc()
    user.failed_login_count = 0

    profile = session.execute(
        select(CustomerProfile).where(CustomerProfile.user_id == user.id)
    ).scalar_one_or_none()
    if profile is None:
        # full_name is NOT NULL, so a Google account without a display name
        # falls back to the local part of its address rather than a blank row.
        profile = CustomerProfile(
            user_id=user.id,
            full_name=name or (email or "").split("@")[0] or "عميل جديد",
            email=email,
            avatar_url=picture,
        )
        session.add(profile)
        session.flush()
    else:
        if not profile.full_name and name:
            profile.full_name = name
        if not profile.email and email:
            profile.email = email
        if not profile.avatar_url and picture:
            profile.avatar_url = picture

    log.info("customer_signed_in", user_id=str(user.id), provider="google", is_new=is_new)
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
