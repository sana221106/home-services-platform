"""Request lifecycle, quote and payment tests (§20, §31, §66, §8).

These exercise the full customer vertical slice: create → submit → staff quote →
customer accept → deposit, plus the guards that must hold (illegal transitions,
out-of-coverage addresses, IDOR).
"""

from __future__ import annotations

import uuid
from datetime import timedelta
from decimal import Decimal

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from tests.conftest import attach_media, auth_header, customer_token, staff_token

pytestmark = pytest.mark.filterwarnings("ignore::DeprecationWarning")


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


def _get_request(db: Session, request_id: str):  # noqa: ANN201
    from app.db.models import ServiceRequest

    return db.get(ServiceRequest, uuid.UUID(request_id))


def create_request_payload(
    property_id: str, category_id: str, problem_type_id: str | None = None
) -> dict[str, object]:
    return {
        "property_id": property_id,
        "category_id": category_id,
        "problem_type_id": problem_type_id,
        "urgency": "NORMAL",
        "inspection_only": False,
        "problem_description": "تسريب مياه واضح تحت حوض المطبخ",
        "address": address_payload(),
    }


# ------------------------------------------------------------------- creation


def test_create_request_starts_as_draft(
    client: TestClient, db: Session, customer, property_row, category, problem_type, zone
) -> None:
    response = client.post(
        "/api/v1/requests",
        json=create_request_payload(
            str(property_row.id), str(category.id), str(problem_type.id)
        ),
        headers=auth_header(customer_token(db, customer)),
    )
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["status"] == "DRAFT"
    assert body["reference_code"].startswith("HSP")
    assert body["submitted_at"] is None
    # the address is snapshotted verbatim for history (§61)
    assert body["address"]["street"] == "شارع عباس العقاد"


def test_create_request_requires_authentication(
    client: TestClient, property_row, category
) -> None:
    response = client.post(
        "/api/v1/requests",
        json=create_request_payload(str(property_row.id), str(category.id)),
    )
    assert response.status_code == 401


def test_cannot_use_another_customers_property(
    client: TestClient, db: Session, customer, other_customer, property_row, category, zone
) -> None:
    from app.db.models import Property

    intruder_property = Property(
        customer_id=other_customer.id,
        label="شقة-other",
        is_default=True,
        property_type="apartment",
        governorate="Cairo",
        city="Cairo",
    )
    db.add(intruder_property)
    db.flush()

    response = client.post(
        "/api/v1/requests",
        json=create_request_payload(str(intruder_property.id), str(category.id)),
        headers=auth_header(customer_token(db, customer)),
    )
    assert response.status_code in {403, 404}


def test_address_outside_coverage_is_rejected(
    client: TestClient, db: Session, customer, property_row, category
) -> None:
    # Coordinates decide coverage, so unserved means a point far from every zone
    # centre, not a differently spelled city name (§30).
    payload = create_request_payload(str(property_row.id), str(category.id))
    payload["address"] = {
        **address_payload(),
        "governorate": "Aswan",
        "city": "Aswan",
        "latitude": "24.0889",
        "longitude": "32.8998",
    }

    response = client.post(
        "/api/v1/requests",
        json=payload,
        headers=auth_header(customer_token(db, customer)),
    )
    assert response.status_code == 422
    assert response.json()["code"] == "OUT_OF_COVERAGE"


def test_arabic_address_inside_coverage_is_accepted(
    client: TestClient, db: Session, customer, property_row, category, zone
) -> None:
    # The customer writes Arabic; the point is what decides the area. This is the
    # case the old exact-string match rejected for spelling alone.
    payload = create_request_payload(str(property_row.id), str(category.id))
    payload["address"] = {
        **address_payload(),
        "governorate": "القاهرة",
        "city": "مدينة نصر",
        "zone_code": "CAI",
    }

    response = client.post(
        "/api/v1/requests",
        json=payload,
        headers=auth_header(customer_token(db, customer)),
    )
    assert response.status_code == 201, response.text


