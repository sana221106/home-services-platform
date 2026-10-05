"""Properties and the maintenance-health record (§17, §31)."""

from __future__ import annotations

import uuid
from decimal import Decimal
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.exceptions import NotFoundError
from app.db.models.catalog import ServiceCategory
from app.db.models.intelligence import MaintenanceRecord
from app.db.models.properties import Property, PropertyContact
from app.db.models.workforce import Technician
from app.schemas.catalog import (
    CreatePropertyRequest,
    PropertyContactRequest,
    UpdatePropertyRequest,
)
from app.utils.pagination import offset_for
from app.utils.time import now_utc


def get_for_customer(
    session: Session, *, property_id: uuid.UUID, customer_id: uuid.UUID
) -> Property:
    prop = session.execute(
        select(Property).where(
            Property.id == property_id,
            Property.customer_id == customer_id,
            Property.deleted_at.is_(None),
        )
    ).scalar_one_or_none()
    if prop is None:
        raise NotFoundError("Property not found.")
    return prop


def list_for_customer(session: Session, *, customer_id: uuid.UUID) -> list[Property]:
    return list(
        session.execute(
            select(Property)
            .where(Property.customer_id == customer_id, Property.deleted_at.is_(None))
            .order_by(Property.is_default.desc(), Property.created_at.asc())
        ).scalars()
    )


def create_property(
    session: Session, *, customer_id: uuid.UUID, payload: CreatePropertyRequest
) -> Property:
    existing_default = session.execute(
        select(func.count(Property.id)).where(
            Property.customer_id == customer_id,
            Property.is_default.is_(True),
            Property.deleted_at.is_(None),
        )
    ).scalar_one()
    prop = Property(
        customer_id=customer_id,
        label=payload.label,
        property_type=payload.property_type,
        governorate=payload.governorate,
        city=payload.city,
        zone=payload.zone,
        district=payload.district,
        street=payload.street,
        building=payload.building,
        floor=payload.floor,
        apartment=payload.apartment,
        landmark=payload.landmark,
        notes=payload.notes,
        latitude=payload.latitude,
        longitude=payload.longitude,
        is_default=bool(payload.is_default or not existing_default),
    )
    session.add(prop)
    session.flush()

    if payload.contact_name:
        session.add(
            PropertyContact(
                property_id=prop.id,
                contact_name=payload.contact_name,
                phone=payload.contact_phone or "",
                relation="primary",
                is_primary=True,
            )
        )
    if prop.is_default and existing_default:
        _demote_other_defaults(session, customer_id=customer_id, keep=prop.id)
    session.flush()
    return prop


def _demote_other_defaults(
    session: Session, *, customer_id: uuid.UUID, keep: uuid.UUID
) -> None:
    for other in list_for_customer(session, customer_id=customer_id):
        if other.id != keep and other.is_default:
            other.is_default = False
    session.flush()


def update_property(
    session: Session, *, prop: Property, customer_id: uuid.UUID, payload: UpdatePropertyRequest
) -> Property:
    data = payload.model_dump(exclude_unset=True)
    contact_name = data.pop("contact_name", None)
    contact_phone = data.pop("contact_phone", None)
    for key, value in data.items():
        setattr(prop, key, value)

    if contact_name or contact_phone:
        contact = session.execute(
            select(PropertyContact).where(
                PropertyContact.property_id == prop.id, PropertyContact.is_primary.is_(True)
            )
        ).scalar_one_or_none()
        if contact is None and contact_name:
            contact = PropertyContact(property_id=prop.id, contact_name=contact_name, phone="")
            session.add(contact)
        if contact is not None:
            if contact_name:
                contact.contact_name = contact_name
            if contact_phone:
                contact.phone = contact_phone

    if payload.is_default:
        _demote_other_defaults(session, customer_id=customer_id, keep=prop.id)
    session.flush()
    return prop


def add_contact(
    session: Session, *, prop: Property, payload: PropertyContactRequest
) -> PropertyContact:
    contact = PropertyContact(
        property_id=prop.id,
        contact_name=payload.contact_name,
        phone=payload.phone,
        relation=payload.relation,
        is_primary=payload.is_primary,
    )
    session.add(contact)
    session.flush()
    return contact


def soft_delete(session: Session, *, prop: Property) -> Property:
    prop.deleted_at = now_utc()
    prop.is_default = False
    session.flush()
    return prop


# ------------------------------------------------------------------ history


def maintenance_records(
    session: Session, *, property_id: uuid.UUID, page: int = 1, per_page: int = 50
) -> tuple[list[MaintenanceRecord], int]:
    base = select(MaintenanceRecord).where(MaintenanceRecord.property_id == property_id)
    total = int(session.execute(select(func.count()).select_from(base.subquery())).scalar_one())
    rows = list(
        session.execute(
            base.order_by(MaintenanceRecord.served_on.desc())
            .offset(offset_for(page, per_page))
            .limit(per_page)
        ).scalars()
    )
    return rows, total


