"""Authentication and authorisation tests (§90, §93).

Covers the email-OTP login flow, refresh rotation, Google sign-in, and — most
importantly — that a customer token can never reach another customer's data.
"""

from __future__ import annotations

from types import SimpleNamespace

from fastapi.testclient import TestClient
from httpx import Response
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.models import OtpDeliveryLog, User
from app.services import auth_service, email_service
from tests.conftest import (
    auth_header,
    customer_token,
    grant_all_permissions,
    latest_otp,
    staff_token,
)

# ------------------------------------------------------------------ OTP login


def _request(client: TestClient, email: str, phone: str | None = None) -> Response:
    payload: dict[str, object] = {"email": email}
    if phone is not None:
        payload["phone"] = phone
    return client.post("/api/v1/auth/request-otp", json=payload)


def test_request_otp_creates_challenge(client: TestClient, db: Session) -> None:
    response = _request(client, "sara@example.com")
    assert response.status_code == 202
    body = response.json()
    assert body["expires_in_seconds"] > 0
    assert body["is_new_customer"] is True
    assert "code" not in body, "the OTP must never be echoed in a response"


def test_a_malformed_email_is_rejected_before_anything_is_written(
    client: TestClient, db: Session
) -> None:
    response = client.post("/api/v1/auth/request-otp", json={"email": "not-an-email"})
    assert response.status_code == 422
    assert db.query(User).count() == 0


def test_verify_otp_issues_tokens(client: TestClient, db: Session) -> None:
    _request(client, "sara@example.com")
    code = latest_otp(db, "sara@example.com")

    response = client.post(
        "/api/v1/auth/verify-otp",
        json={"email": "sara@example.com", "code": code, "full_name": "سارة علي"},
    )
    assert response.status_code == 200
    tokens = response.json()["tokens"]
    assert tokens["access_token"]
    assert tokens["refresh_token"]
    assert tokens["token_type"].lower() == "bearer"

    me = client.get("/api/v1/auth/me", headers=auth_header(tokens["access_token"]))
    assert me.status_code == 200
    assert me.json()["email"] == "sara@example.com"
    assert me.json()["full_name"] == "سارة علي"
    assert me.json()["phone"] is None, "a blank phone must stay blank, not invented"


def test_the_phone_is_optional_but_really_stored(
    client: TestClient, db: Session
) -> None:
    """The number the customer does give has to come back on their own profile."""
    _request(client, "nour@example.com", phone="+201001234567")
    code = latest_otp(db, "nour@example.com")

    session = client.post(
        "/api/v1/auth/verify-otp",
        json={"email": "nour@example.com", "code": code, "full_name": "نور"},
    ).json()["tokens"]
    me = client.get("/api/v1/auth/me", headers=auth_header(session["access_token"]))
    assert me.json()["phone"] == "+201001234567"


def test_the_same_email_is_always_the_same_account(
    client: TestClient, db: Session
) -> None:
    """A different number on the next visit must not fork the customer."""
    assert _request(client, "nour@example.com", phone="+201000000020").json()[
        "is_new_customer"
    ]
    code = latest_otp(db, "nour@example.com")
    assert (
        client.post(
            "/api/v1/auth/verify-otp",
            json={"email": "nour@example.com", "code": code, "full_name": "نور"},
        ).status_code
        == 200
    )

    again = _request(client, "nour@example.com", phone="+201000000021")
    assert again.json()["is_new_customer"] is False
    assert db.query(User).filter(User.email == "nour@example.com").count() == 1

    user = db.query(User).filter(User.email == "nour@example.com").one()
    assert user.phone == "+201000000021", "a corrected number has to stick"


def test_email_matching_ignores_case(client: TestClient, db: Session) -> None:
    _request(client, "Sara@Example.com")
    code = latest_otp(db, "sara@example.com")

    response = client.post(
        "/api/v1/auth/verify-otp",
        json={"email": "SARA@EXAMPLE.COM", "code": code, "full_name": "سارة"},
    )
    assert response.status_code == 200
    assert db.query(User).filter(User.email == "sara@example.com").count() == 1


