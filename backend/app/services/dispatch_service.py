"""Internal technician dispatch (§9, §125).

Dispatch is entirely an operations concern. The customer never sees a
technician identity beyond a first name, and V1 never exposes live location
(§10). Assignment scoring considers skill, zone, availability, current workload
and the working shift.
"""

from __future__ import annotations

import uuid
from datetime import date, datetime, time, timedelta
from typing import Any

from sqlalchemy import Select, func, select
from sqlalchemy.orm import Session, selectinload

from app.core.enums import AssignmentStatus, RequestStatus, TechnicianStatus
from app.core.exceptions import ConflictError, ValidationError
from app.core.logging import get_logger
from app.db.models.catalog import ServiceAreaSnapshot
from app.db.models.requests import ServiceRequest
from app.db.models.workforce import (
    Assignment,
    Technician,
    TechnicianAvailability,
    TechnicianSkill,
    TechnicianZone,
)
from app.utils.time import now_utc

log = get_logger(__name__)

#: Relative weights for candidate ranking.
WEIGHT_SKILL = 50
WEIGHT_ZONE = 30
WEIGHT_AVAILABILITY = 15
WEIGHT_CAPACITY = 15
ON_TIME_BONUS = 10


def _within_shift(
    availability: list[TechnicianAvailability],
    *,
    target: datetime,
    weekday: int,
) -> bool:
    same_day = [
        entry
        for entry in availability
        if entry.weekday == weekday and (entry.date is None or entry.date == target.date())
    ]
    if not same_day:
        return False
    for entry in same_day:
        if not entry.is_available:
            return False
        if entry.start_time <= target.timetz().replace(tzinfo=None) <= entry.end_time:
            return True
    return False


def _current_workload(session: Session, *, technician_id: uuid.UUID, at: datetime) -> int:
    return int(
        session.execute(
            select(func.count(Assignment.id)).where(
                Assignment.technician_id == technician_id,
                Assignment.status.in_(
                    [
                        AssignmentStatus.ASSIGNED,
                        AssignmentStatus.EN_ROUTE,
                        AssignmentStatus.ARRIVED,
                        AssignmentStatus.IN_PROGRESS,
                    ]
                ),
            )
        ).scalar_one()
        or 0
    )


def _daily_capacity(availability: list[TechnicianAvailability], *, weekday: int) -> int:
    same_day = [entry for entry in availability if entry.weekday == weekday]
    if not same_day:
        return 0
    return max(entry.max_daily_assignments for entry in same_day)


def score_candidates(
    session: Session,
    *,
    request: ServiceRequest,
    target_start: datetime,
    limit: int = 20,
) -> list[dict[str, Any]]:
    """Rank technicians for one request. Returns operator-facing data only."""
    # The area was resolved once at creation and stored on the area snapshot.
    # Matching the typed governorate and city here would fail for the same reason
    # the request was nearly rejected: those are free Arabic text (§30).
    area = session.execute(
        select(ServiceAreaSnapshot).where(
            ServiceAreaSnapshot.request_id == request.id
        )
    ).scalar_one_or_none()
    zone_id = area.zone_id if area is not None else None

    stmt: Select[tuple[Technician]] = (
        select(Technician)
        .options(
            selectinload(Technician.skills),
            selectinload(Technician.zones),
            selectinload(Technician.shifts),
        )
        .join(TechnicianSkill, TechnicianSkill.technician_id == Technician.id)
        .where(
            Technician.active.is_(True),
            Technician.status == TechnicianStatus.ACTIVE,
            TechnicianSkill.category_id == request.category_id,
        )
    )
    if zone_id is not None:
        stmt = stmt.join(
            TechnicianZone,
            (TechnicianZone.technician_id == Technician.id) & (TechnicianZone.zone_id == zone_id),
        )

    technicians = list(session.execute(stmt).unique().scalars())
    weekday = target_start.weekday()
    results: list[dict[str, Any]] = []

    for technician in technicians:
        has_zone = any(zone.zone_id == zone_id for zone in technician.zones) if zone_id else bool(
            technician.zones
        )
        on_shift = _within_shift(technician.shifts, target=target_start, weekday=weekday)
        workload = _current_workload(session, technician_id=technician.id, at=now_utc())
        capacity = _daily_capacity(technician.shifts, weekday=weekday)
        has_room = capacity == 0 or workload < capacity

        score = WEIGHT_SKILL
        score += WEIGHT_ZONE if has_zone else 0
        score += WEIGHT_AVAILABILITY if on_shift else 0
        score += WEIGHT_CAPACITY if has_room else 0
        if technician.late_arrivals == 0 and technician.no_show_count == 0:
            score += ON_TIME_BONUS

        results.append(
            {
                "id": technician.id,
                "name": technician.name,
                "active": technician.active,
                "status": technician.status.value,
                "matched_skills": [
                    skill.category_id for skill in technician.skills
                ],
                "matched_zones": [zone_.zone_id for zone_ in technician.zones],
                "current_workload": workload,
                "next_free_at": target_start + timedelta(hours=workload * 2),
                "is_available": bool(on_shift and has_room),
                "score": score,
            }
        )

    results.sort(key=lambda item: (item["is_available"], item["score"]), reverse=True)
    return results[:limit]


