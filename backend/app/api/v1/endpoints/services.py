"""Service catalogue and problem types (§70)."""

from __future__ import annotations

import uuid

from fastapi import APIRouter, HTTPException, Query
from sqlalchemy import select

from app.api.dependencies import CurrentCustomer, DbSession
from app.db.models.catalog import ProblemType, ServiceCategory
from app.schemas.catalog import (
    CoverageZoneResponse,
    GeocodeResult,
    PaymentMethodOption,
    ProblemTypeResponse,
    ServiceCategoryResponse,
    ServiceCategoryWithProblems,
)
from app.services import geocoding_service

router = APIRouter(tags=["catalogue"])

PAYMENT_METHODS = [
    PaymentMethodOption(
        code="CASH",
        label_ar="نقدًا عند الإنجاز",
        instructions_ar="ادفع نقدًا للفني بعد التأكد من إنجاز الخدمة.",
        requires_proof=False,
    ),
    PaymentMethodOption(
        code="VODAFONE_CASH",
        label_ar="فودافون كاش",
        instructions_ar="حوّل المبلغ ثم أدخل رقم العملية في خانة الرقم المرجعي.",
        requires_proof=True,
    ),
    PaymentMethodOption(
        code="INSTAPAY",
        label_ar="إنستا باي",
        instructions_ar="حوّل المبلغ من تطبيق إنستا باي ثم أدخل رقم العملية.",
        requires_proof=True,
    ),
]


@router.get(
    "/services",
    response_model=list[ServiceCategoryResponse],
    summary="Active service categories",
)
def list_services(db: DbSession, _customer: CurrentCustomer) -> list[ServiceCategoryResponse]:
    rows = session_categories(db)
    return [ServiceCategoryResponse.model_validate(row) for row in rows]


def session_categories(db: DbSession):
    return list(
        db.execute(
            select(ServiceCategory)
            .where(
                ServiceCategory.is_active.is_(True),
                ServiceCategory.deleted_at.is_(None),
            )
            .order_by(ServiceCategory.sort_order.asc())
        )
        .scalars()
    )


@router.get(
    "/services/{service_id}/problems",
    response_model=list[ProblemTypeResponse],
    summary="Problem types for a category",
)
def list_problems(
    service_id: uuid.UUID, db: DbSession, _customer: CurrentCustomer
) -> list[ProblemTypeResponse]:
    rows = db.execute(
        select(ProblemType)
        .where(
            ProblemType.category_id == service_id,
            ProblemType.is_active.is_(True),
            ProblemType.deleted_at.is_(None),
        )
        .order_by(ProblemType.sort_order.asc())
    ).scalars()
    return [ProblemTypeResponse.model_validate(row) for row in rows]


@router.get(
    "/catalogue",
    response_model=list[ServiceCategoryWithProblems],
    summary="Categories with their problem types in one round trip",
)
def full_catalogue(db: DbSession, _customer: CurrentCustomer) -> list[ServiceCategoryWithProblems]:
    categories = session_categories(db)
    if not categories:
        return []
    problems = list(
        db.execute(
            select(ProblemType)
            .where(
                ProblemType.category_id.in_([category.id for category in categories]),
                ProblemType.is_active.is_(True),
                ProblemType.deleted_at.is_(None),
            )
            .order_by(ProblemType.sort_order.asc())
        )
        .scalars()
    )
    grouped: dict[uuid.UUID, list[ProblemTypeResponse]] = {}
    for problem in problems:
        grouped.setdefault(problem.category_id, []).append(
            ProblemTypeResponse.model_validate(problem)
        )
    return [
        ServiceCategoryWithProblems(
            **ServiceCategoryResponse.model_validate(category).model_dump(),
            problems=grouped.get(category.id, []),
        )
        for category in categories
    ]


@router.get(
    "/payment-methods",
    response_model=list[PaymentMethodOption],
    summary="Configured payment methods",
)
def payment_methods(_customer: CurrentCustomer) -> list[PaymentMethodOption]:
    return PAYMENT_METHODS


@router.get(
    "/coverage-zones",
    response_model=list[CoverageZoneResponse],
    summary="Areas currently served",
)
def list_coverage_zones(
    db: DbSession, _customer: CurrentCustomer
) -> list[CoverageZoneResponse]:
    """The served areas, so the address form can offer a choice.

    The customer types the rest of the address in free Arabic text; only the
    area is a fixed value, because that is what decides whether a request can be
    accepted at all (§29).
    """
    return geocoding_service.list_coverage_zones(db)


@router.get(
    "/address-search",
    response_model=list[GeocodeResult],
    summary="Search an address",
)
def search_address(
    db: DbSession,
    _customer: CurrentCustomer,
    q: str = Query(min_length=2, max_length=200, description="Address text"),
) -> list[GeocodeResult]:
    """Turns typed address text into a point plus the area it falls in.

    Each hit carries the coverage zone it matched, so the app can fill the form
    in one tap and warn about an unserved address before submit.
    """
    return geocoding_service.search_address(db, q)


@router.get("/problems/{problem_id}", response_model=ProblemTypeResponse, summary="One problem type")
def get_problem(
    problem_id: uuid.UUID, db: DbSession, _customer: CurrentCustomer
) -> ProblemTypeResponse:
    row = db.get(ProblemType, problem_id)
    if row is None or not row.is_active:
        raise HTTPException(status_code=404, detail={"code": "NOT_FOUND", "message": "Not found."})
    return ProblemTypeResponse.model_validate(row)

