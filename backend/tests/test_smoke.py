"""Boot and routing smoke tests.

These assert the application actually serves traffic — that ``main.py`` builds,
that OpenAPI resolves, and that the health probes answer. Runtime import errors
in any endpoint surface here.
"""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.main import app


def test_openapi_resolves() -> None:
    spec = app.openapi()
    assert spec["openapi"].startswith("3.")
    assert len(spec["paths"]) > 50


def test_health_probe(client: TestClient) -> None:
    response = client.get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["environment"] == "test"


def test_readiness_probe(client: TestClient) -> None:
    response = client.get("/health/ready")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_customer_routes_mounted() -> None:
    spec = app.openapi()
    paths = spec["paths"]
    for expected in (
        "/api/v1/services",
        "/api/v1/catalogue",
        "/api/v1/properties",
        "/api/v1/requests",
        "/api/v1/orders",
        "/api/v1/conversations",
        "/api/v1/complaints",
        "/api/v1/auth/request-otp",
        "/api/v1/auth/verify-otp",
        "/api/v1/staff/auth/login",
        "/api/v1/staff/requests",
        "/api/v1/media/{media_id}/content",
        "/api/v1/staff/analytics/overview",
    ):
        assert expected in paths, f"missing route: {expected}"


def test_unauthenticated_request_is_rejected(client: TestClient) -> None:
    response = client.get("/api/v1/properties")
    assert response.status_code == 401
    assert response.json()["code"]
