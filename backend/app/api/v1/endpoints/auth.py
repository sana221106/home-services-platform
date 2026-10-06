"""Customer authentication endpoints (§70)."""

from __future__ import annotations

from fastapi import APIRouter, Request, status
from sqlalchemy import select

from app.api.dependencies import CurrentCustomer, DbSession, client_ip
from app.core.rate_limit import LOGIN_LIMIT, OTP_LIMIT, limiter
from app.db.models.identity import CustomerProfile
from app.schemas.auth import (
    AuthSessionResponse,
    CustomerProfileResponse,
    GoogleSignInRequest,
    LogoutRequest,
    OtpResponse,
    PhoneRequest,
    RefreshRequest,
    TokenPair,
    VerifyOtpRequest,
)
from app.schemas.common import MessageResponse
from app.services import auth_service

router = APIRouter(prefix="/auth", tags=["auth"])


def _token_pair(tokens: auth_service.IssuedTokens) -> TokenPair:
    return TokenPair(
        access_token=tokens.access_token,
        refresh_token=tokens.refresh_token,
        expires_in=tokens.expires_in,
        expires_at=tokens.expires_at,
    )


def _customer_payload(customer: auth_service.AuthenticatedCustomer) -> CustomerProfileResponse:
    return CustomerProfileResponse(
        id=customer.profile.id,
        full_name=customer.profile.full_name,
        phone=customer.user.phone,
        email=customer.profile.email,
        avatar_url=customer.profile.avatar_url,
        preferred_language=customer.profile.preferred_language,
    )


@router.post(
    "/request-otp",
    response_model=OtpResponse,
    status_code=status.HTTP_202_ACCEPTED,
    summary="Send an OTP to a phone number",
)
@limiter.limit(OTP_LIMIT)
def request_otp(payload: PhoneRequest, request: Request, db: DbSession) -> OtpResponse:
    user, _is_new_user, ttl = auth_service.start_otp(
        db, phone=payload.phone, ip_address=client_ip(request)
    )
    db.commit()
    profile_exists = (
        db.execute(
            select(CustomerProfile.id).where(CustomerProfile.user_id == user.id)
        ).first()
        is not None
    )
    return OtpResponse(
        message="تم إرسال رمز التحقق إلى هاتفك.",
        expires_in_seconds=ttl,
        is_new_customer=not profile_exists,
    )


@router.post("/verify-otp", response_model=AuthSessionResponse, summary="Verify OTP")
@limiter.limit(LOGIN_LIMIT)
def verify_otp(payload: VerifyOtpRequest, request: Request, db: DbSession) -> AuthSessionResponse:
    customer, tokens = auth_service.verify_otp(
        db,
        phone=payload.phone,
        code=payload.code,
        full_name=payload.full_name,
    )
    db.commit()
    return AuthSessionResponse(tokens=_token_pair(tokens), customer=_customer_payload(customer))


@router.post("/google", response_model=AuthSessionResponse, summary="Sign in with Google")
@limiter.limit(LOGIN_LIMIT)
def sign_in_with_google(
    payload: GoogleSignInRequest, request: Request, db: DbSession
) -> AuthSessionResponse:
    customer, tokens = auth_service.google_sign_in(db, id_token_value=payload.id_token)
    db.commit()
    return AuthSessionResponse(tokens=_token_pair(tokens), customer=_customer_payload(customer))


@router.post("/refresh", response_model=TokenPair, summary="Rotate a refresh token")
@limiter.limit(LOGIN_LIMIT)
def refresh(
    payload: RefreshRequest, request: Request, db: DbSession
) -> TokenPair:
    tokens = auth_service.refresh_session(db, refresh_token=payload.refresh_token)
    db.commit()
    return _token_pair(tokens)


@router.post("/logout", response_model=MessageResponse, summary="Revoke the current session")
def logout(payload: LogoutRequest, db: DbSession, customer: CurrentCustomer) -> MessageResponse:
    auth_service.revoke_all_for_user(db, user_id=customer.user.id)
    auth_service.revoke_refresh_token(db, refresh_token=payload.refresh_token)
    db.commit()
    return MessageResponse(message="تم تسجيل الخروج بنجاح.")


@router.get("/me", response_model=CustomerProfileResponse, summary="Current customer")
def me(customer: CurrentCustomer) -> CustomerProfileResponse:
    return _customer_payload(customer)
