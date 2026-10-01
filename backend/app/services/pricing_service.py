"""Server-authoritative pricing (§8, §12, §120).

Flutter receives an estimate for display only. The figure sent to the customer
is always produced here from :class:`PricingRule` rows and, when a quote exists,
from the accepted quote revision.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta
from decimal import ROUND_HALF_UP, Decimal

from sqlalchemy import and_, or_, select
from sqlalchemy.orm import Session

from app.core.enums import Urgency
from app.db.models.catalog import CancellationPolicy, PricingRule
from app.utils.time import now_utc

TWO_PLACES = Decimal("0.01")
HUNDRED = Decimal("100")

# Client-supplied urgency is only ever a *hint*. The monetary effect is resolved
# server-side here, then combined with the zone-specific ``PricingRule`` in
# :func:`calculate_estimate`.
URGENCY_MULTIPLIERS: dict[Urgency, Decimal] = {
    Urgency.NORMAL: Decimal("1.00"),
    Urgency.URGENT: Decimal("1.60"),
}
URGENCY_FLAT_FEES: dict[Urgency, Decimal] = {
    Urgency.NORMAL: Decimal("0"),
    Urgency.URGENT: Decimal("50.00"),
}


def urgency_multiplier_for(urgency: Urgency | str | None) -> Decimal:
    if urgency is None:
        return URGENCY_MULTIPLIERS[Urgency.NORMAL]
    try:
        return URGENCY_MULTIPLIERS[Urgency(urgency)]
    except ValueError:
        return URGENCY_MULTIPLIERS[Urgency.NORMAL]


def urgency_flat_fee_for(urgency: Urgency | str | None) -> Decimal:
    if urgency is None:
        return URGENCY_FLAT_FEES[Urgency.NORMAL]
    try:
        return URGENCY_FLAT_FEES[Urgency(urgency)]
    except ValueError:
        return URGENCY_FLAT_FEES[Urgency.NORMAL]


def _q(value: Decimal) -> Decimal:
    return value.quantize(TWO_PLACES, rounding=ROUND_HALF_UP)


def resolve_pricing_rule(
    session: Session,
    *,
    category_id: uuid.UUID,
    problem_type_id: uuid.UUID | None = None,
    zone_id: uuid.UUID | None = None,
    at: datetime | None = None,
) -> PricingRule | None:
    """Most specific active rule wins: problem+zone > problem > category+zone >
    category. Ties resolve to the newest ``valid_from``."""
    moment = at or now_utc()
    candidates: list[PricingRule] = list(
        session.execute(
            select(PricingRule)
            .where(
                PricingRule.category_id == category_id,
                PricingRule.is_active.is_(True),
                PricingRule.valid_from <= moment,
                or_(PricingRule.valid_to.is_(None), PricingRule.valid_to > moment),
            )
            .order_by(PricingRule.valid_from.desc())
        ).scalars()
    )
    if not candidates:
        return None

    def specificity(rule: PricingRule) -> tuple[int, datetime]:
        score = 0
        if rule.problem_type_id is not None and rule.problem_type_id == problem_type_id:
            score += 2
        if rule.zone_id is not None and zone_id is not None and rule.zone_id == zone_id:
            score += 1
        return score, rule.valid_from

    matches = [rule for rule in candidates if specificity(rule)[0] > 0 or rule.problem_type_id is None]
    if not matches:
        return candidates[0]
    return max(matches, key=specificity)


def calculate_estimate(
    session: Session,
    *,
    category_id: uuid.UUID,
    problem_type_id: uuid.UUID | None = None,
    zone_id: uuid.UUID | None = None,
    urgency_multiplier: Decimal = Decimal("1.00"),
    urgent_flat_fee: Decimal = Decimal("0"),
    inspection_only: bool = False,
    at: datetime | None = None,
) -> dict[str, Decimal | int | uuid.UUID | None]:
    """Compute the platform-side estimate. Never trust client-supplied totals."""
    rule = resolve_pricing_rule(
        session,
        category_id=category_id,
        problem_type_id=problem_type_id,
        zone_id=zone_id,
        at=at,
    )
    if rule is None:
        return {
            "service_cost": Decimal("0.00"),
            "materials_cost": Decimal("0.00"),
            "urgency_fee": Decimal("0.00"),
            "inspection_fee": Decimal("0.00"),
            "deposit_percent": Decimal("0.00"),
            "estimated_duration_minutes": 120,
            "matched_rule_id": None,
        }

    multiplier = Decimal(urgency_multiplier) * Decimal(rule.urgency_multiplier or Decimal("1"))
    service_cost = Decimal(rule.base_service_cost)
    urgency_fee = _q(service_cost * (multiplier - Decimal("1"))) + Decimal(urgent_flat_fee)
    inspection_fee = Decimal(rule.inspection_fee) if inspection_only else Decimal("0")

    return {
        "service_cost": _q(service_cost),
        "materials_cost": _q(Decimal(rule.materials_cost)),
        "urgency_fee": _q(urgency_fee),
        "inspection_fee": _q(inspection_fee),
        "deposit_percent": Decimal(rule.deposit_percent),
        "estimated_duration_minutes": int(rule.estimated_duration_minutes),
        "matched_rule_id": rule.id,
    }


def calculate_quote_totals(
    *,
    service_cost: Decimal,
    materials_cost: Decimal,
    urgency_fee: Decimal,
    inspection_fee: Decimal,
    discount: Decimal,
    deposit_percent: Decimal,
) -> dict[str, Decimal]:
    """Totals are always recomputed server-side; submitted totals are ignored."""
    subtotal = _q(
        Decimal(service_cost)
        + Decimal(materials_cost)
        + Decimal(urgency_fee)
        + Decimal(inspection_fee)
    )
    capped_discount = min(_q(Decimal(discount)), subtotal) if subtotal > 0 else Decimal("0.00")
    total = _q(subtotal - capped_discount)
    deposit = _q(total * (Decimal(deposit_percent) / HUNDRED))
    return {
        "subtotal": subtotal,
        "discount": capped_discount,
        "total": total,
        "deposit_amount": deposit,
    }


def deposit_required(total: Decimal, deposit_percent: Decimal) -> bool:
    return Decimal(deposit_percent) > 0 and _q(Decimal(total) * (Decimal(deposit_percent) / HUNDRED)) > 0


def resolve_cancellation_policy(
    session: Session, *, minutes_since_booking: int
) -> CancellationPolicy | None:
    """Longest window that the booking still falls inside wins."""
    policies = list(
        session.execute(
            select(CancellationPolicy)
            .where(
                CancellationPolicy.is_active.is_(True),
                CancellationPolicy.window_minutes >= minutes_since_booking,
            )
            .order_by(CancellationPolicy.window_minutes.asc())
        ).scalars()
    )
    return policies[0] if policies else None


def next_expiry(hours: int) -> datetime:
    return now_utc() + timedelta(hours=hours)


def rules_effective_at(
    session: Session, *, at: datetime
) -> list[PricingRule]:
    return list(
        session.execute(
            select(PricingRule).where(
                PricingRule.is_active.is_(True),
                PricingRule.valid_from <= at,
                and_(or_(PricingRule.valid_to.is_(None), PricingRule.valid_to > at)),
            )
        ).scalars()
    )