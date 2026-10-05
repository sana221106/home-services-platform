"""Regressions for the support and staff-auth defects found in review.

Each test fails against the original code. They share one failure mode: attributes
and constructor kwargs the ORM models do not declare, so the call raised
``AttributeError``/``TypeError``, or silently created a dead attribute that was
never persisted.

  * ``Message`` has no ``is_read``; read state is ``read_at``.
  * ``Conversation`` has no ``closed_at``; closing is ``is_open``.
  * ``SupportCallLog`` names the agent FK ``agent_id`` and requires ``called_at``.
  * ``Review`` stores ``image_storage_path``, not ``has_image``.
  * ``AuthenticatedStaff.staff`` is the ``StaffUser``: ``staff.staff.id`` is the id,
    and ``StaffUser`` has no ``email`` column.
  * ``StaffRole`` is the enum; the mapped table is ``Role``.
"""

from __future__ import annotations

import uuid

import pytest
from sqlalchemy.orm import Session

from app.core.exceptions import NotFoundError, ValidationError
from app.db.models import Message, Review, StaffUser, SupportCallLog
from app.db.models.identity import Role
from app.services import auth_service, support_service
from app.utils.time import now_utc

pytestmark = pytest.mark.filterwarnings("ignore::DeprecationWarning")


# ------------------------------------------------------------------- chat


def test_mark_conversation_read_persists_read_at(
    db: Session, customer
) -> None:
    """mark_conversation_read must actually persist read state.

    It set ``message.is_read = True`` on a model with no such column, so the value
    lived only in the instance dict and never reached the database.
    """
    from app.db.models import Conversation

    conv = Conversation(customer_id=customer.id, subject="موضوع", is_open=True)
    db.add(conv)
    db.flush()
    message = Message(
        conversation_id=conv.id,
        sender_type="staff",
        sender_id=uuid.uuid4(),
        body="رد",
        sent_at=now_utc(),
    )
    db.add(message)
    db.flush()
    assert message.read_at is None

    support_service.mark_conversation_read(
        db, conversation=conv, customer_id=customer.id
    )
    db.commit()

    db.expire(message)
    assert message.read_at is not None, "read_at was never persisted"


def test_close_conversation_persists_without_closed_at(
    db: Session, customer
) -> None:
    """Closing must survive a reload.

    It assigned ``conversation.closed_at``, which does not exist, so the timestamp
    was discarded on commit.
    """
    from app.db.models import Conversation

    conv = Conversation(customer_id=customer.id, subject="م", is_open=True)
    db.add(conv)
    db.flush()

    support_service.close_conversation(db, conversation=conv, customer_id=customer.id)
    db.commit()
    db.expire(conv)

    assert conv.is_open is False
    assert "closed_at" not in Conversation.__table__.columns


def test_mark_conversation_read_rejects_other_customers(
    db: Session, customer, other_customer
) -> None:
    from app.db.models import Conversation

    conv = Conversation(customer_id=customer.id, subject="x", is_open=True)
    db.add(conv)
    db.flush()
    with pytest.raises((NotFoundError, ValidationError)):
        support_service.mark_conversation_read(
            db, conversation=conv, customer_id=other_customer.id
        )


# --------------------------------------------------------------- call logs


def test_log_call_records_the_agent(db: Session, customer, service_request) -> None:
    """log_call must persist with the real column name.

    ``SupportCallLog(staff_id=...)`` raised TypeError, and leaving ``called_at``
    unset raised IntegrityError, so the call-centre log was never writable.
    """
    agent_id = uuid.uuid4()
    call = support_service.log_call(
        db,
        customer_id=customer.id,
        request_id=service_request.id,
        staff_id=agent_id,
        direction="OUTBOUND",
        outcome="RESOLVED",
        duration_seconds=120,
        notes="تم الاتصال",
    )
    db.commit()

    db.expire(call)
    assert call.agent_id == agent_id
    assert call.customer_id == customer.id
    assert call.direction == "OUTBOUND"
    assert call.called_at is not None


def test_support_call_log_column_names() -> None:
    """Guards the rename: staff_id must not creep back in."""
    assert "agent_id" in SupportCallLog.__table__.columns
    assert "staff_id" not in SupportCallLog.__table__.columns