def recurring_issues(
    session: Session, *, property_id: uuid.UUID, minimum: int = 2
) -> list[dict[str, Any]]:
    """Group by ``recurrence_group_key``; only groups meeting ``minimum`` are
    reported, and the wording never overclaims (§18)."""
    rows = session.execute(
        select(
            MaintenanceRecord.recurrence_group_key,
            MaintenanceRecord.category_code,
            func.count(MaintenanceRecord.id).label("occurrences"),
            func.min(MaintenanceRecord.served_on).label("first_seen"),
            func.max(MaintenanceRecord.served_on).label("last_seen"),
        )
        .where(
            MaintenanceRecord.property_id == property_id,
            MaintenanceRecord.recurrence_group_key.is_not(None),
        )
        .group_by(MaintenanceRecord.recurrence_group_key, MaintenanceRecord.category_code)
        .having(func.count(MaintenanceRecord.id) >= minimum)
    ).all()

    issues: list[dict[str, Any]] = []
    for key, category_code, occurrences, first_seen, last_seen in rows:
        category = session.execute(
            select(ServiceCategory).where(ServiceCategory.code == category_code)
        ).scalar_one_or_none()
        request_ids = list(
            session.execute(
                select(MaintenanceRecord.request_id)
                .where(
                    MaintenanceRecord.recurrence_group_key == key,
                    MaintenanceRecord.property_id == property_id,
                )
                .order_by(MaintenanceRecord.served_on.desc())
            ).scalars()
        )
        count = int(occurrences)
        issues.append(
            {
                "category_code": category_code,
                "category_name_ar": category.name_ar if category else category_code,
                "occurrence_count": count,
                "first_seen_on": first_seen,
                "last_seen_on": last_seen,
                "related_request_ids": request_ids,
                "severity_note_ar": (
                    f"لاحظنا تكرارًا لهذه المشكلة ({count} مرات) في نفس العقار."
                    if count >= 3
                    else f"تم تسجيل المشكلة {count} مرات في نفس العقار."
                ),
            }
        )
    issues.sort(key=lambda item: item["occurrence_count"], reverse=True)
    return issues


def history_payload(
    session: Session, *, property_id: uuid.UUID, page: int = 1, per_page: int = 50
) -> dict[str, Any]:
    from app.db.models.requests import ServiceRequest

    prop = session.get(Property, property_id)
    records, total = maintenance_records(
        session, property_id=property_id, page=page, per_page=per_page
    )
    request_ids = [record.request_id for record in records]

    categories = {row.code: row for row in session.execute(select(ServiceCategory)).scalars()}
    request_rows = {
        row.id: row
        for row in session.execute(
            select(ServiceRequest).where(ServiceRequest.id.in_(request_ids))
        ).scalars()
    } if request_ids else {}
    technician_ids = {record.technician_id for record in records if record.technician_id}
    technicians = (
        {
            row.id: row
            for row in session.execute(
                select(Technician).where(Technician.id.in_(technician_ids))
            ).scalars()
        }
        if technician_ids
        else {}
    )

    items: list[dict[str, Any]] = []
    total_spent = Decimal("0.00")
    completed_count = 0
    for record in records:
        category = categories.get(record.category_code)
        request_row = request_rows.get(record.request_id)
        if record.price is not None and record.is_completed:
            total_spent += Decimal(record.price)
        if record.is_completed:
            completed_count += 1
        items.append(
            {
                "request_id": record.request_id,
                "reference_code": request_row.reference_code if request_row else "",
                "category_code": record.category_code,
                "category_name_ar": category.name_ar if category else record.category_code,
                "category_icon_key": category.icon_key if category else "wrench",
                "category_color_hex": category.color_hex if category else "#2557D6",
                "problem_code": record.problem_code,
                "customer_description": record.customer_description,
                "diagnosis": record.diagnosis,
                "resolution": record.resolution,
                "price": record.price,
                "materials_summary": record.materials_summary,
                "media": list(record.media_references or []),
                "served_on": record.served_on,
                "had_complaint": record.had_complaint,
                "had_rework": record.had_rework,
                "is_completed": record.is_completed,
                "recurrence_index": record.recurrence_index,
                "technician_internal_label": (
                    technicians[record.technician_id].name
                    if record.technician_id in technicians
                    else None
                ),
            }
        )

    return {
        "property_id": property_id,
        "property_label": prop.label if prop else "",
        "total_records": total,
        "completed_count": completed_count,
        "total_spent": total_spent,
        "items": items,
        "recurring_issues": recurring_issues(session, property_id=property_id),
        "last_service_on": max((record.served_on for record in records), default=None),
        "next_recommended_service_on": None,
    }
