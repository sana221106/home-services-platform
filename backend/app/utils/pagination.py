"""Pagination and stable human-readable reference codes."""

from __future__ import annotations

import secrets
import string

from fastapi import Query

_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"  # no look-alike characters


def generate_reference_code(prefix: str, *, length: int = 8) -> str:
    body = "".join(secrets.choice(_ALPHABET) for _ in range(length))
    return f"{prefix}-{body}"


def pagination_params(
    page: int = Query(default=1, ge=1, le=100_000),
    per_page: int = Query(default=20, ge=1, le=200),
) -> tuple[int, int]:
    return page, per_page


def offset_for(page: int, per_page: int) -> int:
    return (page - 1) * per_page


SAFE_FILENAME_CHARS = string.ascii_letters + string.digits + "-_"