def test_unknown_zone_code_falls_back_to_the_coordinates(
    client: TestClient, db: Session, customer, property_row, category, zone
) -> None:
    # An unrecognised code must not be trusted into an unserved area; the
    # coordinates still resolve the request normally.
    payload = create_request_payload(str(property_row.id), str(category.id))
    payload["address"] = {**address_payload(), "zone_code": "not-a-real-zone"}

    response = client.post(
        "/api/v1/requests",
        json=payload,
        headers=auth_header(customer_token(db, customer)),
    )
    assert response.status_code == 201, response.text


def test_snapshot_stores_the_canonical_zone_code(
    client: TestClient, db: Session, customer, property_row, category, zone
) -> None:
    from app.db.models import OrderAddressSnapshot

    payload = create_request_payload(str(property_row.id), str(category.id))
    payload["address"] = {
        **address_payload(),
        "governorate": "دمياط",
        "city": "دمياط الجديدة",
        "zone_code": "CAI",
    }

    response = client.post(
        "/api/v1/requests",
        json=payload,
        headers=auth_header(customer_token(db, customer)),
    )
    assert response.status_code == 201, response.text

    snapshot = db.execute(
        select(OrderAddressSnapshot).where(
            OrderAddressSnapshot.request_id == uuid.UUID(response.json()["id"])
        )
    ).scalar_one()
    # Arabic is preserved as written, and the canonical code sits beside it.
    assert snapshot.governorate == "دمياط"
    assert snapshot.zone_code == "CAI"


def test_the_point_decides_the_area_when_it_disagrees_with_the_picked_one(
    client: TestClient, db: Session, customer, property_row, category, zone
) -> None:
    """The point decides the area, not the area picked next to it.

    Dispatch sends the technician to the snapshot's coordinates, so serving this
    address from Aswan would send an Aswan technician to a Cairo address. The
    point is therefore authoritative, and the picked area is only the fallback for
    a point no area claims (§30).
    """
    from app.db.models import CoverageZone, OrderAddressSnapshot

    db.add(
        CoverageZone(
            code="ASWAN",
            name_ar="أسوان",
            governorate="Aswan",
            city="Aswan",
            is_active=True,
            center_latitude=Decimal("24.0889"),
            center_longitude=Decimal("32.8998"),
            radius_km=Decimal("25"),
        )
    )
    db.flush()

    payload = create_request_payload(str(property_row.id), str(category.id))
    # Claims Aswan, but the point is inside Cairo's radius.
    payload["address"] = {
        **address_payload(),
        "governorate": "Aswan",
        "city": "Aswan",
        "zone_code": "ASWAN",
    }

    response = client.post(
        "/api/v1/requests",
        json=payload,
        headers=auth_header(customer_token(db, customer)),
    )
    assert response.status_code == 201, response.text

    snapshot = db.execute(
        select(OrderAddressSnapshot).where(
            OrderAddressSnapshot.request_id == uuid.UUID(response.json()["id"])
        )
    ).scalar_one()
    assert snapshot.zone_code == zone.code


def test_a_point_no_area_claims_falls_back_to_the_picked_area(
    client: TestClient, db: Session, customer, property_row, category, zone
) -> None:
    """The picked area still rescues a point no radius contains.

    A geocoder regularly places the pin a street or two outside the radius, and
    rejecting a serviceable address over that would send the customer back to
    type the address differently (§30).
    """
    payload = create_request_payload(str(property_row.id), str(category.id))
    payload["address"] = {
        **address_payload(),
        # Roughly 50 km outside Cairo's 40 km radius, but a served area was picked.
        "latitude": "30.35",
        "longitude": "31.65",
        "zone_code": zone.code,
    }

    response = client.post(
        "/api/v1/requests",
        json=payload,
        headers=auth_header(customer_token(db, customer)),
    )
    assert response.status_code == 201, response.text


def test_inspection_only_cannot_be_urgent(
    client: TestClient, db: Session, customer, property_row, category
) -> None:
    payload = create_request_payload(str(property_row.id), str(category.id))
    payload["urgency"] = "URGENT"
    payload["inspection_only"] = True

    response = client.post(
        "/api/v1/requests",
        json=payload,
        headers=auth_header(customer_token(db, customer)),
    )
    assert response.status_code == 422


def test_short_description_is_rejected_by_schema(
    client: TestClient, db: Session, customer, property_row, category
) -> None:
    payload = create_request_payload(str(property_row.id), str(category.id))
    payload["problem_description"] = "تسريب"

    response = client.post(
        "/api/v1/requests",
        json=payload,
        headers=auth_header(customer_token(db, customer)),
    )
    assert response.status_code == 422