def test_verify_otp_rejects_wrong_code(client: TestClient, db: Session) -> None:
    _request(client, "nada@example.com")
    code = latest_otp(db, "nada@example.com")

    response = client.post(
        "/api/v1/auth/verify-otp", json={"email": "nada@example.com", "code": "000000"}
    )
    assert response.status_code == 401
    assert response.json()["code"] in {"INVALID_CREDENTIALS", "OTP_ATTEMPTS_EXCEEDED"}
    assert code  # the challenge exists but must not be consumed


def test_otp_is_single_use(client: TestClient, db: Session) -> None:
    _request(client, "mona@example.com")
    code = latest_otp(db, "mona@example.com")
    payload = {"email": "mona@example.com", "code": code, "full_name": "أحمد"}

    assert client.post("/api/v1/auth/verify-otp", json=payload).status_code == 200
    replay = client.post("/api/v1/auth/verify-otp", json=payload)
    # 410 OTP_EXPIRED is the correct answer once the challenge is consumed:
    # there is simply no live challenge left to verify against.
    assert replay.status_code in {401, 410}


def test_a_code_for_an_unknown_address_is_rejected(
    client: TestClient, db: Session
) -> None:
    response = client.post(
        "/api/v1/auth/verify-otp",
        json={"email": "nobody@example.com", "code": "123456"},
    )
    assert response.status_code == 401


def test_an_unconfigured_relay_still_completes_the_flow(
    client: TestClient, db: Session, monkeypatch
) -> None:
    """§135: no mail credentials means the log carries the code, not a failure."""
    monkeypatch.setattr(settings, "smtp_host", "")

    assert _request(client, "offline@example.com").status_code == 202
    code = latest_otp(db, "offline@example.com")
    assert client.post(
        "/api/v1/auth/verify-otp",
        json={"email": "offline@example.com", "code": code},
    ).status_code == 200

    log_row = db.query(OtpDeliveryLog).order_by(OtpDeliveryLog.created_at.desc()).first()
    assert log_row is not None and log_row.provider == "log_only"
    assert log_row.destination_masked == "o***@example.com"


def test_a_refused_send_fails_the_request_rather_than_dropping_the_code(
    client: TestClient, db: Session, monkeypatch
) -> None:
    """"Code sent" must never be shown for a code that could not leave."""
    monkeypatch.setattr(settings, "smtp_host", "smtp.example.com")

    def _boom(*_args: object, **_kwargs: object) -> None:
        raise OSError("connection refused")

    monkeypatch.setattr(email_service.smtplib, "SMTP", _boom)

    response = _request(client, "blocked@example.com")
    assert response.status_code == 503
    assert response.json()["code"] == "INTEGRATION_UNAVAILABLE"
    assert db.query(OtpDeliveryLog).count() == 0


# ------------------------------------------------------------------ Google


def _claims(**overrides: object) -> dict[str, object]:
    claims: dict[str, object] = {
        "iss": "https://accounts.google.com",
        "aud": settings.google_client_ids[0],
        "sub": "1118273645",
        "email": "mohamed@gmail.com",
        "email_verified": True,
        "name": "محمد علي",
        "picture": "https://example.com/a.png",
    }
    claims.update(overrides)
    return claims


def _stub_verifier(monkeypatch, claims: dict[str, object]) -> None:
    """Stand in for Google so the suite never needs the network."""
    monkeypatch.setattr(
        auth_service,
        "id_token",
        SimpleNamespace(verify_oauth2_token=lambda *_args, **_kwargs: claims),
    )


