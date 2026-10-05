"""Media streaming authorisation and soft-delete regression (§79, §90).

Storage paths are never exposed and every read re-checks ownership. The staff
request-photo endpoint had an inverted soft-delete guard
(``media.deleted_at is None``), which 404'd every *live* photo and tried to
stream every soft-deleted one. ``test_staff_request_media_*`` below pin that
behaviour in both directions so it cannot regress.
"""

from __future__ import annotations

import uuid

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.db.models import RequestMedia
from app.utils.time import now_utc
from tests.conftest import (
    attach_media,
    auth_header,
    customer_token,
    grant_all_permissions,
    staff_token,
)

pytestmark = pytest.mark.filterwarnings("ignore::DeprecationWarning")

CONTENT = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR"


@pytest.fixture()
def live_media(db: Session, service_request, customer) -> RequestMedia:
    return attach_media(db, request=service_request, customer=customer, content=CONTENT)


@pytest.fixture()
def staff_headers(db: Session, super_admin_staff) -> dict[str, str]:
    grant_all_permissions(db, super_admin_staff)
    return auth_header(staff_token(db, super_admin_staff))


# ------------------------------------------------------- staff regression


def test_staff_request_media_streams_live_photo(
    client: TestClient, staff_headers, live_media: RequestMedia
) -> None:
    """A photo that has *not* been deleted must stream for authorised staff.

    This is the assertion the inverted ``deleted_at is None`` guard broke: every
    live photo returned 404.
    """
    response = client.get(
        f"/api/v1/media/staff/request-media/{live_media.id}/content",
        headers=staff_headers,
    )
    assert response.status_code == 200, response.text
    assert response.content == CONTENT
    assert response.headers["content-type"].startswith("image/png")


def test_staff_request_media_hides_soft_deleted_photo(
    client: TestClient, db: Session, staff_headers, live_media: RequestMedia
) -> None:
    """A soft-deleted photo must 404 for staff, exactly as it does for its owner.

    The same inverted guard used to serve these.
    """
    row = db.get(RequestMedia, live_media.id)
    row.deleted_at = now_utc()
    db.flush()

    response = client.get(
        f"/api/v1/media/staff/request-media/{live_media.id}/content",
        headers=staff_headers,
    )
    assert response.status_code == 404, response.text
    assert response.json()["code"] == "NOT_FOUND"


def test_staff_request_media_unknown_id_is_404(
    client: TestClient, staff_headers
) -> None:
    response = client.get(
        f"/api/v1/media/staff/request-media/{uuid.uuid4()}/content",
        headers=staff_headers,
    )
    assert response.status_code == 404


# ------------------------------------------------- customer owner / IDOR


def test_customer_streams_own_request_photo(
    client: TestClient, db: Session, customer, live_media: RequestMedia
) -> None:
    response = client.get(
        f"/api/v1/media/{live_media.id}/content",
        headers=auth_header(customer_token(db, customer)),
    )
    assert response.status_code == 200
    assert response.content == CONTENT


def test_customer_cannot_stream_another_customers_photo(
    client: TestClient, db: Session, other_customer, live_media: RequestMedia
) -> None:
    """IDOR guard: ownership is re-checked on read, not just on write."""
    response = client.get(
        f"/api/v1/media/{live_media.id}/content",
        headers=auth_header(customer_token(db, other_customer)),
    )
    assert response.status_code == 404, response.text
    assert response.json()["code"] == "NOT_FOUND"


def test_customer_cannot_stream_soft_deleted_photo(
    client: TestClient, db: Session, customer, live_media: RequestMedia
) -> None:
    row = db.get(RequestMedia, live_media.id)
    row.deleted_at = now_utc()
    db.flush()

    response = client.get(
        f"/api/v1/media/{live_media.id}/content",
        headers=auth_header(customer_token(db, customer)),
    )
    assert response.status_code == 404


def test_anonymous_cannot_stream_media(client: TestClient, live_media: RequestMedia) -> None:
    response = client.get(f"/api/v1/media/{live_media.id}/content")
    assert response.status_code in {401, 403}


def test_customer_cannot_use_staff_media_route(
    client: TestClient, db: Session, customer, live_media: RequestMedia
) -> None:
    """A customer JWT must not satisfy the staff dependency."""
    response = client.get(
        f"/api/v1/media/staff/request-media/{live_media.id}/content",
        headers=auth_header(customer_token(db, customer)),
    )
    assert response.status_code in {401, 403}


# ----------------------------------------------------------- path safety


