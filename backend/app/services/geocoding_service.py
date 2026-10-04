"""Address search and coverage matching (§29, §31).

Two jobs live here because they are the same lookup seen from two ends:

* `search_address` proxies a free-text query to a geocoder so the customer can
  type an address in Arabic and get a point back, instead of dragging a pin.
* `zone_for_point` decides which coverage area a coordinate belongs to.

Resolving coverage from coordinates rather than from typed text is what makes
Arabic input work: the backend matches the point it was given against the zone
centres it owns, so it never has to parse what the customer wrote (§30).

OSM's Nominatim policy requires an identifying User-Agent and at most one
request per second, which is why the app never calls it directly (§135).
"""

from __future__ import annotations

import math
import threading
import time
import uuid
from dataclasses import dataclass
from typing import Any

import httpx
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.exceptions import GeocoderUnavailableError
from app.db.models.catalog import CoverageZone
from app.schemas.catalog import CoverageZoneResponse, GeocodeResult

# Nominatim rejects requests without `addressdetails`, and the free-text parts
# of the response are matched by these keys in order.
_ROAD_KEYS = ("road", "pedestrian", "footway", "residential", "unclassified")
_NEIGHBOURHOOD_KEYS = ("neighbourhood", "suburb", "city_district", "quarter")
_CITY_KEYS = ("city", "town", "municipality", "village")
_REGION_KEYS = ("state", "region", "province")


@dataclass(frozen=True)
class _CacheEntry:
    value: list[GeocodeResult]
    stored_at: float


class _TTLCache:
    """Minimal TTL cache.

    Nominatim is a shared public service, so repeating a customer's own query
    must not become another outbound call. A dict with a sweep on write is
    enough at this size and keeps the service dependency-free.
    """

    def __init__(self, ttl_seconds: int) -> None:
        self._ttl = ttl_seconds
        self._entries: dict[str, _CacheEntry] = {}
        self._lock = threading.Lock()

    def get(self, key: str) -> list[GeocodeResult] | None:
        with self._lock:
            entry = self._entries.get(key)
            if entry is None:
                return None
            if time.monotonic() - entry.stored_at >= self._ttl:
                del self._entries[key]
                return None
            return entry.value

    def put(self, key: str, value: list[GeocodeResult]) -> None:
        with self._lock:
            if len(self._entries) > 2048:
                cutoff = time.monotonic() - self._ttl
                self._entries = {
                    k: v for k, v in self._entries.items() if v.stored_at >= cutoff
                }
            self._entries[key] = _CacheEntry(value=value, stored_at=time.monotonic())


_cache = _TTLCache(settings.geocode_cache_ttl_seconds)

# Nominatim asks for no more than one request per second. Serialising every
# outbound call behind a lock is the cheapest way to honour that, and the app
# has no other geocoder to spread load across.
_request_lock = threading.Lock()
_last_request_at = 0.0


def _throttle() -> None:
    global _last_request_at
    with _request_lock:
        wait = 1.0 - (time.monotonic() - _last_request_at)
        if wait > 0:
            time.sleep(wait)
        _last_request_at = time.monotonic()


# ------------------------------------------------------------------ coverage


def active_zones(session: Session) -> list[CoverageZone]:
    """Every served area, ordered for a dropdown."""
    return list(
        session.execute(
            select(CoverageZone)
            .where(
                CoverageZone.is_active.is_(True),
                CoverageZone.deleted_at.is_(None),
            )
            .order_by(CoverageZone.name_ar.asc())
        )
        .scalars()
    )


def list_coverage_zones(session: Session) -> list[CoverageZoneResponse]:
    return [CoverageZoneResponse.model_validate(zone) for zone in active_zones(session)]


def haversine_km(
    lat1: float, lon1: float, lat2: float, lon2: float
) -> float:
    """Great-circle distance in kilometres."""
    radius = 6371.0088
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    d_phi = math.radians(lat2 - lat1)
    d_lambda = math.radians(lon2 - lon1)
    a = (
        math.sin(d_phi / 2) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2) ** 2
    )
    return 2 * radius * math.asin(math.sqrt(a))


def zone_for_point(
    zones: list[CoverageZone], *, latitude: float, longitude: float
) -> CoverageZone | None:
    """The zone whose radius contains the point, nearest centre wins.

    Ties on distance are impossible in practice, so the first match is enough
    and no tiebreaker would be honest about the data anyway.
    """
    best: CoverageZone | None = None
    best_distance = math.inf
    for zone in zones:
        # A zone with no centre cannot claim any point. Skipping it is safer than
        # treating nulls as 0,0, which would silently cover the Gulf of Guinea.
        if zone.center_latitude is None or zone.center_longitude is None:
            continue
        if zone.radius_km is None:
            continue
        distance = haversine_km(
            latitude,
            longitude,
            float(zone.center_latitude),
            float(zone.center_longitude),
        )
        if distance <= float(zone.radius_km) and distance < best_distance:
            best = zone
            best_distance = distance
    return best


