"""FastAPI dependencies: sessions, authenticated customer, authenticated staff
and permission guards (§90).

Every protected route resolves the actor from the bearer token. Client-supplied
``customer_id`` / ``request_id`` / ``property_id`` values are always re-checked
against the resolved actor to prevent IDOR (§90, §103).
"""

from __future__ import annotations

import uuid
from collections.abc import Callable
from typing import Annotated

from fastapi import Depends, Header, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.enums import Permission
from app.core.exceptions import AuthenticationError
from app.core.security import token_service
from app.db.session import get_db
from app.services import auth_service

bearer_scheme = HTTPBearer(auto_error=False, description="JWT access token")

DbSession = Annotated[Session, Depends(get_db)]


def correlation_id(request: Request) -> str | None:
    return request.headers.get("X-Correlation-ID")


def _extract_token(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
) -> str:
    if credentials is None or not credentials.credentials:
        raise AuthenticationError("Authentication is required.")
    return credentials.credentials


def get_current_customer(
    db: DbSession,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
) -> auth_service.AuthenticatedCustomer:
    token = _extract_token(credentials)
    claims = token_service.decode(token, expected_type="access")
    if claims.customer_id is None:
        raise AuthenticationError("This token is not a customer session.")
    return auth_service.get_customer_by_id(
        db, customer_id=uuid.UUID(claims.customer_id)
    )


CurrentCustomer = Annotated[auth_service.AuthenticatedCustomer, Depends(get_current_customer)]


def get_current_staff(
    db: DbSession,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
) -> auth_service.AuthenticatedStaff:
    token = _extract_token(credentials)
    return auth_service.authenticate_staff_by_token(db, access_token=token)


CurrentStaff = Annotated[auth_service.AuthenticatedStaff, Depends(get_current_staff)]


def require(*permissions: Permission) -> Callable[[auth_service.AuthenticatedStaff], auth_service.AuthenticatedStaff]:
    """Guard factory. Super admin bypasses; everyone else needs every listed
    permission (§75-§78)."""

    def _guard(
        staff: Annotated[auth_service.AuthenticatedStaff, Depends(get_current_staff)],
    ) -> auth_service.AuthenticatedStaff:
        for permission in permissions:
            auth_service.require_permission(staff, permission)
        return staff

    return _guard


def client_ip(request: Request) -> str | None:
    forwarded = request.headers.get("X-Forwarded-For")
    if forwarded:
        return forwarded.split(",")[0].strip()[:64]
    return request.client.host if request.client else None


def user_agent(request: Request) -> str | None:
    return request.headers.get("User-Agent")


def is_production() -> bool:
    return settings.is_production


RequestIdHeader = Annotated[str | None, Header(alias="X-Correlation-ID")]
