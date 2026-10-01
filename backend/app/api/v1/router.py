"""API v1 aggregate router."""

from __future__ import annotations

from fastapi import APIRouter

from app.api.v1.endpoints import (
    analytics,
    auth,
    customer,
    media,
    orders,
    payments,
    properties,
    requests,
    services,
    staff_auth,
    staff_directory,
    staff_finance,
    staff_requests,
    staff_support,
    support,
)

api_router = APIRouter()

# Customer-facing surface
api_router.include_router(auth.router)
api_router.include_router(services.router)
api_router.include_router(properties.router)
api_router.include_router(requests.router)
api_router.include_router(orders.router)
api_router.include_router(payments.router)
api_router.include_router(support.router)
api_router.include_router(customer.router)
api_router.include_router(media.router)

# Staff / operations surface
api_router.include_router(staff_auth.router)
api_router.include_router(staff_requests.router)
api_router.include_router(staff_finance.router)
api_router.include_router(staff_support.router)
api_router.include_router(staff_directory.router)
api_router.include_router(analytics.router)

__all__ = ["api_router"]