def zone_by_id(session: Session, zone_id: uuid.UUID) -> CoverageZone | None:
    return session.scalar(
        select(CoverageZone).where(
            CoverageZone.id == zone_id,
            CoverageZone.is_active.is_(True),
            CoverageZone.deleted_at.is_(None),
        )
    )


def zone_by_code(session: Session, code: str) -> CoverageZone | None:
    return session.scalar(
        select(CoverageZone).where(
            CoverageZone.code == code,
            CoverageZone.is_active.is_(True),
            CoverageZone.deleted_at.is_(None),
        )
    )


def zone_by_text(
    zones: list[CoverageZone], *, governorate: str | None, city: str | None
) -> CoverageZone | None:
    """Last-resort match for a typed governorate/city pair.

    Only reached when the customer supplied no coordinates. Comparison is
    case-folded and also tries the Arabic district/name, so "دمياط الجديدة"
    resolves as readily as "New Damietta".
    """
    if not governorate and not city:
        return None
    wanted = {part.casefold().strip() for part in (governorate, city) if part}
    wanted.discard("")

    # Scored rather than first-match: "دمياط" is a governorate shared by two
    # served areas, so a governorate hit must not outrank a city hit or the
    # result would depend on row order.
    best: CoverageZone | None = None
    best_score = 0
    for zone in zones:
        candidates = {
            zone.governorate.casefold().strip(): 1,
            zone.city.casefold().strip(): 2,
            (zone.district or "").casefold().strip(): 2,
            zone.name_ar.casefold().strip(): 3,
        }
        score = max(
            (candidates[part] for part in wanted if part in candidates),
            default=0,
        )
        if score > best_score:
            best = zone
            best_score = score
    return best


# ------------------------------------------------------------------ geocoding


def _pick(address: dict[str, Any], keys: tuple[str, ...]) -> str | None:
    for key in keys:
        value = address.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return None


def _to_result(
    entry: dict[str, Any], zones: list[CoverageZone]
) -> GeocodeResult | None:
    try:
        latitude = float(entry["lat"])
        longitude = float(entry["lon"])
    except (KeyError, TypeError, ValueError):
        return None

    address = entry.get("address") if isinstance(entry.get("address"), dict) else {}
    zone = zone_for_point(zones, latitude=latitude, longitude=longitude)

    return GeocodeResult(
        display_name=str(entry.get("display_name") or "").strip(),
        latitude=latitude,
        longitude=longitude,
        street=_pick(address, _ROAD_KEYS),
        district=_pick(address, _NEIGHBOURHOOD_KEYS),
        city=_pick(address, _CITY_KEYS),
        governorate=_pick(address, _REGION_KEYS),
        zone_code=zone.code if zone is not None else None,
        zone_name_ar=zone.name_ar if zone is not None else None,
    )


def search_address(session: Session, query: str) -> list[GeocodeResult]:
    """Search for an address, newest results last.

    An empty list is a legitimate answer ("no such street"), not an error, so
    the app can render "no matches" without treating it as a failure. Only a
    broken upstream is an error.
    """
    cleaned = " ".join(query.split())
    if len(cleaned) < settings.geocode_min_query_length:
        return []

    if settings.geocoder_provider == "none" or not settings.geocoder_enabled:
        raise GeocoderUnavailableError()

    cached = _cache.get(cleaned)
    if cached is not None:
        return cached

    zones = active_zones(session)
    params: dict[str, Any] = {
        "q": cleaned,
        "format": "jsonv2",
        "addressdetails": 1,
        "limit": max(1, min(settings.geocode_max_results, 10)),
    }
    if settings.geocode_country_codes:
        params["countrycodes"] = settings.geocode_country_codes

    url = f"{settings.nominatim_base_url.rstrip('/')}/search"
    try:
        _throttle()
        with httpx.Client(
            timeout=httpx.Timeout(settings.nominatim_timeout_seconds, connect=5.0)
        ) as client:
            response = client.get(
                url,
                params=params,
                headers={"User-Agent": settings.nominatim_user_agent},
            )
            response.raise_for_status()
            payload = response.json()
    except httpx.HTTPError as exc:
        raise GeocoderUnavailableError() from exc
    except ValueError as exc:
        raise GeocoderUnavailableError(
            "Address search returned an unreadable answer."
        ) from exc

    entries = payload if isinstance(payload, list) else []
    results = [
        result
        for entry in entries
        if isinstance(entry, dict)
        for result in [_to_result(entry, zones)]
        if result is not None
    ]

    _cache.put(cleaned, results)
    return results
