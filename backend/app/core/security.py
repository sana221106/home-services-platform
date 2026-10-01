"""Password hashing and JWT issuance/verification (§86, §93).

Tokens never contain secrets beyond identity + role claims. Refresh tokens are
stored hashed so a database leak cannot be replayed (§91).
"""

from __future__ import annotations

import hashlib
import hmac
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any, Literal

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError

from app.core.config import settings
from app.core.exceptions import AuthenticationError

_hasher = PasswordHasher(
    time_cost=settings.argon2_time_cost,
    memory_cost=settings.argon2_memory_cost,
    parallelism=settings.argon2_parallelism,
)

TokenType = Literal["access", "refresh"]


def hash_password(plain: str) -> str:
    return _hasher.hash(plain)


def verify_password(plain: str, hashed: str) -> bool:
    try:
        _hasher.verify(hashed, plain)
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False
    return True


def needs_rehash(hashed: str) -> bool:
    return _hasher.check_needs_rehash(hashed)


def hash_refresh_token(token: str) -> str:
    """SHA-256 digest used for at-rest storage of refresh tokens."""
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def generate_otp() -> str:
    return f"{uuid.uuid4().int % 1_000_000:06d}"


@dataclass(frozen=True, slots=True)
class TokenClaims:
    subject: str
    token_type: TokenType
    roles: tuple[str, ...]
    permissions: tuple[str, ...]
    staff_id: str | None = None
    customer_id: str | None = None
    jti: str = ""
    expires_at: datetime | None = None


class TokenService:
    def __init__(self) -> None:
        self._secret = settings.jwt_secret.get_secret_value()
        self._algorithm = settings.jwt_algorithm

    def _encode(self, *, claims: dict[str, Any], ttl: timedelta) -> str:
        now = datetime.now(UTC)
        payload = {
            **claims,
            "iat": int(now.timestamp()),
            "nbf": int(now.timestamp()),
            "exp": int((now + ttl).timestamp()),
            "iss": settings.app_name,
        }
        return jwt.encode(payload, self._secret, algorithm=self._algorithm)

    def create_access_token(
        self,
        *,
        subject: str,
        roles: tuple[str, ...] = (),
        permissions: tuple[str, ...] = (),
        staff_id: str | None = None,
        customer_id: str | None = None,
    ) -> tuple[str, datetime]:
        ttl = timedelta(minutes=settings.access_token_ttl_minutes)
        expires_at = datetime.now(UTC) + ttl
        token = self._encode(
            claims={
                "sub": subject,
                "type": "access",
                "roles": list(roles),
                "perms": list(permissions),
                "sid": staff_id,
                "cid": customer_id,
                "jti": uuid.uuid4().hex,
            },
            ttl=ttl,
        )
        return token, expires_at

    def create_refresh_token(self, *, subject: str, customer_id: str | None = None) -> str:
        return self._encode(
            claims={
                "sub": subject,
                "type": "refresh",
                "cid": customer_id,
                "jti": uuid.uuid4().hex,
            },
            ttl=timedelta(days=settings.refresh_token_ttl_days),
        )

    def decode(self, token: str, *, expected_type: TokenType) -> TokenClaims:
        try:
            payload = jwt.decode(
                token,
                self._secret,
                algorithms=[self._algorithm],
                issuer=settings.app_name,
                options={"require": ["exp", "sub", "type"]},
            )
        except jwt.ExpiredSignatureError as exc:
            raise AuthenticationError("Your session has expired.", code="TOKEN_EXPIRED") from exc
        except jwt.InvalidTokenError as exc:
            raise AuthenticationError("Invalid authentication token.") from exc

        if payload.get("type") != expected_type:
            raise AuthenticationError("Invalid authentication token.")

        return TokenClaims(
            subject=str(payload["sub"]),
            token_type=expected_type,
            roles=tuple(payload.get("roles") or ()),
            permissions=tuple(payload.get("perms") or ()),
            staff_id=payload.get("sid"),
            customer_id=payload.get("cid"),
            jti=payload.get("jti", ""),
            expires_at=datetime.fromtimestamp(payload["exp"], tz=UTC),
        )


token_service = TokenService()


def constant_time_equals(left: str, right: str) -> bool:
    return hmac.compare_digest(left.encode("utf-8"), right.encode("utf-8"))