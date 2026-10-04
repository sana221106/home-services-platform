"""FastAPI application factory (§110, §135)."""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi.errors import RateLimitExceeded
from sqlalchemy import text

from app.api.v1.router import api_router
from app.core.config import settings
from app.core.exceptions import DomainError
from app.core.logging import configure_logging, get_logger
from app.core.rate_limit import limiter, rate_limit_exceeded_handler
from app.db.session import engine
from app.schemas.common import ErrorResponse, HealthResponse
from app.utils.time import now_utc

DESCRIPTION = """
Backend for the Home Services managed platform.

The API is the single authority for pricing, payment state, technician
assignment, quote versioning and complaint handling. The mobile client and the
admin dashboard both go through this API — neither writes business data
directly.
"""

log = get_logger(__name__)


@asynccontextmanager
async def lifespan(_app: FastAPI) -> AsyncIterator[None]:
    configure_logging()
    # Refuse to serve production traffic with a dev secret, a plaintext DSN or
    # a second identity provider switched on (§135).
    settings.assert_production_safe()
    log.info(
        "startup",
        environment=settings.environment,
        version=settings.app_version,
        supabase_configured=settings.supabase_configured,
        supabase_auth_enabled=settings.supabase_auth_enabled,
    )
    yield
    log.info("shutdown")


def create_app() -> FastAPI:
    app = FastAPI(
        title=settings.app_name,
        version=settings.app_version,
        description=DESCRIPTION,
        lifespan=lifespan,
        docs_url="/docs" if not settings.is_production else None,
        redoc_url=None,
        openapi_url="/openapi.json",
        responses={
            400: {"model": ErrorResponse},
            401: {"model": ErrorResponse},
            403: {"model": ErrorResponse},
            404: {"model": ErrorResponse},
            409: {"model": ErrorResponse},
            422: {"model": ErrorResponse},
            429: {"model": ErrorResponse},
        },
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_allow_origins,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PATCH", "PUT", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "X-Correlation-ID"],
    )

    app.state.limiter = limiter
    app.add_exception_handler(RateLimitExceeded, rate_limit_exceeded_handler)

    @app.middleware("http")
    async def correlation_id_middleware(request: Request, call_next):  # noqa: ANN001, ANN202
        correlation_id = request.headers.get("X-Correlation-ID") or ""
        request.state.correlation_id = correlation_id
        response = await call_next(request)
        if correlation_id:
            response.headers["X-Correlation-ID"] = correlation_id
        return response

    @app.exception_handler(DomainError)
    async def domain_error_handler(_request: Request, exc: DomainError) -> JSONResponse:
        return JSONResponse(
            status_code=exc.http_status,
            content=exc.to_payload(),
            headers=(
                {"Retry-After": str(exc.details["retry_after_seconds"])}
                if exc.code == "RATE_LIMITED" and "retry_after_seconds" in exc.details
                else None
            ),
        )

    @app.exception_handler(RequestValidationError)
    async def validation_handler(
        _request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        return JSONResponse(
            status_code=422,
            content={
                "code": "VALIDATION_ERROR",
                "message": "The request payload is invalid.",
                "details": {"errors": exc.errors()[:10]},
            },
        )

    @app.get(
        "/health",
        response_model=HealthResponse,
        tags=["system"],
        summary="Liveness probe (no infrastructure detail)",
    )
    def health() -> HealthResponse:
        return HealthResponse(
            status="ok",
            service=settings.app_name,
            environment=settings.environment,
            version=settings.app_version,
            time=now_utc(),
        )

    @app.get(
        "/health/ready",
        response_model=HealthResponse,
        tags=["system"],
        summary="Readiness probe (checks the database)",
    )
    def readiness() -> HealthResponse:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
        return HealthResponse(
            status="ok",
            service=settings.app_name,
            environment=settings.environment,
            version=settings.app_version,
            time=now_utc(),
        )

    app.include_router(api_router, prefix=settings.api_v1_prefix)
    return app


app = create_app()

__all__ = ["app", "create_app"]
