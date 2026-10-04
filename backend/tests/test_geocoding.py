"""Served areas and address search (§29, §30, §31, §135).

These pin the behaviour the address form depends on: the list is derived from
the zones table, coverage is decided by coordinates rather than by spelling, and
the upstream geocoder is never called without its identifying User-Agent.
"""

from __future__ import annotations

from decimal import Decimal

import httpx
import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.exceptions import GeocoderUnavailableError
from app.db.models.catalog import CoverageZone
from app.services import geocoding_service
from tests.conftest import auth_header, customer_token


@pytest.fixture(autouse=True)
def fresh_geocoder_state(monkeypatch: pytest.MonkeyPatch) -> None:
    """Gives every test an empty cache and no throttle debt.

    The cache and the one-request-per-second limiter are process-wide, because
    Nominatim's usage policy is. Left alone, the first test to search a given
    query would answer the next one from cache instead of calling the stubbed
    upstream, and every later search would sleep for a second first.
    """
    monkeypatch.setattr(
        geocoding_service,
        "_cache",
        geocoding_service._TTLCache(settings.geocode_cache_ttl_seconds),
    )
    monkeypatch.setattr(geocoding_service, "_last_request_at", 0.0)


def test_haversine_is_zero_for_the_same_point() -> None:
    assert geocoding_service.haversine_km(31.15, 31.41, 31.15, 31.41) == 0


def test_haversine_matches_a_known_distance() -> None:
    # Cairo to Damietta is roughly 165 km. A loose bound is used because the
    # exact figure depends on the formula's earth radius constant.
    distance = geocoding_service.haversine_km(30.0444, 31.2357, 31.4167, 31.8083)
    assert 160 < distance < 175


def test_zone_for_point_picks_the_nearest_containing_zone(
    db: Session, zone
) -> None:
    zones = geocoding_service.active_zones(db)
    # Well inside Cairo's 40 km radius.
    assert geocoding_service.zone_for_point(
        zones, latitude=30.05, longitude=31.24
    ) is zone


def test_zone_for_point_returns_none_outside_every_radius(
    db: Session, zone
) -> None:
    zones = geocoding_service.active_zones(db)
    assert (
        geocoding_service.zone_for_point(zones, latitude=24.0889, longitude=32.8998)
        is None
    )


def test_a_zone_without_a_centre_never_claims_a_point(db: Session) -> None:
    # Nulls must not be read as 0,0, which would cover the Gulf of Guinea.
    headless = CoverageZone(
        code="NOWHERE",
        name_ar="بلا مركز",
        governorate="Nowhere",
        city="Nowhere",
        is_active=True,
        radius_km=Decimal("500"),
    )
    db.add(headless)
    db.flush()

    zones = geocoding_service.active_zones(db)
    assert (
        geocoding_service.zone_for_point(zones, latitude=0.0, longitude=0.0) is None
    )


def test_zone_by_text_matches_arabic_names(db: Session, zone) -> None:
    zones = geocoding_service.active_zones(db)
    # An Arabic district resolves as readily as the English pair.
    assert (
        geocoding_service.zone_by_text(zones, governorate=None, city="القاهرة") is zone
    )


def test_short_queries_are_ignored_without_calling_upstream(db: Session) -> None:
    # Guards against a keystroke-by-keystroke flood of outbound requests.
    assert geocoding_service.search_address(db, "د") == []
    assert geocoding_service.search_address(db, "  ") == []


def test_search_marks_a_hit_inside_coverage(
    db: Session, zone, monkeypatch: pytest.MonkeyPatch
) -> None:
    _stub_nominatim(
        monkeypatch,
        [
            {
                "lat": "30.0444",
                "lon": "31.2357",
                "display_name": "شارع التحرير، القاهرة",
                "address": {"road": "شارع التحرير", "city": "القاهرة"},
            }
        ],
    )

    results = geocoding_service.search_address(db, "شارع التحرير القاهرة")

    assert len(results) == 1
    hit = results[0]
    assert hit.zone_code == zone.code
    assert hit.street == "شارع التحرير"


def test_search_marks_a_hit_outside_coverage(
    db: Session, zone, monkeypatch: pytest.MonkeyPatch
) -> None:
    _stub_nominatim(
        monkeypatch,
        [
            {
                "lat": "24.0889",
                "lon": "32.8998",
                "display_name": "أسوان",
                "address": {"city": "أسوان"},
            }
        ],
    )

    results = geocoding_service.search_address(db, "أسوان")

    assert len(results) == 1
    assert results[0].zone_code is None
    assert results[0].zone_name_ar is None


def test_search_sends_an_identifying_user_agent(
    db: Session, zone, monkeypatch: pytest.MonkeyPatch
) -> None:
    # OSM's usage policy requires this; the app must never appear as an
    # anonymous client.
    seen: dict[str, str] = {}
    original_get = httpx.Client.get

    def _fake_get(self, url, *, params=None, headers=None, **kwargs):  # noqa: ANN001
        if settings.nominatim_base_url not in str(url):
            return original_get(self, url, params=params, headers=headers, **kwargs)
        seen.update(headers or {})
        return httpx.Response(
            200, json=[], request=httpx.Request("GET", str(url))
        )

    monkeypatch.setattr(httpx.Client, "get", _fake_get)
    geocoding_service.search_address(db, "شارع التحرير")

    assert seen.get("User-Agent") == settings.nominatim_user_agent