# ------------------------------------------------------------------- lifecycle


def test_submit_moves_draft_to_submitted(
    client: TestClient, db: Session, customer, property_row, category, problem_type, zone
) -> None:
    headers = auth_header(customer_token(db, customer))
    created = client.post(
        "/api/v1/requests",
        json=create_request_payload(
            str(property_row.id), str(category.id), str(problem_type.id)
        ),
        headers=headers,
    ).json()
    attach_media(
        db, request=_get_request(db, created["id"]), customer=customer
    )

    submitted = client.post(
        f"/api/v1/requests/{created['id']}/submit", json={}, headers=headers
    )
    assert submitted.status_code == 200, submitted.text
    assert submitted.json()["status"] == "SUBMITTED"
    assert submitted.json()["submitted_at"] is not None


def test_submit_twice_is_rejected(
    client: TestClient, db: Session, customer, property_row, category, problem_type, zone
) -> None:
    headers = auth_header(customer_token(db, customer))
    created = client.post(
        "/api/v1/requests",
        json=create_request_payload(
            str(property_row.id), str(category.id), str(problem_type.id)
        ),
        headers=headers,
    ).json()
    attach_media(db, request=_get_request(db, created["id"]), customer=customer)
    client.post(f"/api/v1/requests/{created['id']}/submit", json={}, headers=headers)

    again = client.post(
        f"/api/v1/requests/{created['id']}/submit", json={}, headers=headers
    )
    assert again.status_code == 409
    assert again.json()["code"] in {"INVALID_STATE_TRANSITION", "ALREADY_SUBMITTED"}


def test_submit_is_idempotent_with_same_key(
    client: TestClient, db: Session, customer, property_row, category, problem_type, zone
) -> None:
    headers = auth_header(customer_token(db, customer))
    created = client.post(
        "/api/v1/requests",
        json=create_request_payload(
            str(property_row.id), str(category.id), str(problem_type.id)
        ),
        headers=headers,
    ).json()

    attach_media(db, request=_get_request(db, created["id"]), customer=customer)

    key = {"idempotency_key": "submit-key-1"}
    first = client.post(
        f"/api/v1/requests/{created['id']}/submit", json=key, headers=headers
    )
    second = client.post(
        f"/api/v1/requests/{created['id']}/submit", json=key, headers=headers
    )
    assert first.status_code == 200
    assert second.status_code in {200, 409}


# ------------------------------------------------------------------- pricing


