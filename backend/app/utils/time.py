"""Timezone helpers. Canonical storage is UTC; presentation converts to
Africa/Cairo as the application timezone (§60)."""

from __future__ import annotations

from datetime import UTC, datetime
from zoneinfo import ZoneInfo

APPLICATION_TIMEZONE = ZoneInfo("Africa/Cairo")


def now_utc() -> datetime:
    return datetime.now(UTC)


def to_app_timezone(value: datetime) -> datetime:
    if value.tzinfo is None:
        raise ValueError("naive datetime is not accepted; business logic requires tz-aware values")
    return value.astimezone(APPLICATION_TIMEZONE)


def ensure_aware(value: datetime) -> datetime:
    return value if value.tzinfo is not None else value.replace(tzinfo=UTC)


def minutes_between(start: datetime, end: datetime) -> int:
    return int((ensure_aware(end) - ensure_aware(start)).total_seconds() // 60)


def hours_between(start: datetime, end: datetime) -> float:
    return round((ensure_aware(end) - ensure_aware(start)).total_seconds() / 3600, 2)


def age_minutes(since: datetime | None, *, reference: datetime | None = None) -> int | None:
    if since is None:
        return None
    return max(0, minutes_between(since, reference or now_utc()))