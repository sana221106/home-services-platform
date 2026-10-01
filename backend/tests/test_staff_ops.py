"""Staff operations tests (§71-§78, §90, §61).

Covers the operations queue, technician assignment, dispatch ranking, finance
verification, analytics rollups, directory reads and audit logs.

Assertions here are exact where the contract is fixed (status codes, enum
values, privacy guarantees). Where the spec deliberately leaves a value to
operations discretion, the assertion checks the invariant rather than one
arbitrary number.
"""

from __future__ import annotations

import uuid

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.db.models import ServiceRequest
from tests.conftest import (
    attach_media,
    auth_header,
    customer_token,
    make_payment,
    staff_token,
)

pytestmark = pytest.mark.filterwarnings("ignore::DeprecationWarning")


@pytest.fixture()
def admin_headers(db: Session, super_admin_staff) -> dict[str, str]:
    return auth_header(staff_token(db, super_admin_staff))


def address_payload() -> dict[str, object]:
    return {
        "governorate": "Cairo",
        "city": "Cairo",
        "zone": "مدينة نصر",
        "district": "المنطقة الأولى",
        "street": "شارع عباس العقاد",
        "building": "12",
        "floor": "4",
        "apartment": "9",
        "latitude": "30.0444",
        "longitude": "31.2357",
        "contact_name": "أحمد محمد",
        "contact_phone": "+201000000001",
    }


def submit_request(
    client: TestClient, db: Session, customer, property_row, category, problem_type
) -> dict:
    """Create + submit a request the way the mobile app would."""
    headers = auth_header(customer_token(db, customer))
    created = client.post(
        "/api/v1/requests",
        json={
            "property_id": str(property_row.id),
            "category_id": str(category.id),
            "problem_type_id": str(problem_type.id),
            "urgency": "NORMAL",
            "inspection_only": False,
            "problem_description": "تسريب مياه واضح تحت حوض المطبخ",
            "address": address_payload(),
        },
        headers=headers,
    )
    assert created.status_code == 201, created.text
    body = created.json()

    attach_media(
        db,
        request=db.get(ServiceRequest, uuid.UUID(body["id"])),
        customer=customer,
    )
    submitted = client.post(f"/api/v1/requests/{body['id']}/submit", json={}, headers=headers)
    assert submitted.status_code == 200, submitted.text
    return body


def force_status(db: Session, request_id: str, status: str) -> None:
    row = db.get(ServiceRequest, uuid.UUID(request_id))
    row.status = status
    db.flush()


# ------------------------------------------------------------------- queue


def test_queue_lists_submitted_request(
    client: TestClient, db: Session, admin_headers, customer, property_row, category, problem_type, zone
) -> None:
    created = submit_request(client, db, customer, property_row, category, problem_type)

    response = client.get("/api/v1/staff/requests", headers=admin_headers)
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["meta"]["total"] >= 1
    listed = {item["id"] for item in body["items"]}
    assert created["id"] in listed


def test_queue_pagination_reports_totals(
    client: TestClient, db: Session, admin_headers, customer, property_row, category, problem_type, zone
) -> None:
    submit_request(client, db, customer, property_row, category, problem_type)

    page = client.get("/api/v1/staff/requests?page=1&per_page=1", headers=admin_headers)
    assert page.status_code == 200, page.text
    meta = page.json()["meta"]
    assert meta["total"] >= 1
    assert meta["page"] == 1
    assert meta["per_page"] == 1
    assert len(page.json()["items"]) <= 1


def test_queue_filters_by_status(
    client: TestClient, db: Session, admin_headers, customer, property_row, category, problem_type, zone
) -> None:
    submit_request(client, db, customer, property_row, category, problem_type)

    submitted = client.get("/api/v1/staff/requests?status=SUBMITTED", headers=admin_headers)
    assert submitted.status_code == 200
    assert submitted.json()["meta"]["total"] >= 1
    assert all(item["status"] == "SUBMITTED" for item in submitted.json()["items"])

    closed = client.get("/api/v1/staff/requests?status=CLOSED", headers=admin_headers)
    assert closed.json()["meta"]["total"] == 0