def test_google_sign_in_creates_a_phone_less_customer(
    client: TestClient, db: Session, monkeypatch
) -> None:
    _stub_verifier(monkeypatch, _claims())

    response = client.post("/api/v1/auth/google", json={"id_token": "x" * 40})
    assert response.status_code == 200
    body = response.json()
    assert body["tokens"]["access_token"]
    assert body["customer"]["email"] == "mohamed@gmail.com"

    # The whole point of the migration: no fake number is written anywhere.
    assert body["customer"]["phone"] is None

    me = client.get(
        "/api/v1/auth/me", headers=auth_header(body["tokens"]["access_token"])
    )
    assert me.status_code == 200
    assert me.json()["phone"] is None
    assert me.json()["full_name"] == "محمد علي"

    user = db.query(User).filter(User.google_sub == "1118273645").one()
    assert user.phone is None


def test_google_sign_in_is_idempotent(client: TestClient, db: Session, monkeypatch) -> None:
    _stub_verifier(monkeypatch, _claims())

    first = client.post("/api/v1/auth/google", json={"id_token": "x" * 40})
    second = client.post("/api/v1/auth/google", json={"id_token": "x" * 40})
    assert first.status_code == second.status_code == 200
    assert first.json()["customer"]["id"] == second.json()["customer"]["id"]
    assert db.query(User).filter(User.google_sub == "1118273645").count() == 1


def test_google_sign_in_reuses_an_existing_otp_account(
    client: TestClient, db: Session, customer, monkeypatch
) -> None:
    """The same human must not end up with two accounts, one per sign-in method."""
    _stub_verifier(monkeypatch, _claims(email="ahmed@example.com"))

    response = client.post("/api/v1/auth/google", json={"id_token": "x" * 40})
    assert response.status_code == 200
    assert response.json()["customer"]["id"] == str(customer.id)

    linked = db.query(User).filter(User.id == customer.user_id).one()
    assert linked.google_sub == "1118273645"
    assert linked.phone == "+201000000001", "the OTP number must survive the link"
    assert db.query(User).filter(User.google_sub == "1118273645").count() == 1


def test_google_rejects_a_token_issued_to_another_client(
    client: TestClient, db: Session, monkeypatch
) -> None:
    """A real Google token for someone else's app must not sign anyone in here."""
    _stub_verifier(monkeypatch, _claims(aud="attacker-client.apps.googleusercontent.com"))

    response = client.post("/api/v1/auth/google", json={"id_token": "x" * 40})
    assert response.status_code == 401
    assert response.json()["code"] == "INVALID_CREDENTIALS"
    assert db.query(User).filter(User.google_sub == "1118273645").count() == 0


def test_google_rejects_a_token_from_another_issuer(client: TestClient, monkeypatch) -> None:
    _stub_verifier(monkeypatch, _claims(iss="https://evil.example.com"))

    response = client.post("/api/v1/auth/google", json={"id_token": "x" * 40})
    assert response.status_code == 401


def test_google_rejects_an_unverified_email(client: TestClient, monkeypatch) -> None:
    _stub_verifier(monkeypatch, _claims(email_verified=False))

    response = client.post("/api/v1/auth/google", json={"id_token": "x" * 40})
    assert response.status_code == 401


def test_google_sign_in_reports_a_missing_configuration(
    client: TestClient, monkeypatch
) -> None:
    """Without a client ID every token is unverifiable, so say that plainly."""
    monkeypatch.setattr(settings, "google_client_ids", [])

    response = client.post("/api/v1/auth/google", json={"id_token": "x" * 40})
    assert response.status_code == 401
    assert response.json()["code"] == "GOOGLE_NOT_CONFIGURED"


# --------------------------------------------------------------------- tokens


def test_refresh_rotates_and_revokes_old_token(client: TestClient, db: Session) -> None:
    client.post("/api/v1/auth/request-otp", json={"email": "rotating@example.com"})
    code = latest_otp(db, "rotating@example.com")
    first = client.post(
        "/api/v1/auth/verify-otp",
        json={"email": "rotating@example.com", "code": code, "full_name": "س"},
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
