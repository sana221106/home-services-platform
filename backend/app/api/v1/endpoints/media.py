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
from app.db.models.support import Conversation, Message, MessageAttachment
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
    # A soft-deleted photo is gone for everyone, staff included. This condition
    # was previously inverted (``deleted_at is None``), which 404'd every live
    # photo and served every soft-deleted one.
    if media is None or media.deleted_at is not None:
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
    # message_attachments has no soft-delete column; absence is the only way an
    # attachment goes away, and the FK cascade removes the row.
    if attachment is None:
        raise NotFoundError("Attachment not found.")
    return Response(
        content=_read(attachment.storage_path),
        media_type=attachment.mime_type,
        headers={"Cache-Control": "private, max-age=3600"},
    )


@router.get(
    "/message-attachments/{attachment_id}/content",
    summary="Stream your own chat attachment",
    response_class=Response,
)
def customer_message_attachment_content(
    attachment_id: uuid.UUID,
    db: DbSession,
    customer: CurrentCustomer,
) -> Response:
    """Customer-facing counterpart to the staff route.

    ``message_attachments`` links to a message and nothing else, so ownership is
    proven by walking attachment → message → conversation → customer. Returning
    the raw ``storage_path`` instead would leak internal bucket paths (§79).
    """
    attachment = db.get(MessageAttachment, attachment_id)
    if attachment is None:
        raise NotFoundError("Attachment not found.")
    message = db.get(Message, attachment.message_id)
    if message is None:
        raise NotFoundError("Attachment not found.")
    conversation = db.get(Conversation, message.conversation_id)
    if conversation is None or conversation.customer_id != customer.profile.id:
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