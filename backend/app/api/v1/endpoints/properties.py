"""Properties and maintenance history (§31, §17)."""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Query

from app.api.dependencies import CurrentCustomer, DbSession
from app.schemas.catalog import (
    CreatePropertyRequest,
    PropertyContactRequest,
    PropertyContactResponse,
    PropertyHistoryResponse,
    PropertyResponse,
    UpdatePropertyRequest,
)
from app.schemas.common import MessageResponse
from app.services import property_service

router = APIRouter(prefix="/properties", tags=["properties"])


def _response(prop) -> PropertyResponse:  # noqa: ANN001 - Property
    return PropertyResponse(
        id=prop.id,
        label=prop.label,
        property_type=prop.property_type,
        governorate=prop.governorate,
        city=prop.city,
        zone=prop.zone,
        district=prop.district,
        street=prop.street,
        building=prop.building,
        floor=prop.floor,
        apartment=prop.apartment,
        landmark=prop.landmark,
        notes=prop.notes,
        latitude=prop.latitude,
        longitude=prop.longitude,
        is_default=prop.is_default,
        created_at=prop.created_at,
        contacts=[PropertyContactResponse.model_validate(c) for c in prop.contacts],
    )


@router.get("", response_model=list[PropertyResponse], summary="Customer properties")
def list_properties(db: DbSession, customer: CurrentCustomer) -> list[PropertyResponse]:
    return [_response(prop) for prop in property_service.list_for_customer(
        db, customer_id=customer.profile.id
    )]


@router.post(
    "",
    response_model=PropertyResponse,
    status_code=201,
    summary="Create a property",
)
def create_property(
    payload: CreatePropertyRequest, db: DbSession, customer: CurrentCustomer
) -> PropertyResponse:
    prop = property_service.create_property(
        db, customer_id=customer.profile.id, payload=payload
    )
    db.commit()
    db.refresh(prop)
    return _response(prop)


@router.get("/{property_id}", response_model=PropertyResponse, summary="Property detail")
def get_property(
    property_id: uuid.UUID, db: DbSession, customer: CurrentCustomer
) -> PropertyResponse:
    prop = property_service.get_for_customer(
        db, property_id=property_id, customer_id=customer.profile.id
    )
    return _response(prop)


@router.patch("/{property_id}", response_model=PropertyResponse, summary="Update a property")
def update_property(
    property_id: uuid.UUID,
    payload: UpdatePropertyRequest,
    db: DbSession,
    customer: CurrentCustomer,
) -> PropertyResponse:
    prop = property_service.get_for_customer(
        db, property_id=property_id, customer_id=customer.profile.id
    )
    property_service.update_property(
        db, prop=prop, customer_id=customer.profile.id, payload=payload
    )
    db.commit()
    db.refresh(prop)
    return _response(prop)


@router.post(
    "/{property_id}/contacts",
    response_model=PropertyContactResponse,
    status_code=201,
    summary="Add a site contact",
)
def add_contact(
    property_id: uuid.UUID,
    payload: PropertyContactRequest,
    db: DbSession,
    customer: CurrentCustomer,
) -> PropertyContactResponse:
    prop = property_service.get_for_customer(
        db, property_id=property_id, customer_id=customer.profile.id
    )
    contact = property_service.add_contact(db, prop=prop, payload=payload)
    db.commit()
    return PropertyContactResponse.model_validate(contact)


@router.delete(
    "/{property_id}", response_model=MessageResponse, summary="Archive a property"
)
def delete_property(
    property_id: uuid.UUID, db: DbSession, customer: CurrentCustomer
) -> MessageResponse:
    prop = property_service.get_for_customer(
        db, property_id=property_id, customer_id=customer.profile.id
    )
    property_service.soft_delete(db, prop=prop)
    db.commit()
    return MessageResponse(message="تم حذف العقار.")


@router.get(
    "/{property_id}/history",
    response_model=PropertyHistoryResponse,
    summary="Maintenance health record for a property",
)
def property_history(
    property_id: uuid.UUID,
    db: DbSession,
    customer: CurrentCustomer,
    page: int = Query(default=1, ge=1),
    per_page: int = Query(default=50, ge=1, le=200),
) -> PropertyHistoryResponse:
    property_service.get_for_customer(
        db, property_id=property_id, customer_id=customer.profile.id
    )
    payload = property_service.history_payload(
        db, property_id=property_id, page=page, per_page=per_page
    )
    return PropertyHistoryResponse(**payload)