# ----------------------------------------------------------------- reviews


def test_create_review_succeeds(db: Session, customer, service_request) -> None:
    """A paid request must be ratable.

    ``Review(has_image=...)`` raised TypeError, so creating any review 500'd.
    """
    service_request.status = "PAID"
    db.flush()

    review = support_service.create_review(
        db,
        customer_id=customer.id,
        request_id=service_request.id,
        rating=5,
        text="ممتاز",
        has_image=False,
    )
    db.commit()

    assert review.id is not None
    assert review.rating == 5
    assert review.publication_status.value == "PENDING"


def test_re_rating_updates_instead_of_duplicating(
    db: Session, customer, service_request
) -> None:
    """§69 requires idempotency per request."""
    service_request.status = "PAID"
    db.flush()

    first = support_service.create_review(
        db, customer_id=customer.id, request_id=service_request.id,
        rating=4, text="جيد", has_image=False,
    )
    second = support_service.create_review(
        db, customer_id=customer.id, request_id=service_request.id,
        rating=5, text="ممتاز", has_image=False,
    )
    db.commit()

    assert first.id == second.id, "a second review row was created"
    assert second.rating == 5
    assert second.text == "ممتاز"


def test_review_column_names() -> None:
    assert "image_storage_path" in Review.__table__.columns
    assert "has_image" not in Review.__table__.columns


def test_cannot_rate_someone_elses_request(
    db: Session, customer, other_customer, service_request
) -> None:
    service_request.status = "PAID"
    db.flush()
    with pytest.raises(NotFoundError):
        support_service.create_review(
            db, customer_id=other_customer.id, request_id=service_request.id,
            rating=5, text=None, has_image=False,
        )


def test_cannot_rate_an_unfinished_request(
    db: Session, customer, service_request
) -> None:
    service_request.status = "UNDER_REVIEW"
    db.flush()
    with pytest.raises(ValidationError):
        support_service.create_review(
            db, customer_id=customer.id, request_id=service_request.id,
            rating=5, text=None, has_image=False,
        )


# -------------------------------------------------------------- staff auth


def test_staff_role_enum_is_not_the_mapped_table() -> None:
    """``select(StaffRole)`` built an unresolvable FROM clause.

    The endpoint imported the enum re-exported from models.identity; the mapped
    class is Role.
    """
    from app.core.enums import StaffRole
    from app.db.models import identity

    assert identity.StaffRole is StaffRole
    assert not hasattr(StaffRole, "__table__")
    assert hasattr(Role, "__table__")


def test_staff_me_endpoint_returns_200(client, db, super_admin_staff) -> None:
    """GET /staff/auth/me must succeed.

    It selected the enum instead of the Role table and read a nonexistent
    StaffUser.email, so this 500'd for every staff user.
    """
    from tests.conftest import grant_all_permissions, staff_token

    grant_all_permissions(db, super_admin_staff)
    db.commit()

    resp = client.get(
        "/api/v1/staff/auth/me",
        headers={"Authorization": f"Bearer {staff_token(db, super_admin_staff)}"},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["staff_id"]
    assert body["full_name"]
    assert "SUPER_ADMIN" in body["roles"]
    assert body["permissions"]
    assert body["email"]


def test_staff_login_mints_a_token_with_the_right_staff_claim(
    client, db, super_admin_staff
) -> None:
    """authenticate_staff used ``staff.staff.id`` on a StaffUser instance."""
    from app.core.security import token_service
    from app.db.models import User

    user = db.query(User).filter(User.id == super_admin_staff.user_id).one()
    user.phone = "+20111119999"
    db.commit()

    resp = client.post(
        "/api/v1/staff/auth/login",
        json={"email": "+20111119999", "password": "ChangeMe!2024"},
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["access_token"]
    assert resp.json()["refresh_token"]

    claims = token_service.decode(resp.json()["access_token"], expected_type="access")
    assert claims.staff_id == str(super_admin_staff.id)


def test_staff_email_helper_is_column_safe() -> None:
    """``staff.staff.email`` raised AttributeError; the helper is column-safe."""
    import inspect

    assert "email" not in StaffUser.__table__.columns
    source = inspect.getsource(auth_service.staff_email)
    assert "employee_code" in source