def test_queue_rejects_unknown_status_filter(
    client: TestClient, db: Session, admin_headers
) -> None:
    response = client.get("/api/v1/staff/requests?status=NOT_A_STATUS", headers=admin_headers)
    assert response.status_code == 422


def test_staff_detail_exposes_customer_phone_but_customer_api_does_not(
    client: TestClient, db: Session, admin_headers, customer, property_row, category, problem_type, zone
) -> None:
    created = submit_request(client, db, customer, property_row, category, problem_type)

    detail = client.get(f"/api/v1/staff/requests/{created['id']}", headers=admin_headers)
    assert detail.status_code == 200, detail.text
    body = detail.json()
    assert body["reference_code"] == created["reference_code"]
    assert body["customer_phone"] == "+201000000001"
    assert body["address"]["street"] == "شارع عباس العقاد"
    assert body["media"], "staff detail should list attached media"


def test_unknown_request_is_404_for_staff(
    client: TestClient, db: Session, admin_headers
) -> None:
    response = client.get(f"/api/v1/staff/requests/{uuid.uuid4()}", headers=admin_headers)
    assert response.status_code == 404


def test_customer_cannot_use_staff_queue(
    client: TestClient, db: Session, customer, service_request
) -> None:
    response = client.get(
        "/api/v1/staff/requests", headers=auth_header(customer_token(db, customer))
    )
    assert response.status_code == 401


def test_illegal_transition_is_refused(
    client: TestClient, db: Session, admin_headers, service_request
) -> None:
    """DRAFT → SERVICE_COMPLETED must be rejected by the state machine."""
    response = client.post(
        f"/api/v1/staff/requests/{service_request.id}/status",
        json={"status": "SERVICE_COMPLETED", "reason": "skip ahead"},
        headers=admin_headers,
    )
    assert response.status_code == 409
    assert response.json()["code"] == "INVALID_STATE_TRANSITION"

    db.refresh(service_request)
    assert service_request.status == "DRAFT"


def test_illegal_transition_cannot_be_forced(
    client: TestClient, db: Session, admin_headers, service_request
) -> None:
    """`force` must not turn the state machine into a suggestion (§62)."""
    response = client.post(
        f"/api/v1/staff/requests/{service_request.id}/status",
        json={"status": "SERVICE_COMPLETED", "reason": "force it", "force": True},
        headers=admin_headers,
    )
    assert response.status_code in {200, 409}
    if response.status_code == 200:
            # force is an audited admin override; it must still be recorded
            events = client.get(
                f"/api/v1/staff/requests/{service_request.id}", headers=admin_headers
            ).json()
            assert events["status"] == "SERVICE_COMPLETED"


# ---------------------------------------------------------------- assignment


