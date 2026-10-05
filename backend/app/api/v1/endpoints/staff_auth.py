"""Staff authentication and permission profile (§70, §77)."""

from __future__ import annotations

from fastapi import APIRouter, Request
from sqlalchemy import select

from app.api.dependencies import CurrentStaff, DbSession
from app.core.rate_limit import LOGIN_LIMIT, limiter
from app.db.models.identity import Role
from app.schemas.admin import (
    StaffLoginRequest,
    StaffProfileResponse,
    TokenPairSchema,
)
from app.schemas.common import MessageResponse
from app.services import auth_service

router = APIRouter(prefix="/staff/auth", tags=["staff-auth"])


@router.post(
    "/login",
    response_model=TokenPairSchema,
    summary="Email + password login (staff only)",
)
@limiter.limit(LOGIN_LIMIT)
def login(payload: StaffLoginRequest, request: Request, db: DbSession) -> TokenPairSchema:
    staff, tokens = auth_service.authenticate_staff(
        db, email=payload.email, password=payload.password
    )
    db.commit()
    return TokenPairSchema(
        access_token=tokens.access_token,
        refresh_token=tokens.refresh_token,
        expires_in=tokens.expires_in,
    )


@router.get(
    "/me",
    response_model=StaffProfileResponse,
    summary="Current staff identity, roles and effective permissions",
)
def me(db: DbSession, staff: CurrentStaff) -> StaffProfileResponse:
    # Role is the mapped table. StaffRole is the enum re-exported from
    # app.db.models.identity, so selecting it built an unresolvable FROM clause
    # and /staff/auth/me failed for every staff user.
    roles = list(
        db.execute(select(Role).where(Role.code.in_(staff.roles))).scalars()
    )
    return StaffProfileResponse(
        staff_id=staff.staff.id,
        # StaffUser has no email column; auth_service.staff_email resolves the
        # real contact identity. staff.staff.email raised AttributeError.
        email=auth_service.staff_email(staff),
        full_name=staff.staff.full_name,
        is_active=staff.staff.is_active,
        roles=sorted(role.code for role in roles),
        permissions=sorted(staff.permissions),
    )


@router.post("/logout", response_model=MessageResponse, summary="Revoke staff sessions")
def logout(db: DbSession, staff: CurrentStaff) -> MessageResponse:
    auth_service.revoke_all_for_user(db, user_id=staff.staff.user_id)
    db.commit()
    return MessageResponse(message="تم تسجيل الخروج.")