def test_search_raises_a_retryable_error_when_upstream_fails(
    db: Session, zone, monkeypatch: pytest.MonkeyPatch
) -> None:
    # 503 rather than 400: the query was fine, the upstream was not.
    def _boom(self, url, **kwargs):  # noqa: ANN001
        raise httpx.ConnectError("refused")

    monkeypatch.setattr(httpx.Client, "get", _boom)

    with pytest.raises(GeocoderUnavailableError) as caught:
        geocoding_service.search_address(db, "شارع التحرير")

    assert caught.value.http_status == 503


def test_an_empty_upstream_answer_is_not_an_error(
    db: Session, zone, monkeypatch: pytest.MonkeyPatch
) -> None:
    # "No such street" is an answer, and the app renders it as empty results
    # rather than a failure banner.
    _stub_nominatim(monkeypatch, [])
    assert geocoding_service.search_address(db, "شارع غير موجود") == []


def test_malformed_entries_are_skipped(
    db: Session, zone, monkeypatch: pytest.MonkeyPatch
) -> None:
    _stub_nominatim(
        monkeypatch,
        [
            {"lat": "not-a-number", "lon": "31.2", "display_name": "سيء"},
            {"display_name": "بلا إحداثيات"},
            {
                "lat": "30.0444",
                "lon": "31.2357",
                "display_name": "شارع الخير",
                "address": {},
            },
        ],
    )

    results = geocoding_service.search_address(db, "شارع الخير")

    assert [r.display_name for r in results] == ["شارع الخير"]


# ------------------------------------------------------------------ endpoints


def test_coverage_zones_endpoint_lists_active_areas(
    client: TestClient, db: Session, customer, zone
) -> None:
    response = client.get(
        "/api/v1/coverage-zones", headers=auth_header(customer_token(db, customer))
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert [z["code"] for z in body] == [zone.code]
    # Arabic labels are what the customer reads, so they must be present.
    assert body[0]["name_ar"] == "القاهرة"


def test_coverage_zones_requires_authentication(client: TestClient) -> None:
    assert client.get("/api/v1/coverage-zones").status_code == 401


def test_coverage_zones_still_lists_an_area_without_a_centre(
    client: TestClient, db: Session, customer
) -> None:
    # A zone with no centre is still an area the operator chose to serve, so it
    # has to reach the app. Reporting it as 0,0 would point at the Gulf of
    # Guinea; failing to serialise it would take the whole picker down.
    db.add(
        CoverageZone(
            code="NOWHERE",
            name_ar="بلا مركز",
            governorate="Nowhere",
            city="Nowhere",
            is_active=True,
            radius_km=Decimal("500"),
        )
    )
    db.flush()

    response = client.get(
        "/api/v1/coverage-zones", headers=auth_header(customer_token(db, customer))
    )

    assert response.status_code == 200, response.text
    headless = next(z for z in response.json() if z["code"] == "NOWHERE")
    assert headless["center_latitude"] is None
    # Decimals serialise as strings, which is what keeps the exact value intact.
    assert Decimal(headless["radius_km"]) == Decimal("500")


def test_address_search_requires_authentication(client: TestClient) -> None:
    assert client.get("/api/v1/address-search", params={"q": "دمياط"}).status_code == 401


def test_address_search_endpoint_returns_matched_zones(
    client: TestClient, db: Session, customer, zone, monkeypatch: pytest.MonkeyPatch
) -> None:
    _stub_nominatim(
        monkeypatch,
        [
            {
                "lat": "30.0444",
                "lon": "31.2357",
                "display_name": "شارع التحرير، القاهرة",
                "address": {"road": "شارع التحرير", "city": "القاهرة"},
            }
        ],
    )

    response = client.get(
        "/api/v1/address-search",
        params={"q": "شارع التحرير"},
        headers=auth_header(customer_token(db, customer)),
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert body, response.text
    # Compared with the raw body as the message: a shape change here should say
    # what came back rather than only that a key was missing.
    assert body[0].get("zone_code") == zone.code, response.text


def test_address_search_rejects_an_overlong_query(
    client: TestClient, db: Session, customer
) -> None:
    # Authenticated, because the endpoint checks the session before it validates
    # the query: an anonymous call is a 401, not a 422.
    response = client.get(
        "/api/v1/address-search",
        params={"q": "x" * 500},
        headers=auth_header(customer_token(db, customer)),
    )
    assert response.status_code == 422


def _stub_nominatim(
    monkeypatch: pytest.MonkeyPatch, payload: list[dict[str, object]]
) -> None:
    """Replaces the outbound geocoder call so tests never touch the network.

    Only requests to the configured Nominatim host are intercepted. Patching
    `httpx.Client.get` unconditionally would also catch starlette's TestClient,
    which subclasses it, and the test's own request to the app would be answered
    with this payload instead of reaching the endpoint.
    """
    original_get = httpx.Client.get

    def _fake_get(self, url, **kwargs):  # noqa: ANN001
        if settings.nominatim_base_url not in str(url):
            return original_get(self, url, **kwargs)
        return httpx.Response(
            200, json=payload, request=httpx.Request("GET", str(url))
        )

    monkeypatch.setattr(httpx.Client, "get", _fake_get)
