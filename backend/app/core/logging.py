"""Structured logging with secret redaction (§93).

Passwords, OTPs, tokens, authorization headers and payment references must
never reach a log sink. ``RedactingProcessor`` scrubs configured keys and
pattern-shaped JWTs from the event dict before rendering.
"""

from __future__ import annotations

import logging
import re
import sys
from typing import Any

import structlog

from app.core.config import settings

_SENSITIVE_KEYS = frozenset(
    {
        "password",
        "new_password",
        "old_password",
        "otp",
        "otp_code",
        "code",
        "access_token",
        "refresh_token",
        "token",
        "authorization",
        "api_key",
        "supabase_service_role_key",
        "secret",
        "jwt_secret",
        "reference_number",
        "private_key",
        "firebase_credentials_json",
    }
)

_JWT_RE = re.compile(r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{4,}\b")
_BEARER_RE = re.compile(r"(?i)\bBearer\s+[A-Za-z0-9._-]{8,}")


def _scrub(value: Any, key: str | None = None) -> Any:
    if key is not None and key.lower() in _SENSITIVE_KEYS:
        return "[REDACTED]"
    if isinstance(value, dict):
        return {k: _scrub(v, k) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_scrub(item) for item in value]
    if isinstance(value, str):
        scrubbed = _BEARER_RE.sub("Bearer [REDACTED]", value)
        return _JWT_RE.sub("[REDACTED-JWT]", scrubbed)
    return value


class RedactingProcessor:
    """structlog processor that strips sensitive material."""

    def __call__(self, logger: Any, name: str, event_dict: dict[str, Any]) -> dict[str, Any]:
        return _scrub(event_dict)  # type: ignore[return-value]


def configure_logging() -> None:
    level = logging.DEBUG if settings.debug else logging.INFO
    logging.basicConfig(format="%(message)s", stream=sys.stdout, level=level)

    processors: list[Any] = [
        structlog.contextvars.merge_contextvars,
        structlog.stdlib.add_log_level,
        structlog.processors.TimeStamper(fmt="iso", utc=True),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        RedactingProcessor(),
    ]
    if settings.is_production:
        processors.append(structlog.processors.JSONRenderer())
    else:
        processors.append(structlog.dev.ConsoleRenderer(colors=True))

    structlog.configure(
        processors=processors,
        wrapper_class=structlog.make_filtering_bound_logger(level),
        logger_factory=structlog.PrintLoggerFactory(),
        cache_logger_on_first_use=True,
    )


def get_logger(name: str) -> Any:
    return structlog.get_logger(name)