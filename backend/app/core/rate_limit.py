"""Rate limiting for abuse-sensitive endpoints (§94).

Limits are applied through ``slowapi`` keyed on client IP + route. Financial and
OTP routes get their own tighter budgets. Disabled in tests so suites stay
deterministic (``RATE_LIMIT_ENABLED=false``).
"""

from __future__ import annotations

from fastapi import Request
from slowapi import Limiter
from slowapi.util import get_remote_address
from starlette.responses import JSONResponse

from app.core.config import settings
from app.core.logging import get_logger

log = get_logger(__name__)

limiter = Limiter(
    key_func=get_remote_address,
    default_limits=[settings.rate_limit_default] if settings.rate_limit_enabled else [],
    enabled=settings.rate_limit_enabled,
    # Off on purpose: slowapi injects X-RateLimit-* headers only when the
    # endpoint returns a Response or takes a `response: Response` argument. Our
    # endpoints return Pydantic models, so headers_enabled=True makes every
    # limited route raise "parameter `response` must be an instance of
    # starlette.responses.Response" (a 500). The 429 still carries Retry-After,
    # set by rate_limit_exceeded_handler below.
    headers_enabled=False,
)

# Named budgets, referenced from route decorators by ``@limiter.limit(...)``.
OTP_LIMIT = settings.rate_limit_otp
LOGIN_LIMIT = settings.rate_limit_login
MEDIA_LIMIT = settings.rate_limit_media
CHAT_LIMIT = settings.rate_limit_chat
COMPLAINT_LIMIT = settings.rate_limit_complaint
AI_LIMIT = settings.rate_limit_ai
PAYMENT_PROOF_LIMIT = settings.rate_limit_payment_proof


def rate_limit_exceeded_handler(request: Request, exc: Exception) -> JSONResponse:
    retry_after = getattr(exc, "retry_after", None) or 60
    log.warning("rate_limit_exceeded", path=request.url.path, retry_after=retry_after)
    return JSONResponse(
        status_code=429,
        content={
            "code": "RATE_LIMITED",
            "message": "Too many requests. Please slow down.",
            "details": {"retry_after_seconds": retry_after},
        },
        headers={"Retry-After": str(retry_after)},
    )