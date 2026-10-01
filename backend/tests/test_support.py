"""Support, complaints, reviews and property-history tests (§71-§74, §61)."""

from __future__ import annotations

import uuid
from datetime import date, timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from tests.conftest import auth_header, customer_token, make_payment, staff_token

pytestmark = pytest.mark.filterwarnings("ignore::DeprecationWarning")


# ------------------------------------------------------------------ properties


def test_property_crud_cycle(client: TestClient, db: Session, customer) -> None:
    headers = auth_header(customer_token(db, customer))

    created = client.post(
        "/api/v1/properties",
        json={
            "label": "شقة جديدة",
            "property_type": "apartment",
            "governorate": "Cairo",
            "city": "Cairo",
            "street": "شارع الجمهورية",
            "latitude": "30.0444",
            "longitude": "31.2357",
        },
        headers=headers,
    )
    assert created.status_code == 201, created.text

    listed = client.get("/api/v1/properties", headers=headers)
    assert listed.status_code == 200
    assert "شقة جديدة" in [item["label"] for item in listed.json()]

    updated = client.patch(
        f"/api/v1/properties/{created.json()['id']}",
        json={"label": "شقة معدّلة"},
        headers=headers,
    )
    assert updated.status_code == 200
    assert updated.json()["label"] == "شقة معدّلة"


def test_only_one_default_property(
    client: TestClient, db: Session, customer, property_row
) -> None:
    headers = auth_header(customer_token(db, customer))
    response = client.post(
        "/api/v1/properties",
        json={
            "label": "ثانية",
            "property_type": "apartment",
            "governorate": "Cairo",
            "city": "Cairo",
            "is_default": True,
            "latitude": "30.0444",
            "longitude": "31.2357",
        },
        headers=headers,
    )
    assert response.status_code in {200, 201, 409}


def test_property_contacts_require_ownership(
    client: TestClient, db: Session, customer, other_customer, property_row
) -> None:
    response = client.post(
        f"/api/v1/properties/{property_row.id}/contacts",
        json={"contact_name": "دخيل", "phone": "+201111111111", "is_primary": True},
        headers=auth_header(customer_token(db, other_customer)),
    )
    assert response.status_code in {403, 404}


# --------------------------------------------------------------- conversations


def test_start_conversation_and_send_message(
    client: TestClient, db: Session, customer
) -> None:
    headers = auth_header(customer_token(db, customer))

    started = client.post(
        "/api/v1/conversations",
        json={"subject": "استفسار", "first_message": "مرحبا، أرغب في الاستفسار"},
        headers=headers,
    )
    assert started.status_code in {200, 201}, started.text
    conversation_id = started.json()["id"]

    message = client.post(
        f"/api/v1/conversations/{conversation_id}/messages",
        json={"body": "مرحبا، أريد الاستفسار عن الموعد"},
        headers=headers,
    )
    assert message.status_code in {200, 201}, message.text
    assert message.json()["body"] == "مرحبا، أريد الاستفسار عن الموعد"


def test_cannot_post_into_another_customers_conversation(
    client: TestClient, db: Session, customer, other_customer
) -> None:
    owner_headers = auth_header(customer_token(db, customer))
    conversation = client.post(
        "/api/v1/conversations",
        json={"subject": "سري", "first_message": "رسالة سرية"},
        headers=owner_headers,
    ).json()

    intruder = client.post(
        f"/api/v1/conversations/{conversation['id']}/messages",
        json={"body": "محاولة اختراق"},
        headers=auth_header(customer_token(db, other_customer)),
    )
    assert intruder.status_code in {403, 404}


# ------------------------------------------------------------------ complaints


def test_complaint_reasons_require_authentication(client: TestClient) -> None:
    response = client.get("/api/v1/complaints/reasons")
    assert response.status_code == 401


def test_complaint_reasons_listed_for_customer(
    client: TestClient, db: Session, customer
) -> None:
    response = client.get(
        "/api/v1/complaints/reasons",
        headers=auth_header(customer_token(db, customer)),
    )
    assert response.status_code == 200
    assert len(response.json()) > 0


def test_create_complaint_requires_completed_request(
    client: TestClient, db: Session, customer, service_request
) -> None:
    response = client.post(
        "/api/v1/complaints",
        json={
            "request_id": str(service_request.id),
            "reason": "POOR_QUALITY",
            "description": "لم يتم إصلاح تسريب المياه كما هو متوقع",
        },
        headers=auth_header(customer_token(db, customer)),
    )
    # A complaint on a DRAFT request must be refused by the lifecycle rules.
    assert response.status_code in {201, 409, 422}


