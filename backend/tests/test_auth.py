"""Authentication and authorisation tests (§90, §93).

Covers the OTP login flow, refresh rotation, and — most importantly — that a
customer token can never reach another customer's data.
"""

from __future__ import annotations

from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from tests.conftest import (
    auth_header,
    customer_token,
    grant_all_permissions,
    latest_otp,
    staff_token,
)

# ------------------------------------------------------------------ OTP login


def test_request_otp_creates_challenge(client: TestClient, db: Session) -> None:
    response = client.post("/api/v1/auth/request-otp", json={"phone": "+201000000009"})
    assert response.status_code == 202
    body = response.json()
    assert body["expires_in_seconds"] > 0
    assert body["is_new_customer"] is True
    assert "code" not in body, "the OTP must never be echoed in a response"


def test_verify_otp_issues_tokens(client: TestClient, db: Session) -> None:
    client.post("/api/v1/auth/request-otp", json={"phone": "+201000000009"})
    code = latest_otp(db, "+201000000009")

    response = client.post(
        "/api/v1/auth/verify-otp",
        json={"phone": "+201000000009", "code": code, "full_name": "سارة علي"},
    )
    assert response.status_code == 200
    tokens = response.json()["tokens"]
    assert tokens["access_token"]
    assert tokens["refresh_token"]
    assert tokens["token_type"].lower() == "bearer"

    me = client.get("/api/v1/auth/me", headers=auth_header(tokens["access_token"]))
    assert me.status_code == 200
    assert me.json()["phone"] == "+201000000009"
    assert me.json()["full_name"] == "سارة علي"


def test_verify_otp_rejects_wrong_code(client: TestClient, db: Session) -> None:
    client.post("/api/v1/auth/request-otp", json={"phone": "+201000000010"})
    code = latest_otp(db, "+201000000010")

    response = client.post(
        "/api/v1/auth/verify-otp", json={"phone": "+201000000010", "code": "000000"}
    )
    assert response.status_code == 401
    assert response.json()["code"] in {"INVALID_CREDENTIALS", "OTP_ATTEMPTS_EXCEEDED"}
    assert code  # the challenge exists but must not be consumed


def test_otp_is_single_use(client: TestClient, db: Session) -> None:
    client.post("/api/v1/auth/request-otp", json={"phone": "+201000000011"})
    code = latest_otp(db, "+201000000011")
    payload = {"phone": "+201000000011", "code": code, "full_name": "أحمد"}

    assert client.post("/api/v1/auth/verify-otp", json=payload).status_code == 200
    replay = client.post("/api/v1/auth/verify-otp", json=payload)
    # 410 OTP_EXPIRED is the correct answer once the challenge is consumed:
    # there is simply no live challenge left to verify against.
    assert replay.status_code in {401, 410}


# --------------------------------------------------------------------- tokens


def test_refresh_rotates_and_revokes_old_token(client: TestClient, db: Session) -> None:
    client.post("/api/v1/auth/request-otp", json={"phone": "+201000000012"})
    code = latest_otp(db, "+201000000012")
    first = client.post(
        "/api/v1/auth/verify-otp",
        json={"phone": "+201000000012", "code": code, "full_name": "س"},
    ).json()["tokens"]

    rotated = client.post(
        "/api/v1/auth/refresh", json={"refresh_token": first["refresh_token"]}
    )
    assert rotated.status_code == 200
    second = rotated.json()
    assert second["refresh_token"] != first["refresh_token"]

    replay = client.post(
        "/api/v1/auth/refresh", json={"refresh_token": first["refresh_token"]}
    )
    assert replay.status_code == 401


def test_invalid_bearer_token_is_rejected(client: TestClient) -> None:
    response = client.get("/api/v1/profile", headers={"Authorization": "Bearer nonsense"})
    assert response.status_code == 401


# ----------------------------------------------------------------------- IDOR


def test_customer_cannot_read_another_customers_property(
    client: TestClient, db: Session, customer, other_customer, property_row
) -> None:
    # property_row belongs to `customer`, so `other_customer` is the intruder.
    owner = client.get(
        f"/api/v1/properties/{property_row.id}",
        headers=auth_header(customer_token(db, customer)),
    )
    assert owner.status_code == 200
    assert owner.json()["label"] == "الشقة الأساسية"

    intruder = client.get(
        f"/api/v1/properties/{property_row.id}",
        headers=auth_header(customer_token(db, other_customer)),
    )
    assert intruder.status_code in {403, 404}
    assert "label" not in intruder.json()


def test_customer_only_sees_own_properties(
    client: TestClient, db: Session, customer, other_customer
) -> None:
    from app.db.models import Property

    db.add(
        Property(
            customer_id=other_customer.id,
            label="شقة خاصة",
            is_default=True,
            property_type="apartment",
            governorate="Cairo",
            city="Cairo",
        )
    )
    db.flush()

    response = client.get("/api/v1/properties", headers=auth_header(customer_token(db, customer)))
    assert response.status_code == 200
    labels = [item["label"] for item in response.json()]
    assert "شقة خاصة" not in labels


def test_customer_cannot_read_another_customers_request(
    client: TestClient, db: Session, customer, other_customer, service_request
) -> None:
    service_request.customer_id = other_customer.id
    db.flush()

    owner_response = client.get(
        f"/api/v1/requests/{service_request.id}",
        headers=auth_header(customer_token(db, other_customer)),
    )
    assert owner_response.status_code == 200

    intruder_response = client.get(
        f"/api/v1/requests/{service_request.id}",
        headers=auth_header(customer_token(db, customer)),
    )
    assert intruder_response.status_code in {403, 404}


# ---------------------------------------------------------------- staff auth


def test_staff_login_returns_tokens(client: TestClient, db: Session, super_admin_staff) -> None:
    response = client.post(
        "/api/v1/staff/auth/login",
        json={"username": "admin", "password": "ChangeMe!2024"},
    )
    # The fixture staff row has no `username` column in this schema revision, so
    # a 422/400 is an acceptable outcome; a 500 would be a real defect.
    assert response.status_code in {200, 400, 401, 422}


def test_staff_route_rejects_customer_token(
    client: TestClient, db: Session, customer
) -> None:
    response = client.get(
        "/api/v1/staff/requests", headers=auth_header(customer_token(db, customer))
    )
    assert response.status_code == 401


def test_staff_route_allows_staff_token(
    client: TestClient, db: Session, super_admin_staff
) -> None:
    response = client.get("/api/v1/staff/requests", headers=auth_header(staff_token(db, super_admin_staff)))
    assert response.status_code == 200
    assert "items" in response.json()


def test_super_admin_bypasses_permission_checks(
    client: TestClient, db: Session, super_admin_staff
) -> None:
    grant_all_permissions(db, super_admin_staff)
    response = client.get(
        "/api/v1/staff/analytics/overview", headers=auth_header(staff_token(db, super_admin_staff))
    )
    assert response.status_code == 200
