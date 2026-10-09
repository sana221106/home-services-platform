"""Verification email over the Gmail HTTPS API using a stored OAuth refresh token."""

from __future__ import annotations

import base64
import math
from email.message import EmailMessage
from email.utils import formataddr
from threading import Lock
from time import monotonic
from typing import NoReturn

import httpx
from pydantic import SecretStr

from app.core.config import settings
from app.core.exceptions import IntegrationUnavailableError
from app.core.logging import get_logger
from app.services.email_service import mask_email

log = get_logger(__name__)

_TOKEN_URL = "https://oauth2.googleapis.com/token"  # noqa: S105
_SEND_URL = "https://gmail.googleapis.com/gmail/v1/users/me/messages/send"
_TIMEOUT_SECONDS = 15.0
_EXPIRY_MARGIN_SECONDS = 60.0
_token_lock = Lock()
_access_token: SecretStr | None = None
_expires_at = 0.0


def _fail(to: str, reason: str, *, status_code: int | None = None) -> NoReturn:
    # Never include an upstream body, exception text, credentials or MIME here.
    log.error(
        "otp_email_failed",
        provider="gmail_api",
        email_masked=mask_email(to),
        status_code=status_code,
        safe_error_reason=reason,
    )
    raise IntegrationUnavailableError(
        "Sending the verification email failed. Please try again."
    ) from None


def _get_access_token(client: httpx.Client, *, to: str) -> str:
    global _access_token, _expires_at

    secret = settings.gmail_client_secret
    refresh_token = settings.gmail_refresh_token
    if (
        not settings.gmail_client_id.strip()
        or secret is None
        or not secret.get_secret_value().strip()
        or refresh_token is None
        or not refresh_token.get_secret_value().strip()
        or not settings.gmail_sender_email.strip()
    ):
        _fail(to, "not_configured")

    # OTP endpoints run in worker threads. Only one thread refreshes at a time.
    with _token_lock:
        if _access_token is not None and monotonic() < _expires_at:
            return _access_token.get_secret_value()

        _access_token = None
        _expires_at = 0.0
        requested_at = monotonic()
        response = client.post(
            _TOKEN_URL,
            data={
                "client_id": settings.gmail_client_id,
                "client_secret": secret.get_secret_value(),
                "refresh_token": refresh_token.get_secret_value(),
                "grant_type": "refresh_token",
            },
        )
        if not response.is_success:
            _fail(to, "oauth_refresh_failed", status_code=response.status_code)

        try:
            payload = response.json()
        except ValueError:
            _fail(to, "invalid_oauth_response", status_code=response.status_code)
        if not isinstance(payload, dict):
            _fail(to, "invalid_oauth_response", status_code=response.status_code)
        token = payload.get("access_token")
        expires_in = payload.get("expires_in")
        if (
            not isinstance(token, str)
            or not token
            or not token.isascii()
            or any(character.isspace() for character in token)
            or isinstance(expires_in, bool)
            or not isinstance(expires_in, (int, float))
            or not math.isfinite(expires_in)
            or expires_in <= 0
        ):
            _fail(to, "invalid_oauth_response", status_code=response.status_code)

        _access_token = SecretStr(token)
        _expires_at = requested_at + max(0.0, expires_in - _EXPIRY_MARGIN_SECONDS)
        return token


def _invalidate_access_token(rejected_token: str) -> None:
    global _access_token, _expires_at

    with _token_lock:
        # A concurrent request may already have refreshed this rejected token.
        if _access_token is not None and _access_token.get_secret_value() == rejected_token:
            _access_token = None
            _expires_at = 0.0


def _build_message(*, to: str, code: str, ttl_minutes: int) -> EmailMessage:
    message = EmailMessage()
    message["From"] = formataddr((settings.gmail_sender_name, settings.gmail_sender_email))
    message["To"] = to
    message["Subject"] = "Home Services Verification Code"
    message.set_content(
        "Your Home Services verification code is:\n\n"
        f"{code}\n\n"
        f"This code expires in {ttl_minutes} minutes.\n\n"
        "If you did not request this code, you can ignore this email.\n"
    )
    return message


def send_verification_code(to: str, *, code: str, ttl_minutes: int) -> None:
    """Send once, with at most one token refresh/retry after a Gmail 401.

    All other failures are surfaced through the existing safe 503 envelope.
    Redirects are disabled so credentials cannot follow a redirect off Google.
    """
    try:
        message = _build_message(to=to, code=code, ttl_minutes=ttl_minutes)
        raw = base64.urlsafe_b64encode(message.as_bytes()).decode("ascii").rstrip("=")
    except (ValueError, UnicodeError):
        _fail(to, "invalid_email_message")

    try:
        with httpx.Client(timeout=_TIMEOUT_SECONDS, follow_redirects=False) as client:
            token = _get_access_token(client, to=to)
            for attempt in range(2):
                response = client.post(
                    _SEND_URL,
                    headers={"Authorization": f"Bearer {token}"},
                    json={"raw": raw},
                )
                if response.status_code == 401:
                    _invalidate_access_token(token)
                    if attempt == 0:
                        token = _get_access_token(client, to=to)
                        continue
                if not response.is_success:
                    _fail(to, "gmail_send_failed", status_code=response.status_code)
                log.info("otp_email_sent", provider="gmail_api", email_masked=mask_email(to))
                return
    except httpx.TimeoutException:
        _fail(to, "timeout")
    except httpx.RequestError:
        _fail(to, "network_error")