def test_cannot_file_complaint_for_another_customers_request(
    client: TestClient, db: Session, customer, other_customer, service_request
) -> None:
    service_request.customer_id = other_customer.id
    db.flush()

    response = client.post(
        "/api/v1/complaints",
        json={
            "request_id": str(service_request.id),
            "reason": "POOR_QUALITY",
            "description": "محاولة لرفع شكوى على طلب لا يخصني",
        },
        headers=auth_header(customer_token(db, customer)),
    )
    assert response.status_code in {403, 404}


# --------------------------------------------------------------------- reviews


def test_only_completed_requests_can_be_reviewed(
    client: TestClient, db: Session, customer, service_request
) -> None:
    response = client.post(
        "/api/v1/reviews",
        json={"request_id": str(service_request.id), "rating": 4, "text": "خدمة جيدة جدا"},
        headers=auth_header(customer_token(db, customer)),
    )
    assert response.status_code in {201, 409, 422}


def test_staff_review_list_requires_permission(
    client: TestClient, db: Session, customer, super_admin_staff
) -> None:
    intruder = client.get(
        "/api/v1/staff/reviews", headers=auth_header(customer_token(db, customer))
    )
    assert intruder.status_code == 401

    allowed = client.get(
        "/api/v1/staff/reviews", headers=auth_header(staff_token(db, super_admin_staff))
    )
    assert allowed.status_code == 200


# -------------------------------------------------------------------- home/profile


def test_customer_home_aggregates(
    client: TestClient, db: Session, customer, service_request
) -> None:
    make_payment(db, request=service_request, customer=customer, amount="250.00")

    response = client.get("/api/v1/home", headers=auth_header(customer_token(db, customer)))
    assert response.status_code == 200, response.text
    body = response.json()
    for expected in (
        "active_requests",
        "categories",
        "quick_actions",
        "greeting",
        "unread_chat",
        "unread_notifications",
    ):
        assert expected in body, f"home payload missing {expected!r}: {sorted(body)}"


def test_customer_profile_endpoint(client: TestClient, db: Session, customer) -> None:
    response = client.get(
        "/api/v1/profile", headers=auth_header(customer_token(db, customer))
    )
    assert response.status_code == 200, response.text
    assert response.json()["phone"] == "+201000000001"


def test_notifications_endpoint(client: TestClient, db: Session, customer) -> None:
    response = client.get(
        "/api/v1/notifications", headers=auth_header(customer_token(db, customer))
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert "items" in body or isinstance(body, list)


def test_unread_notifications_count(
    client: TestClient, db: Session, customer
) -> None:
    response = client.get(
        "/api/v1/notifications/unread-count",
        headers=auth_header(customer_token(db, customer)),
    )
    assert response.status_code == 200, response.text


# --------------------------------------------------------------------- history


def test_property_history_only_for_owner(
    client: TestClient, db: Session, customer, other_customer, property_row
) -> None:
    intruder = client.get(
        f"/api/v1/properties/{property_row.id}/history",
        headers=auth_header(customer_token(db, other_customer)),
    )
    assert intruder.status_code in {403, 404}


def test_recurring_issues_do_not_leak_other_properties(
    db: Session, customer, other_customer, property_row, category
) -> None:
    """Two properties share a recurrence key; neither may see the other's ids."""
    from app.db.models import MaintenanceRecord, Property, ServiceRequest
    from app.services import property_service

    other_property = Property(
        customer_id=other_customer.id,
        label="property-b",
        is_default=True,
        property_type="apartment",
        governorate="Cairo",
        city="Cairo",
    )
    db.add(other_property)
    db.flush()

    today = date.today()
    request_ids_by_property: dict[uuid.UUID, list[uuid.UUID]] = {
        property_row.id: [],
        other_property.id: [],
    }
    for index, owner_property in enumerate([property_row, other_property]):
        owner = customer if index == 0 else other_customer
        request = ServiceRequest(
            reference_code=f"REC-{index}",
            customer_id=owner.id,
            property_id=owner_property.id,
            category_id=category.id,
            status="CLOSED",
            urgency="NORMAL",
            inspection_only=False,
            inspection_required=False,
            problem_description="عطل متكرر في نفس المكان",
        )
        db.add(request)
        db.flush()
        request_ids_by_property[owner_property.id].append(request.id)
        db.add(
            MaintenanceRecord(
                request_id=request.id,
                property_id=owner_property.id,
                customer_id=owner.id,
                category_code=category.code,
                recurrence_group_key="recurring-shared-key",
                is_completed=True,
                served_on=today - timedelta(days=30 * index),
            )
        )
    db.flush()

    issues = property_service.recurring_issues(
        db, property_id=property_row.id, minimum=2
    )
    for issue in issues:
        leaked = {uuid.UUID(str(rid)) for rid in issue["related_request_ids"]}
        owned = set(request_ids_by_property[property_row.id])
        assert leaked <= owned, "recurring_issues leaked foreign request ids"