def find_assignment(session: Session, *, request_id: uuid.UUID) -> Assignment | None:
    return session.execute(
        select(Assignment)
        .where(Assignment.request_id == request_id, Assignment.is_current.is_(True))
        .order_by(Assignment.assigned_at.desc())
        .limit(1)
    ).scalar_one_or_none()


def is_technician_double_booked(
    session: Session,
    *,
    technician_id: uuid.UUID,
    start: datetime,
    end: datetime,
    exclude_request_id: uuid.UUID | None = None,
) -> bool:
    """Overlapping-window guard so two operators cannot double-assign (§140)."""
    stmt = select(func.count(Assignment.id)).where(
        Assignment.technician_id == technician_id,
        Assignment.is_current.is_(True),
        Assignment.status.in_(
            [
                AssignmentStatus.ASSIGNED,
                AssignmentStatus.EN_ROUTE,
                AssignmentStatus.ARRIVED,
                AssignmentStatus.IN_PROGRESS,
            ]
        ),
        Assignment.expected_arrival_start.is_not(None),
        Assignment.expected_arrival_start <= end,
        Assignment.expected_arrival_end.is_not(None),
        Assignment.expected_arrival_end >= start,
    )
    if exclude_request_id is not None:
        stmt = stmt.where(Assignment.request_id != exclude_request_id)
    return int(session.execute(stmt).scalar_one() or 0) > 0


def assert_assignable(session: Session, *, request: ServiceRequest, technician_id: uuid.UUID) -> Technician:
    if request.status not in {
        RequestStatus.CONFIRMED,
        RequestStatus.TECHNICIAN_ASSIGNMENT_PENDING,
        RequestStatus.TECHNICIAN_ASSIGNED,
        RequestStatus.INSPECTION_SCHEDULED,
    }:
        raise ConflictError(
            "A technician cannot be assigned while the request is in its current status.",
            code="INVALID_STATE_TRANSITION",
            details={"status": request.status.value},
        )

    technician = session.get(Technician, technician_id)
    if technician is None:
        raise ValidationError("Unknown technician.")
    if not technician.active or technician.status != TechnicianStatus.ACTIVE:
        raise ValidationError("This technician is not currently available.")

    has_skill = session.execute(
        select(func.count(TechnicianSkill.id)).where(
            TechnicianSkill.technician_id == technician_id,
            TechnicianSkill.category_id == request.category_id,
        )
    ).scalar_one()
    if not has_skill:
        raise ValidationError("This technician does not cover the requested service category.")
    return technician


def technician_first_name(name: str) -> str:
    """Only the first token is ever surfaced to the customer (§9, §10)."""
    parts = name.strip().split()
    return parts[0] if parts else "فريق الخدمة"


def shift_window_for(*, target: datetime, duration_minutes: int) -> tuple[datetime, datetime]:
    start = target.replace(second=0, microsecond=0)
    return start, start + timedelta(minutes=max(30, duration_minutes))


def time_window_label(start: datetime, end: datetime) -> str:
    def fmt(value: datetime) -> str:
        return value.strftime("%I:%M %p").lstrip("0")

    return f"{fmt(start)} - {fmt(end)}"


def is_within_shift(availability: list[TechnicianAvailability], *, target: datetime) -> bool:
    return _within_shift(availability, target=target, weekday=target.weekday())


def default_shift_for(weekday: int) -> tuple[time, time]:
    """Company default shift used when a technician has no explicit shift row."""
    if weekday in (4, 5):  # Friday, Saturday
        return time(9, 0), time(17, 0)
    return time(9, 0), time(19, 0)


def today() -> date:
    return now_utc().date()
