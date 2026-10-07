"""Auth contracts (§4, §26)."""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator

PHONE_PATTERN = r"^\+?[0-9]{8,15}$"
#: Deliberately permissive: the address only has to be well-formed enough to
#: route mail to it. Deliverability is the relay's answer, not a regex's.
EMAIL_PATTERN = r"^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$"


class EmailOtpRequest(BaseModel):
    """Asks for a verification code to be sent to an email address.

    `phone` is contact detail rather than identity: it is stored, shown on the
    profile, and never used to decide who is signing in — which is why it is
    optional and why the same number may appear on more than one account.
    """

    model_config = ConfigDict(
        json_schema_extra={
            "example": {"email": "sara@example.com", "phone": "+201001234567"}
        }
    )

    email: str = Field(pattern=EMAIL_PATTERN, max_length=255)
    phone: str | None = Field(default=None, pattern=PHONE_PATTERN)

    @field_validator("email")
    @classmethod
    def _normalise_email(cls, value: str) -> str:
        return value.strip().lower()

    @field_validator("phone")
    @classmethod
    def _trim_phone(cls, value: str | None) -> str | None:
        if value is None:
            return None
        return value.strip().replace(" ", "").replace("-", "") or None


class VerifyOtpRequest(BaseModel):
    email: str = Field(pattern=EMAIL_PATTERN, max_length=255)
    code: str = Field(min_length=4, max_length=8)
    full_name: str | None = Field(default=None, max_length=160)

    @field_validator("email")
    @classmethod
    def _normalise_email(cls, value: str) -> str:
        return value.strip().lower()


class GoogleSignInRequest(BaseModel):
    """The ID token minted by the mobile SDK for the signed-in Google account.

    It is not a credential this platform can mint, so it carries no password and
    no phone: the server verifies it against Google and derives identity from the
    claims (§90).
    """

    id_token: str = Field(min_length=32, max_length=4096)


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "Bearer"  # noqa: S105 - RFC 6750 scheme, not a secret
    expires_in: int
    expires_at: datetime


class CustomerProfileResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    full_name: str
    #: Optional: the customer may leave it blank, and a Google sign-in never
    #: asks for it at all.
    phone: str | None = None
    email: str | None = None
    avatar_url: str | None = None
    preferred_language: str = "ar"


class AuthSessionResponse(BaseModel):
    tokens: TokenPair
    customer: CustomerProfileResponse


class OtpResponse(BaseModel):
    """The code is never returned to the mobile client in production (§93)."""

    message: str
    expires_in_seconds: int
    is_new_customer: bool


class RefreshRequest(BaseModel):
    refresh_token: str


class LogoutRequest(BaseModel):
    refresh_token: str | None = None


class StaffLoginRequest(BaseModel):
    email: str = Field(max_length=255)
    password: str = Field(min_length=8, max_length=128)


class StaffSessionResponse(BaseModel):
    tokens: TokenPair
    staff: StaffProfileResponse


class StaffProfileResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    full_name: str
    email: str
    employee_code: str
    roles: list[str]
    permissions: list[str]
    is_active: bool = True