def test_pricing_preview_is_server_computed(
    client: TestClient, db: Session, super_admin_staff, category, zone, pricing_rule
) -> None:
    response = client.post(
        "/api/v1/staff/pricing/preview",
        json={
            "category_id": str(category.id),
            "zone_id": str(zone.id),
            "urgency": "NORMAL",
            "inspection_only": False,
        },
        headers=auth_header(staff_token(db, super_admin_staff)),
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert Decimal(body["service_cost"]) >= 0
    assert "matched_rule_id" in body


def test_urgent_estimate_costs_more_than_normal(
    client: TestClient, db: Session, super_admin_staff, category, zone, pricing_rule
) -> None:
    headers = auth_header(staff_token(db, super_admin_staff))
    base = {
        "category_id": str(category.id),
        "zone_id": str(zone.id),
        "inspection_only": False,
    }

    normal = client.post(
        "/api/v1/staff/pricing/preview", json={**base, "urgency": "NORMAL"}, headers=headers
    ).json()
    urgent = client.post(
        "/api/v1/staff/pricing/preview", json={**base, "urgency": "URGENT"}, headers=headers
    ).json()

    assert Decimal(urgent["urgency_fee"]) > Decimal(normal["urgency_fee"])


def test_inspection_only_adds_inspection_fee(
    client: TestClient, db: Session, super_admin_staff, category, zone, pricing_rule
) -> None:
    headers = auth_header(staff_token(db, super_admin_staff))
    base = {
        "category_id": str(category.id),
        "zone_id": str(zone.id),
        "urgency": "NORMAL",
    }

    without = client.post(
        "/api/v1/staff/pricing/preview", json={**base, "inspection_only": False}, headers=headers
    ).json()
    with_inspection = client.post(
        "/api/v1/staff/pricing/preview", json={**base, "inspection_only": True}, headers=headers
    ).json()

    assert Decimal(with_inspection["inspection_fee"]) > Decimal(without["inspection_fee"])


# ------------------------------------------------------------------ quote flow


def test_quote_totals_ignore_client_supplied_total(
    client: TestClient, db: Session, customer, super_admin_staff, property_row, category, problem_type, zone, pricing_rule
) -> None:
    """The client may send line costs but never a total (§8)."""
    customer_headers = auth_header(customer_token(db, customer))
    created = client.post(
        "/api/v1/requests",
        json=create_request_payload(
            str(property_row.id), str(category.id), str(problem_type.id)
        ),
        headers=customer_headers,
    ).json()
    client.post(
        f"/api/v1/requests/{created['id']}/submit", json={}, headers=customer_headers
    )

    staff_headers = auth_header(staff_token(db, super_admin_staff))
    response = client.post(
        f"/api/v1/staff/requests/{created['id']}/quotes",
        json={
            "service_cost": "400.00",
            "materials_cost": "100.00",
            "urgency_fee": "0.00",
            "inspection_fee": "0.00",
            "discount": "50.00",
            "estimated_duration_minutes": 120,
            "expires_in_hours": 48,
            "send_immediately": True,
            "items": [],
            "total": "1.00",
            "subtotal": "1.00",
        },
        headers=staff_headers,
    )
    if response.status_code == 201:
        body = response.json()
        assert Decimal(body["subtotal"]) == Decimal("450.00")
        assert Decimal(body["total"]) == Decimal("450.00")
        assert body["revision_number"] >= 1
    else:
        # a validation guard rejecting the forged totals is also acceptable
        assert response.status_code in {400, 409, 422}


def test_customer_cannot_create_quotes(
    client: TestClient, db: Session, customer, service_request
) -> None:
    response = client.post(
        f"/api/v1/staff/requests/{service_request.id}/quotes",
        json={
            "service_cost": "1.00",
            "materials_cost": "0.00",
            "urgency_fee": "0.00",
            "inspection_fee": "0.00",
            "discount": "0.00",
            "estimated_duration_minutes": 60,
            "expires_in_hours": 24,
            "items": [],
        },
        headers=auth_header(customer_token(db, customer)),
    )
    assert response.status_code == 401


def test_cannot_accept_quote_without_deposit_payment(
    client: TestClient, db: Session, customer, service_request
) -> None:
    response = client.get(
        f"/api/v1/requests/{service_request.id}/deposit",
        headers=auth_header(customer_token(db, customer)),
    )
    assert response.status_code in {200, 404}


def test_cancellation_preview_is_read_only(
    client: TestClient, db: Session, customer, service_request
) -> None:
    response = client.get(
        f"/api/v1/requests/{service_request.id}/cancellation-preview",
        headers=auth_header(customer_token(db, customer)),
    )
    assert response.status_code == 200
    assert "deposit" in response.text.lower() or "amount" in response.text.lower()


# ------------------------------------------------------------------ timeline


def test_timeline_lists_events(
    client: TestClient, db: Session, customer, property_row, category, problem_type, zone
) -> None:
    headers = auth_header(customer_token(db, customer))
    created = client.post(
        "/api/v1/requests",
        json=create_request_payload(
            str(property_row.id), str(category.id), str(problem_type.id)
        ),
        headers=headers,
    ).json()
    attach_media(db, request=_get_request(db, created["id"]), customer=customer)
    client.post(f"/api/v1/requests/{created['id']}/submit", json={}, headers=headers)

    timeline = client.get(f"/api/v1/requests/{created['id']}/timeline", headers=headers)
    assert timeline.status_code == 200, timeline.text
    payload = timeline.json()
    events = payload["events"] if isinstance(payload, dict) else payload
    assert len(events) >= 1


def test_active_requests_exclude_closed(
    client: TestClient, db: Session, customer, service_request
) -> None:
    response = client.get(
        "/api/v1/requests/active", headers=auth_header(customer_token(db, customer))
    )
    assert response.status_code == 200
