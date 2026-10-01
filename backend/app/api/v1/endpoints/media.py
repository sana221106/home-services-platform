"""Media streaming behind authorisation (§30, §90).

Storage paths are never exposed. The client always asks for
``/media/{id}/content`` and the endpoint re-checks ownership before streaming.
"""

from __future__ import annotations

import uuid

from fastapi import APIRouter
from fastapi.responses import Response

from app.api.dependencies import CurrentCustomer, CurrentStaff, DbSession
from app.core.enums import Permission
from app.core.exceptions import NotFoundError
from app.db.models.finance import PaymentProof
from app.db.models.requests import RequestMedia, ServiceRequest
from app.db.models.support import MessageAttachment
from app.services.media_service import make_storage_client

router = APIRouter(prefix="/media", tags=["media"])


def _read(storage_path: str) -> bytes:
    return make_storage_client().read(storage_path)


@router.get(
    "/{media_id}/content",
    summary="Stream a request photo (owner or authorised staff only)",
    response_class=Response,
)
def request_media_content(
    media_id: uuid.UUID,
    db: DbSession,
    customer: CurrentCustomer,
) -> Response:
    media = db.get(RequestMedia, media_id)
    if media is None or media.deleted_at is not None:
        raise NotFoundError("Media not found.")
    request = db.get(ServiceRequest, media.request_id)
    if request is None or request.customer_id != customer.profile.id:
        raise NotFoundError("Media not found.")
    return Response(
        content=_read(media.storage_path),
        media_type=media.mime_type,
        headers={"Cache-Control": "private, max-age=3600"},
    )


@router.get(
    "/staff/request-media/{media_id}/content",
    summary="Stream a request photo as staff (review needs it)",
    response_class=Response,
)
def staff_request_media_content(
    media_id: uuid.UUID, db: DbSession, staff: CurrentStaff
) -> Response:
    from app.core.permissions import assert_permission

    assert_permission(staff.permissions, Permission.REQUEST_READ)
    media = db.get(RequestMedia, media_id)
    if media is None or media.deleted_at is None:
        raise NotFoundError("Media not found.")
    return Response(
        content=_read(media.storage_path),
        media_type=media.mime_type,
        headers={"Cache-Control": "private, max-age=3600"},
    )


@router.get(
    "/staff/message-attachments/{attachment_id}/content",
    summary="Stream a chat attachment (staff only)",
    response_class=Response,
)
def message_attachment_content(
    attachment_id: uuid.UUID, db: DbSession, staff: CurrentStaff
) -> Response:
    from app.core.permissions import assert_permission

    assert_permission(staff.permissions, Permission.CHAT_READ)
    attachment = db.get(MessageAttachment, attachment_id)
    if attachment is None or attachment.deleted_at is not None:
        raise NotFoundError("Attachment not found.")
    return Response(
        content=_read(attachment.storage_path),
        media_type=attachment.mime_type,
        headers={"Cache-Control": "private, max-age=3600"},
    )


@router.get(
    "/staff/payment-proofs/{proof_id}/content",
    summary="Stream a payment proof (finance only)",
    response_class=Response,
)
def payment_proof_content(
    proof_id: uuid.UUID, db: DbSession, staff: CurrentStaff
) -> Response:
    from app.core.permissions import assert_permission

    assert_permission(staff.permissions, Permission.PAYMENT_READ)
    proof = db.get(PaymentProof, proof_id)
    if proof is None:
        raise NotFoundError("Payment proof not found.")
    return Response(
        content=_read(proof.storage_path),
        media_type=proof.mime_type,
        headers={"Cache-Control": "private, no-store"},
    )