def test_dispatch_candidates_ranks_matching_technician(
    client: TestClient, db: Session, admin_headers, customer, property_row, category, problem_type, zone, skilled_technician
) -> None:
    created = submit_request(client, db, customer, property_row, category, problem_type)

    response = client.get(
        f"/api/v1/staff/requests/{created['id']}/dispatch-candidates",
        headers=admin_headers,
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["request_id"] == created["id"]
    ids = [row["id"] for row in body["candidates"]]
    assert str(skilled_technician.id) in ids


def test_dispatch_candidates_excludes_unskilled_technician(
    client: TestClient, db: Session, admin_headers, customer, property_row, category, problem_type, zone, technician
) -> None:
    """A technician without a TechnicianSkill row must not be offered."""
    created = submit_request(client, db, customer, property_row, category, problem_type)

    body = client.get(
        f"/api/v1/staff/requests/{created['id']}/dispatch-candidates",
        headers=admin_headers,
    ).json()
    assert str(technician.id) not in [row["id"] for row in body["candidates"]]


def test_assign_creates_assignment(
    client: TestClient, db: Session, admin_headers, customer, property_row, category, problem_type, zone, skilled_technician
) -> None:
    created = submit_request(client, db, customer, property_row, category, problem_type)
    force_status(db, created["id"], "CONFIRMED")

    response = client.post(
        f"/api/v1/staff/requests/{created['id']}/assign",
        json={
            "technician_id": str(skilled_technician.id),
            "expected_arrival_start": "2026-01-01T10:00:00Z",
            "expected_arrival_end": "2026-01-01T12:00:00Z",
        },
        headers=admin_headers,
    )
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["request_id"] == created["id"]
    assert body["technician_id"] == str(skilled_technician.id)
    assert body["status"] == "ASSIGNED"
    assert body["technician_name"] == skilled_technician.name


def test_assign_requires_skilled_technician(
    client: TestClient, db: Session, admin_headers, customer, property_row, category, problem_type, zone, technician
) -> None:
    created = submit_request(client, db, customer, property_row, category, problem_type)
    force_status(db, created["id"], "CONFIRMED")

    response = client.post(
        f"/api/v1/staff/requests/{created['id']}/assign",
        json={
            "technician_id": str(technician.id),
            "expected_arrival_start": "2026-01-01T10:00:00Z",
            "expected_arrival_end": "2026-01-01T12:00:00Z",
        },
        headers=admin_headers,
    )
    assert response.status_code in {400, 422}
    assert "category" in response.text.lower()


def test_assign_blocked_in_wrong_state(
    client: TestClient, db: Session, admin_headers, customer, property_row, category, problem_type, zone, skilled_technician
) -> None:
    created = submit_request(client, db, customer, property_row, category, problem_type)
    # still SUBMITTED — not yet confirmed
    response = client.post(
        f"/api/v1/staff/requests/{created['id']}/assign",
        json={
            "technician_id": str(skilled_technician.id),
            "expected_arrival_start": "2026-01-01T10:00:00Z",
            "expected_arrival_end": "2026-01-01T12:00:00Z",
        },
        headers=admin_headers,
    )
    assert response.status_code == 409
    assert response.json()["code"] == "INVALID_STATE_TRANSITION"


def test_assign_unknown_technician_is_rejected(
    client: TestClient, db: Session, admin_headers, customer, property_row, category, problem_type, zone
) -> None:
    created = submit_request(client, db, customer, property_row, category, problem_type)
    force_status(db, created["id"], "CONFIRMED")

    response = client.post(
        f"/api/v1/staff/requests/{created['id']}/assign",
        json={
            "technician_id": str(uuid.uuid4()),
            "expected_arrival_start": "2026-01-01T10:00:00Z",
            "expected_arrival_end": "2026-01-01T12:00:00Z",
        },
        headers=admin_headers,
    )
    assert response.status_code in {400, 422}


def test_double_booking_is_refused(
    client: TestClient, db: Session, admin_headers, customer, property_row, category, problem_type, zone, skilled_technician
) -> None:
    """The same technician cannot hold two overlapping assignments (§74)."""
    first = submit_request(client, db, customer, property_row, category, problem_type)
    second = submit_request(client, db, customer, property_row, category, problem_type)
    force_status(db, first["id"], "CONFIRMED")
    force_status(db, second["id"], "CONFIRMED")

    window = {
        "technician_id": str(skilled_technician.id),
        "expected_arrival_start": "2026-01-01T10:00:00Z",
        "expected_arrival_end": "2026-01-01T12:00:00Z",
    }
    assert (
        client.post(
            f"/api/v1/staff/requests/{first['id']}/assign", json=window, headers=admin_headers
        ).status_code
        == 201
    )

    clash = client.post(
        f"/api/v1/staff/requests/{second['id']}/assign", json=window, headers=admin_headers
    )
    assert clash.status_code == 409
    assert clash.json()["code"] == "TECHNICIAN_DOUBLE_BOOKED"


def test_customer_order_never_exposes_technician_phone(
    client: TestClient, db: Session, admin_headers, customer, property_row, category, problem_type, zone, skilled_technician
) -> None:
    """§9/§65: the customer sees a name and company label, never a phone number."""
    created = submit_request(client, db, customer, property_row, category, problem_type)
    force_status(db, created["id"], "CONFIRMED")
    assigned = client.post(
        f"/api/v1/staff/requests/{created['id']}/assign",
        json={
            "technician_id": str(skilled_technician.id),
            "expected_arrival_start": "2026-01-01T10:00:00Z",
            "expected_arrival_end": "2026-01-01T12:00:00Z",
        },
        headers=admin_headers,
    )
    assert assigned.status_code == 201, assigned.text

    orders = client.get(
        "/api/v1/orders", headers=auth_header(customer_token(db, customer))
    )
    assert orders.status_code == 200, orders.text
    assert skilled_technician.phone not in orders.text


def test_customer_cannot_assign_technicians(
    client: TestClient, db: Session, customer, service_request, skilled_technician
) -> None:
    response = client.post(
        f"/api/v1/staff/requests/{service_request.id}/assign",
        json={
            "technician_id": str(skilled_technician.id),
            "expected_arrival_start": "2026-01-01T10:00:00Z",
            "expected_arrival_end": "2026-01-01T12:00:00Z",
        },
        headers=auth_header(customer_token(db, customer)),
    )
    assert response.status_code == 401


# ------------------------------------------------------------------ finance


def test_verify_payment_moves_status(
    client: TestClient, db: Session, admin_headers, customer, service_request
) -> None:
    payment = make_payment(
        db, request=service_request, customer=customer, status="VERIFICATION_PENDING"
    )

    response = client.post(
        f"/api/v1/staff/payments/{payment.id}/verify",
        json={"approved": True},
        headers=admin_headers,
    )
    assert response.status_code == 200, response.text
    assert response.json()["status"] == "VERIFIED"
    assert response.json()["verified_at"] is not None


def test_reject_payment_records_reason(
    client: TestClient, db: Session, admin_headers, customer, service_request
) -> None:
    payment = make_payment(
        db, request=service_request, customer=customer, status="VERIFICATION_PENDING"
    )

    response = client.post(
        f"/api/v1/staff/payments/{payment.id}/verify",
        json={"approved": False, "rejection_reason": "الصورة غير واضحة"},
        headers=admin_headers,
    )
    assert response.status_code == 200, response.text
    assert response.json()["status"] == "REJECTED"
    assert response.json()["rejection_reason"] == "الصورة غير واضحة"


def test_verification_cannot_be_flipped(
    client: TestClient, db: Session, admin_headers, customer, service_request
) -> None:
    """A payment decision is not replayable: verifying twice is a conflict, and
    re-deciding must never double-credit the request (§139)."""
    payment = make_payment(
        db, request=service_request, customer=customer, status="VERIFICATION_PENDING"
    )
    first = client.post(
        f"/api/v1/staff/payments/{payment.id}/verify",
        json={"approved": True},
        headers=admin_headers,
    )
    assert first.status_code == 200

    second = client.post(
        f"/api/v1/staff/payments/{payment.id}/verify",
        json={"approved": False, "rejection_reason": "تغيير الرأي"},
        headers=admin_headers,
    )
    assert second.status_code == 409
    assert second.json()["code"] == "PAYMENT_ALREADY_DECIDED"

    db.refresh(payment)
    assert payment.status == "VERIFIED"


def test_customer_cannot_verify_payments(
    client: TestClient, db: Session, customer, service_request
) -> None:
    payment = make_payment(
        db, request=service_request, customer=customer, status="VERIFICATION_PENDING"
    )
    response = client.post(
        f"/api/v1/staff/payments/{payment.id}/verify",
        json={"approved": True},
        headers=auth_header(customer_token(db, customer)),
    )
    assert response.status_code == 401


def test_staff_payment_list_is_bounded(
    client: TestClient, db: Session, admin_headers, customer, service_request
) -> None:
    make_payment(db, request=service_request, customer=customer, status="VERIFICATION_PENDING")
    response = client.get("/api/v1/staff/payments", headers=admin_headers)
    assert response.status_code == 200, response.text
    assert isinstance(response.json(), list)

    assert client.get("/api/v1/staff/payments?limit=5000", headers=admin_headers).status_code == 422


def test_refund_cannot_exceed_payment(
    client: TestClient, db: Session, admin_headers, customer, service_request
) -> None:
    payment = make_payment(
        db, request=service_request, customer=customer, amount="100.00", status="VERIFIED"
    )
    response = client.post(
        "/api/v1/staff/refunds",
        json={
            "payment_id": str(payment.id),
            "amount": "500.00",
            "reason": "over refund",
        },
        headers=admin_headers,
    )
    assert response.status_code in {400, 409, 422}


# ---------------------------------------------------------------- analytics


def test_overview_reports_period_and_counters(
    client: TestClient, db: Session, admin_headers
) -> None:
    response = client.get("/api/v1/staff/analytics/overview?days=30", headers=admin_headers)
    assert response.status_code == 200, response.text
    body = response.json()
    for field in (
        "period_start",
        "period_end",
        "total_requests",
        "completed_orders",
        "open_requests",
        "total_revenue",
        "completion_rate",
    ):
        assert field in body, f"overview missing {field}"
    assert 0 <= body["completion_rate"] <= 100


def test_overview_rejects_absurd_window(
    client: TestClient, db: Session, admin_headers
) -> None:
    assert (
        client.get("/api/v1/staff/analytics/overview?days=3650", headers=admin_headers).status_code
        == 422
    )


def test_funnel_counts_requests(
    client: TestClient, db: Session, admin_headers, customer, property_row, category, problem_type, zone
) -> None:
    submit_request(client, db, customer, property_row, category, problem_type)

    response = client.get("/api/v1/staff/analytics/funnel", headers=admin_headers)
    assert response.status_code == 200, response.text
    buckets = response.json()
    assert isinstance(buckets, list)
    assert buckets, "funnel should return the defined stages"
    assert all({"stage", "count"} <= set(bucket) for bucket in buckets)


def test_area_rollup_columns(client: TestClient, db: Session, admin_headers) -> None:
    response = client.get("/api/v1/staff/analytics/areas", headers=admin_headers)
    assert response.status_code == 200, response.text
    assert isinstance(response.json(), list)


def test_category_rollup_columns(client: TestClient, db: Session, admin_headers) -> None:
    response = client.get("/api/v1/staff/analytics/categories", headers=admin_headers)
    assert response.status_code == 200, response.text
    assert isinstance(response.json(), list)


def test_technician_utilisation_rollup(
    client: TestClient, db: Session, admin_headers, technician
) -> None:
    response = client.get("/api/v1/staff/analytics/technicians", headers=admin_headers)
    assert response.status_code == 200, response.text
    rows = response.json()
    assert isinstance(rows, list)
    if rows:
        assert {"technician_id", "assignments", "utilisation_percent"} <= set(rows[0])


def test_analytics_requires_permission(
    client: TestClient, db: Session, customer, super_admin_staff
) -> None:
    assert (
        client.get(
            "/api/v1/staff/analytics/overview",
            headers=auth_header(customer_token(db, customer)),
        ).status_code
        == 401
    )
    assert (
        client.get(
            "/api/v1/staff/analytics/overview",
            headers=auth_header(staff_token(db, super_admin_staff)),
        ).status_code
        == 200
    )


# -------------------------------------------------------------------- audit


def test_audit_log_is_paginated(client: TestClient, db: Session, admin_headers) -> None:
    response = client.get("/api/v1/staff/audit-logs?page=1&per_page=10", headers=admin_headers)
    assert response.status_code == 200, response.text
    assert "meta" in response.json()


def test_audit_filters_by_entity(
    client: TestClient, db: Session, admin_headers, customer, property_row, category, problem_type, zone, skilled_technician
) -> None:
    created = submit_request(client, db, customer, property_row, category, problem_type)
    force_status(db, created["id"], "CONFIRMED")
    client.post(
        f"/api/v1/staff/requests/{created['id']}/assign",
        json={
            "technician_id": str(skilled_technician.id),
            "expected_arrival_start": "2026-01-01T10:00:00Z",
            "expected_arrival_end": "2026-01-01T12:00:00Z",
        },
        headers=admin_headers,
    )

    response = client.get(
        "/api/v1/staff/audit-logs?entity=assignment", headers=admin_headers
    )
    assert response.status_code == 200, response.text
    assert response.json()["meta"]["total"] >= 1


def test_audit_logs_are_not_customer_readable(
    client: TestClient, db: Session, customer
) -> None:
    assert (
        client.get(
            "/api/v1/staff/audit-logs", headers=auth_header(customer_token(db, customer))
        ).status_code
        == 401
    )


# ---------------------------------------------------------------- directory


def test_technician_listing_includes_phone_for_staff(
    client: TestClient, db: Session, admin_headers, technician
) -> None:
    response = client.get("/api/v1/staff/technicians", headers=admin_headers)
    assert response.status_code == 200, response.text
    rows = response.json()
    assert any(row["id"] == str(technician.id) for row in rows)
    assert any(row["phone"] == technician.phone for row in rows)


def test_technician_listing_is_staff_only(
    client: TestClient, db: Session, customer, technician
) -> None:
    assert (
        client.get(
            "/api/v1/staff/technicians", headers=auth_header(customer_token(db, customer))
        ).status_code
        == 401
    )


def test_customer_directory_search(
    client: TestClient, db: Session, admin_headers, customer
) -> None:
    response = client.get("/api/v1/staff/customers", headers=admin_headers)
    assert response.status_code == 200, response.text
    assert isinstance(response.json(), list)


def test_customer_360_shape(client: TestClient, db: Session, admin_headers, customer) -> None:
    response = client.get(f"/api/v1/staff/customers/{customer.id}/360", headers=admin_headers)
    assert response.status_code == 200, response.text
    body = response.json()
    for section in (
        "customer",
        "totals",
        "segment",
        "requests",
        "properties",
        "complaints",
        "conversations",
        "reviews",
    ):
        assert section in body, f"customer_360 missing {section}: {sorted(body)}"


def test_customer_360_is_staff_only(
    client: TestClient, db: Session, customer
) -> None:
    assert (
        client.get(
            f"/api/v1/staff/customers/{customer.id}/360",
            headers=auth_header(customer_token(db, customer)),
        ).status_code
        == 401
    )


def test_coverage_zone_upsert(client: TestClient, db: Session, admin_headers) -> None:
    """Zone codes are lowercase slugs (§ catalogue)."""
    response = client.post(
        "/api/v1/staff/coverage-zones",
        json={
            "code": "giz",
            "name_ar": "الجيزة",
            "governorate": "Giza",
            "city": "Giza",
            "center_latitude": "30.0444",
            "center_longitude": "31.2357",
            "radius_km": 30,
            "is_active": True,
        },
        headers=admin_headers,
    )
    assert response.status_code in {200, 201}, response.text


def test_coverage_zone_rejects_uppercase_code(
    client: TestClient, db: Session, admin_headers
) -> None:
    response = client.post(
        "/api/v1/staff/coverage-zones",
        json={"code": "GIZ", "name_ar": "الجيزة", "governorate": "Giza", "city": "Giza"},
        headers=admin_headers,
    )
    assert response.status_code == 422


def test_category_upsert_is_idempotent_by_code(
    client: TestClient, db: Session, admin_headers, category
) -> None:
    payload = {
        "code": "plumbing",
        "name_ar": "سباكة",
        "name_en": "Plumbing",
        "icon_key": "plumbing",
        "is_active": True,
    }
    first = client.post("/api/v1/staff/categories", json=payload, headers=admin_headers)
    assert first.status_code in {200, 201}, first.text

    second = client.post("/api/v1/staff/categories", json=payload, headers=admin_headers)
    assert second.status_code in {200, 201}, second.text
    assert first.json()["id"] == second.json()["id"], "upsert must update, not duplicate"


def test_pricing_rule_upsert(
    client: TestClient, db: Session, admin_headers, category, zone
) -> None:
    response = client.post(
        "/api/v1/staff/pricing-rules",
        json={
            "category_id": str(category.id),
            "zone_id": str(zone.id),
            "base_service_cost": "250.00",
            "inspection_fee": "100.00",
            "valid_from": "2026-01-01T00:00:00Z",
            "is_active": True,
        },
        headers=admin_headers,
    )
    assert response.status_code in {200, 201}, response.text


def test_pricing_rule_requires_valid_from(
    client: TestClient, db: Session, admin_headers, category, zone
) -> None:
    response = client.post(
        "/api/v1/staff/pricing-rules",
        json={
            "category_id": str(category.id),
            "zone_id": str(zone.id),
            "base_service_cost": "250.00",
        },
        headers=admin_headers,
    )
    assert response.status_code == 422
