"""Domain exceptions and the single public error envelope (§96).

Customer-facing responses never leak SQL errors, stack traces, filesystem paths
or secrets. Every exception carries a stable machine-readable ``code``.
"""

from __future__ import annotations

from typing import Any

from fastapi import status


class DomainError(Exception):
    """Base class for all expected business failures."""

    code: str = "DOMAIN_ERROR"
    http_status: int = status.HTTP_400_BAD_REQUEST
    message: str = "The request could not be completed."

    def __init__(
        self,
        message: str | None = None,
        *,
        details: dict[str, Any] | None = None,
        code: str | None = None,
    ) -> None:
        self.message = message or self.message
        self.code = code or self.code
        self.details = details or {}
        super().__init__(self.message)

    def to_payload(self) -> dict[str, Any]:
        return {"code": self.code, "message": self.message, "details": self.details}


class NotFoundError(DomainError):
    code = "NOT_FOUND"
    http_status = status.HTTP_404_NOT_FOUND
    message = "The requested resource was not found."


class AuthenticationError(DomainError):
    code = "UNAUTHENTICATED"
    http_status = status.HTTP_401_UNAUTHORIZED
    message = "Authentication is required."


class InvalidCredentialsError(AuthenticationError):
    code = "INVALID_CREDENTIALS"
    message = "Invalid phone number or verification code."


class OtpExpiredError(DomainError):
    code = "OTP_EXPIRED"
    http_status = status.HTTP_410_GONE
    message = "The verification code has expired. Please request a new one."


class OtpAttemptsExceededError(DomainError):
    code = "OTP_ATTEMPTS_EXCEEDED"
    http_status = status.HTTP_429_TOO_MANY_REQUESTS
    message = "Too many incorrect attempts. Please request a new code."


class PermissionDeniedError(DomainError):
    code = "FORBIDDEN"
    http_status = status.HTTP_403_FORBIDDEN
    message = "You do not have permission to perform this action."


class ValidationError(DomainError):
    code = "VALIDATION_ERROR"
    # `_CONTENT` is the current Starlette name; the old `_ENTITY` spelling still
    # works but warns on every import, which buries warnings that matter.
    http_status = status.HTTP_422_UNPROCESSABLE_CONTENT
    message = "The submitted data is invalid."


class ConflictError(DomainError):
    code = "CONFLICT"
    http_status = status.HTTP_409_CONFLICT
    message = "The resource was modified by someone else. Please refresh."


class InvalidStateTransitionError(DomainError):
    code = "INVALID_STATE_TRANSITION"
    http_status = status.HTTP_409_CONFLICT
    message = "This action is not allowed for the current status."


class QuoteExpiredError(DomainError):
    code = "QUOTE_EXPIRED"
    http_status = status.HTTP_410_GONE
    message = "The current quote has expired."


class QuoteAlreadyDecidedError(DomainError):
    code = "QUOTE_ALREADY_DECIDED"
    http_status = status.HTTP_409_CONFLICT
    message = "This quote has already been accepted or rejected."


class UploadRejectedError(DomainError):
    code = "UPLOAD_REJECTED"
    http_status = status.HTTP_415_UNSUPPORTED_MEDIA_TYPE
    message = "The uploaded file was rejected."


class RateLimitedError(DomainError):
    code = "RATE_LIMITED"
    http_status = status.HTTP_429_TOO_MANY_REQUESTS
    message = "Too many requests. Please slow down."


class CoverageError(DomainError):
    code = "OUT_OF_COVERAGE"
    http_status = status.HTTP_422_UNPROCESSABLE_CONTENT
    message = "This address is outside our service coverage."


class IntegrationUnavailableError(DomainError):
    code = "INTEGRATION_UNAVAILABLE"
    http_status = status.HTTP_503_SERVICE_UNAVAILABLE
    message = "This service is temporarily unavailable."


class GeocoderUnavailableError(DomainError):
    """The address geocoder could not be reached or gave an unusable answer.

    Separate from [IntegrationUnavailableError] because the customer can act on
    it: the address they typed is fine, so the app offers a retry rather than
    asking them to change what they wrote.
    """

    code = "GEOCODER_UNAVAILABLE"
    http_status = status.HTTP_503_SERVICE_UNAVAILABLE
    message = "Address search is not available right now."