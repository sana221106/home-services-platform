"""Shared response envelopes and pagination (§96, §137)."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any, Generic, TypeVar

from pydantic import BaseModel, ConfigDict, Field

T = TypeVar("T")


class ErrorBody(BaseModel):
    code: str = Field(examples=["QUOTE_EXPIRED"])
    message: str = Field(examples=["The current quote has expired."])
    details: dict[str, Any] = Field(default_factory=dict)


class ErrorResponse(BaseModel):
    """The one and only error shape exposed to clients."""

    code: str
    message: str
    details: dict[str, Any] = Field(default_factory=dict)


class MessageResponse(BaseModel):
    message: str
    request_id: str | None = None


class PageMeta(BaseModel):
    page: int = Field(ge=1)
    per_page: int = Field(ge=1, le=200)
    total: int = Field(ge=0)
    total_pages: int = Field(ge=0)
    has_next: bool
    has_previous: bool


class Page(BaseModel, Generic[T]):
    """Cursor-free offset pagination for admin lists and customer lists alike."""

    model_config = ConfigDict(populate_by_name=True)

    items: list[T]
    meta: PageMeta

    @classmethod
    def build(
        cls, items: list[T], *, total: int, page: int, per_page: int
    ) -> Page[T]:
        total_pages = (total + per_page - 1) // per_page if per_page else 0
        return cls(
            items=items,
            meta=PageMeta(
                page=page,
                per_page=per_page,
                total=total,
                total_pages=total_pages,
                has_next=page < total_pages,
                has_previous=page > 1,
            ),
        )


class IdResponse(BaseModel):
    id: uuid.UUID


class HealthResponse(BaseModel):
    """Deliberately free of infrastructure detail (§110)."""

    status: str = Field(examples=["ok"])
    service: str
    environment: str
    version: str
    time: datetime