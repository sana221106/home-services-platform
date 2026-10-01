"""Auth contracts (§4, §26)."""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator

PHONE_PATTERN = r"^\+?[0-9]{8,15}$"


class PhoneRequest(BaseModel):
    model_config = ConfigDict(json_schema_extra={"example": {"phone": "+201001234567"}})

    phone: str = Field(pattern=PHONE_PATTERN)
    full_name: str | None = Field(default=None, max_length=160)

    @field_validator("phone")
    @classmethod
    def _normalise(cls, value: str) -> str:
        return value.strip().replace(" ", "")


class OtpRequest(BaseModel):
    phone: str = Field(pattern=PHONE_PATTERN)


class VerifyOtpRequest(BaseModel):
    phone: str = Field(pattern=PHONE_PATTERN)
    code: str = Field(min_length=4, max_length=8)
    full_name: str | None = Field(default=None, max_length=160)


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "Bearer"
    expires_in: int
    expires_at: datetime


class CustomerProfileResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    full_name: str
    phone: str
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