def test_media_response_never_leaks_storage_path(
    client: TestClient, staff_headers, live_media: RequestMedia
) -> None:
    """The stored path carries customer/request UUIDs and must stay internal."""
    response = client.get(
        f"/api/v1/media/staff/request-media/{live_media.id}/content",
        headers=staff_headers,
    )
    assert response.status_code == 200
    body = response.content
    assert live_media.storage_path.encode() not in body
    assert str(live_media.request_id).encode() not in body


# ------------------------------------------------------ chat attachments


@pytest.fixture()
def chat_attachment(db: Session, customer):
    """A chat attachment in a conversation owned by ``customer``.

    Built through the ORM because no endpoint uploads chat attachments yet;
    what is under test is the read authorisation, not the upload.
    ``message_attachments`` has no customer_id or conversation_id, so the
    fixture threads ownership through a real message.
    """
    from app.db.models import Conversation, Message, MessageAttachment
    from app.services.media_service import (
        build_conversation_attachment_path,
        make_storage_client,
    )

    conversation = Conversation(customer_id=customer.id, subject="استفسار", is_open=True)
    db.add(conversation)
    db.flush()

    message = Message(
        conversation_id=conversation.id,
        sender_type="CUSTOMER",
        body="مرفق",
        sent_at=now_utc(),
    )
    db.add(message)
    db.flush()

    attachment_id = uuid.uuid4()
    path = build_conversation_attachment_path(
        customer_id=customer.id,
        conversation_id=conversation.id,
        extension=".png",
        attachment_id=attachment_id,
    )
    make_storage_client().write(path, CONTENT)

    attachment = MessageAttachment(
        id=attachment_id,
        message_id=message.id,
        storage_path=path,
        mime_type="image/png",
        size_bytes=len(CONTENT),
        checksum_sha256="0" * 64,
        kind="IMAGE",
    )
    db.add(attachment)
    db.flush()
    return attachment


def test_customer_streams_own_chat_attachment(
    client: TestClient, db: Session, customer, chat_attachment
) -> None:
    response = client.get(
        f"/api/v1/media/message-attachments/{chat_attachment.id}/content",
        headers=auth_header(customer_token(db, customer)),
    )
    assert response.status_code == 200, response.text
    assert response.content == CONTENT


def test_customer_cannot_stream_another_customers_chat_attachment(
    client: TestClient, db: Session, other_customer, chat_attachment
) -> None:
    """IDOR guard on the chat route: ownership comes from the conversation."""
    response = client.get(
        f"/api/v1/media/message-attachments/{chat_attachment.id}/content",
        headers=auth_header(customer_token(db, other_customer)),
    )
    assert response.status_code == 404, response.text
    assert response.json()["code"] == "NOT_FOUND"


def test_anonymous_cannot_stream_chat_attachment(
    client: TestClient, chat_attachment
) -> None:
    response = client.get(f"/api/v1/media/message-attachments/{chat_attachment.id}/content")
    assert response.status_code in {401, 403}


def test_staff_streams_chat_attachment_without_a_soft_delete_column(
    client: TestClient, staff_headers, chat_attachment
) -> None:
    """Regression: this route used to read ``attachment.deleted_at``, a column
    message_attachments does not have, so every call raised a 500."""
    response = client.get(
        f"/api/v1/media/staff/message-attachments/{chat_attachment.id}/content",
        headers=staff_headers,
    )
    assert response.status_code == 200, response.text
    assert response.content == CONTENT


def test_customer_cannot_use_staff_chat_attachment_route(
    client: TestClient, db: Session, customer, chat_attachment
) -> None:
    response = client.get(
        f"/api/v1/media/staff/message-attachments/{chat_attachment.id}/content",
        headers=auth_header(customer_token(db, customer)),
    )
    assert response.status_code in {401, 403}


def test_message_list_returns_authorised_urls_not_storage_paths(
    client: TestClient, db: Session, customer, chat_attachment
) -> None:
    """``attachment_urls`` must never carry the internal bucket path."""
    headers = auth_header(customer_token(db, customer))
    conversation_id = chat_attachment.message.conversation_id

    listed = client.get(
        f"/api/v1/conversations/{conversation_id}/messages", headers=headers
    )
    assert listed.status_code == 200, listed.text
    urls = [url for m in listed.json() for url in m["attachment_urls"]]
    assert urls, "the attached message should expose its attachment"
    assert chat_attachment.storage_path not in listed.text
    assert "chat-media" not in listed.text
    # Instead: an authorised API route the client calls with its own JWT.
    assert urls == [
        f"/api/v1/media/message-attachments/{chat_attachment.id}/content"
    ]