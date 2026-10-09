"""Verification email delivery (§93).

The code itself is untouched: the platform still generates a 6-digit OTP,
hashes it, gives it one TTL and one attempt budget. Only the channel that
carries it moved from a handset to an inbox, so this module owns transport and
nothing else — no code generation, no storage, no API response.

Delivery is selected by EMAIL_OTP_PROVIDER. SMTP without a host retains the
development log-only fallback (§135). Gmail API failures always propagate so
the request cannot report a code as sent when delivery failed.
"""

from __future__ import annotations

import smtplib
from email.message import EmailMessage
from email.utils import formataddr

from app.core.config import settings
from app.core.exceptions import IntegrationUnavailableError
from app.core.logging import get_logger

log = get_logger(__name__)

#: `OtpDeliveryLog.destination_masked` is 32 chars, and an unmasked address is
#: still personal data in a log sink.
_MAX_MASKED = 32


def mask_email(email: str) -> str:
    """``m***@gmail.com``: enough for an operator to correlate, not to read."""
    local, separator, domain = email.strip().partition("@")
    if not separator or not domain:
        return "***"
    masked = f"{local[:1]}***@{domain}"
    return masked[:_MAX_MASKED]


def _build_message(*, to: str, code: str, ttl_minutes: int) -> EmailMessage:
    sender = settings.email_from or settings.smtp_user or "no-reply@localhost"
    message = EmailMessage()
    # Arabic subject and body: this is customer-facing copy, and the account
    # language defaults to Arabic. The SMTP policy RFC 2047-encodes the header,
    # so a non-ASCII Subject is safe on any relay.
    message["Subject"] = f"رمز التحقق من {settings.email_from_name}"
    message["From"] = formataddr((settings.email_from_name, sender))
    message["To"] = to

    message.set_content(
        f"""{settings.email_from_name}

رمز التحقق الخاص بك هو:

    {code}

أدخل هذا الرمز في التطبيق لإكمال تسجيل الدخول.
الرمز صالح لمدة {ttl_minutes} دقائق.

لم تطلب هذا الرمز؟ تجاهل هذه الرسالة — لن يدخل أحد إلى حسابك بدون الرمز.
"""
    )
    return message


def send_verification_code(to: str, *, code: str, ttl_minutes: int) -> None:
    """Deliver `code` to `to` with the selected provider, or raise on failure.

    Raising is deliberate. Returning quietly would show the customer "code sent"
    while the mailbox stays empty, and they would sit there retrying a flow that
    can never succeed.
    """
    if settings.email_otp_provider == "gmail_api":
        from app.services import gmail_service

        gmail_service.send_verification_code(to, code=code, ttl_minutes=ttl_minutes)
        return

    if settings.email_otp_provider == "log_only" or not settings.email_configured:
        if settings.debug and not settings.is_production:
            log.info("otp_issued", email_masked=mask_email(to), otp_debug_value=code)
        else:
            log.warning("otp_email_unconfigured", email_masked=mask_email(to))
        return

    password = settings.smtp_password
    try:
        with smtplib.SMTP(
            settings.smtp_host, settings.smtp_port, timeout=settings.smtp_timeout_seconds
        ) as smtp:
            if settings.smtp_starttls:
                smtp.starttls()
            if settings.smtp_user and password is not None and password.get_secret_value():
                smtp.login(settings.smtp_user, password.get_secret_value())
            smtp.send_message(_build_message(to=to, code=code, ttl_minutes=ttl_minutes))
    except (OSError, smtplib.SMTPException) as exc:
        log.error(
            "otp_email_failed",
            email_masked=mask_email(to),
            host=settings.smtp_host,
            port=settings.smtp_port,
            error=str(exc),
        )
        raise IntegrationUnavailableError(
            "Sending the verification email failed. Please try again."
        ) from exc
    log.info("otp_email_sent", email_masked=mask_email(to))
