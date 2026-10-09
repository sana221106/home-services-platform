"""Email provider routing and Gmail delivery, with every Google call mocked."""

from __future__ import annotations

import base64
import json
import logging
from email import policy
from email.parser import BytesParser
from pathlib import Path
from unittest.mock import MagicMock
from urllib.parse import parse_qs

import httpx
import pytest
from fastapi.testclient import TestClient
from pydantic import SecretStr, ValidationError
from sqlalchemy.orm import Session
from structlog.testing import CapturingLogger

from app.core.config import Settings, settings
from app.core.exceptions import IntegrationUnavailableError
from app.db.models import OtpDeliveryLog, User
from app.services import auth_service, email_service, gmail_service

TOKEN_URL = "https://oauth2.googleapis.com/token"
SEND_URL = "https://gmail.googleapis.com/gmail/v1/users/me/messages/send"
CLIENT_ID = "test-client-id"
CLIENT_SECRET = "test-client-secret"
REFRESH_TOKEN = "test-refresh-token"
ACCESS_TOKEN = "test-access-token-one"
NEW_ACCESS_TOKEN = "test-access-token-two"
RECIPIENT = "customer@example.com"
CODE = "839241"
TTL = 9
PRIVATE_TEXT = f"{CLIENT_SECRET} {REFRESH_TOKEN} {ACCESS_TOKEN} {CODE} {RECIPIENT}"


def _token(token: str = ACCESS_TOKEN, *, expires_in: int = 3600) -> httpx.Response:
    return httpx.Response(200, json={"access_token": token, "expires_in": expires_in})


def _sent() -> httpx.Response:
    return httpx.Response(200, json={"id": "test-message-id"})


class GoogleHTTP:
    def __init__(self) -> None:
        self.requests: list[httpx.Request] = []
        self.responses: list[httpx.Response | httpx.RequestError] = []
        self.client_options: list[dict[str, object]] = []
        self.log = CapturingLogger()
        self.smtp = MagicMock(side_effect=AssertionError("SMTP must not be called"))

    def handle(self, request: httpx.Request) -> httpx.Response:
        assert request.method == "POST"
        assert str(request.url) in {TOKEN_URL, SEND_URL}
        self.requests.append(request)
        assert self.responses, "Unexpected extra request or retry"
        response = self.responses.pop(0)
        if isinstance(response, httpx.RequestError):
            raise response
        return response


@pytest.fixture(autouse=True)
def google_http(monkeypatch: pytest.MonkeyPatch) -> GoogleHTTP:
    """No real SMTP/Google calls, even if a test forgets to queue a response."""
    stub = GoogleHTTP()
    monkeypatch.setattr(settings, "email_otp_provider", "gmail_api")
    monkeypatch.setattr(settings, "gmail_client_id", CLIENT_ID)
    monkeypatch.setattr(settings, "gmail_client_secret", SecretStr(CLIENT_SECRET))
    monkeypatch.setattr(settings, "gmail_refresh_token", SecretStr(REFRESH_TOKEN))
    monkeypatch.setattr(settings, "gmail_sender_email", "sender@example.com")
    monkeypatch.setattr(settings, "gmail_sender_name", "Home Services")
    monkeypatch.setattr(settings, "otp_ttl_minutes", TTL)
    monkeypatch.setattr(settings, "smtp_host", "smtp.example.com")
    monkeypatch.setattr(settings, "debug", False)
    monkeypatch.setattr(gmail_service, "_access_token", None)
    monkeypatch.setattr(gmail_service, "_expires_at", 0.0)
    monkeypatch.setattr(gmail_service, "log", stub.log)
    monkeypatch.setattr(email_service, "log", stub.log)
    monkeypatch.setattr(email_service.smtplib, "SMTP", stub.smtp)
    original_client = httpx.Client

    def make_client(**kwargs: object) -> httpx.Client:
        stub.client_options.append(kwargs)
        return original_client(transport=httpx.MockTransport(stub.handle), **kwargs)

    monkeypatch.setattr(gmail_service.httpx, "Client", make_client)
    return stub


def _send() -> None:
    email_service.send_verification_code(RECIPIENT, code=CODE, ttl_minutes=TTL)


def _message(request: httpx.Request):
    raw = json.loads(request.content)["raw"]
    assert "=" not in raw, "Gmail payload should be unpadded base64url"
    assert "+" not in raw and "/" not in raw
    decoded = base64.urlsafe_b64decode(raw + "=" * (-len(raw) % 4))
    return BytesParser(policy=policy.default).parsebytes(decoded)


def test_gmail_api_routing_bypasses_smtp(google_http: GoogleHTTP) -> None:
    google_http.responses.extend([_token(), _sent()])

    assert _send() is None

    assert [str(request.url) for request in google_http.requests] == [TOKEN_URL, SEND_URL]
    google_http.smtp.assert_not_called()
    assert google_http.client_options == [{"timeout": 15.0, "follow_redirects": False}]


def test_oauth_refresh_grant_and_gmail_authorization(google_http: GoogleHTTP) -> None:
    google_http.responses.extend([_token(), _sent()])
    _send()

    refresh, send = google_http.requests
    assert refresh.headers["Content-Type"] == "application/x-www-form-urlencoded"
    assert parse_qs(refresh.content.decode()) == {
        "client_id": [CLIENT_ID],
        "client_secret": [CLIENT_SECRET],
        "refresh_token": [REFRESH_TOKEN],
        "grant_type": ["refresh_token"],
    }
    assert "Authorization" not in refresh.headers
    assert send.headers["Authorization"] == f"Bearer {ACCESS_TOKEN}"
    assert send.headers["Content-Type"] == "application/json"
    assert set(json.loads(send.content)) == {"raw"}


def test_gmail_mime_sender_recipient_subject_otp_and_ttl(google_http: GoogleHTTP) -> None:
    google_http.responses.extend([_token(), _sent()])
    _send()

    message = _message(google_http.requests[1])
    assert message["From"] == "Home Services <sender@example.com>"
    assert message["To"] == RECIPIENT
    assert message["Subject"] == "Home Services Verification Code"
    assert message.get_content_type() == "text/plain"
    assert message.get_content() == (
        "Your Home Services verification code is:\n\n"
        f"{CODE}\n\n"
        f"This code expires in {TTL} minutes.\n\n"
        "If you did not request this code, you can ignore this email.\n"
    )


def test_access_token_is_cached_between_sends(google_http: GoogleHTTP) -> None:
    google_http.responses.extend([_token(), _sent(), _sent()])
    _send()
    _send()

    assert [str(request.url) for request in google_http.requests] == [TOKEN_URL, SEND_URL, SEND_URL]
    assert google_http.requests[-1].headers["Authorization"] == f"Bearer {ACCESS_TOKEN}"


def test_cached_token_refreshes_one_minute_before_expiry(
    google_http: GoogleHTTP, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(gmail_service, "monotonic", lambda: 100.0)
    google_http.responses.extend([_token(expires_in=120), _sent(), _token(NEW_ACCESS_TOKEN), _sent()])
    _send()
    monkeypatch.setattr(gmail_service, "monotonic", lambda: 161.0)
    _send()

    assert [str(request.url) for request in google_http.requests] == [TOKEN_URL, SEND_URL] * 2
    assert google_http.requests[-1].headers["Authorization"] == f"Bearer {NEW_ACCESS_TOKEN}"


def test_gmail_401_refreshes_and_retries_once(google_http: GoogleHTTP) -> None:
    google_http.responses.extend([_token(), httpx.Response(401), _token(NEW_ACCESS_TOKEN), _sent()])
    _send()

    assert [str(request.url) for request in google_http.requests] == [TOKEN_URL, SEND_URL] * 2
    first_send, retry = google_http.requests[1], google_http.requests[3]
    assert first_send.headers["Authorization"] == f"Bearer {ACCESS_TOKEN}"
    assert retry.headers["Authorization"] == f"Bearer {NEW_ACCESS_TOKEN}"
    assert first_send.content == retry.content, "Retry must carry the same OTP"
    google_http.smtp.assert_not_called()


def test_repeated_401_stops_after_one_retry_and_discards_token(google_http: GoogleHTTP) -> None:
    google_http.responses.extend(
        [_token(), httpx.Response(401), _token(NEW_ACCESS_TOKEN), httpx.Response(401)]
    )
    with pytest.raises(IntegrationUnavailableError):
        _send()

    assert len(google_http.requests) == 4
    assert gmail_service._access_token is None
    assert gmail_service._expires_at == 0.0


def test_oauth_failure_after_401_does_not_retry_send(google_http: GoogleHTTP) -> None:
    google_http.responses.extend([_token(), httpx.Response(401), httpx.Response(400)])
    with pytest.raises(IntegrationUnavailableError):
        _send()

    assert [str(request.url) for request in google_http.requests] == [TOKEN_URL, SEND_URL, TOKEN_URL]


@pytest.mark.parametrize("status_code", [400, 403, 429, 500, 503])
def test_gmail_http_failure_is_safe_and_not_retried(
    google_http: GoogleHTTP, status_code: int
) -> None:
    google_http.responses.extend([_token(), httpx.Response(status_code, text=PRIVATE_TEXT)])
    with pytest.raises(IntegrationUnavailableError) as exc:
        _send()

    assert exc.value.http_status == 503
    assert exc.value.details == {}
    assert PRIVATE_TEXT not in str(exc.value)
    assert len(google_http.requests) == 2
    assert google_http.log.calls[-1].kwargs == {
        "provider": "gmail_api",
        "email_masked": "c***@example.com",
        "status_code": status_code,
        "safe_error_reason": "gmail_send_failed",
    }


@pytest.mark.parametrize("status_code", [400, 401, 403, 429, 500])
def test_oauth_failure_never_attempts_gmail_send(
    google_http: GoogleHTTP, status_code: int
) -> None:
    google_http.responses.append(httpx.Response(status_code, text=PRIVATE_TEXT))
    with pytest.raises(IntegrationUnavailableError):
        _send()

    assert [str(request.url) for request in google_http.requests] == [TOKEN_URL]
    assert google_http.log.calls[-1].kwargs["safe_error_reason"] == "oauth_refresh_failed"


@pytest.mark.parametrize(
    "payload",
    [
        [],
        {},
        {"access_token": "", "expires_in": 3600},
        {"access_token": ACCESS_TOKEN, "expires_in": 0},
        {"access_token": ACCESS_TOKEN, "expires_in": "invalid"},
        {"access_token": ACCESS_TOKEN, "expires_in": True},
    ],
)
def test_invalid_oauth_payload_fails_safely(google_http: GoogleHTTP, payload: object) -> None:
    google_http.responses.append(httpx.Response(200, json=payload))
    with pytest.raises(IntegrationUnavailableError):
        _send()
    assert len(google_http.requests) == 1
    assert gmail_service._access_token is None


def test_non_json_oauth_response_fails_safely(google_http: GoogleHTTP) -> None:
    google_http.responses.append(httpx.Response(200, text=PRIVATE_TEXT))
    with pytest.raises(IntegrationUnavailableError):
        _send()
    assert len(google_http.requests) == 1


@pytest.mark.parametrize("stage", ["oauth", "send"])
@pytest.mark.parametrize("error_type", [httpx.ReadTimeout, httpx.ConnectError])
def test_timeout_or_network_failure_is_safe(
    google_http: GoogleHTTP, stage: str, error_type: type[httpx.RequestError]
) -> None:
    if stage == "send":
        google_http.responses.append(_token())
    google_http.responses.append(error_type(PRIVATE_TEXT))
    with pytest.raises(IntegrationUnavailableError) as exc:
        _send()

    assert exc.value.http_status == 503
    assert PRIVATE_TEXT not in str(exc.value)
    assert len(google_http.requests) == (2 if stage == "send" else 1)
    assert google_http.log.calls[-1].kwargs["safe_error_reason"] == (
        "timeout" if error_type is httpx.ReadTimeout else "network_error"
    )


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("gmail_client_id", ""),
        ("gmail_client_secret", None),
        ("gmail_client_secret", SecretStr("")),
        ("gmail_refresh_token", None),
        ("gmail_refresh_token", SecretStr("")),
        ("gmail_sender_email", ""),
    ],
)
def test_missing_gmail_config_never_falls_back_to_smtp_or_log_only(
    google_http: GoogleHTTP, monkeypatch: pytest.MonkeyPatch, field: str, value: object
) -> None:
    monkeypatch.setattr(settings, field, value)
    assert not settings.email_configured
    with pytest.raises(IntegrationUnavailableError):
        _send()
    assert google_http.requests == []
    google_http.smtp.assert_not_called()


@pytest.mark.parametrize("outcome", ["success", "oauth_error", "send_error", "network_error"])
def test_no_secrets_tokens_authorization_or_otp_in_gmail_logs(
    google_http: GoogleHTTP,
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
    outcome: str,
) -> None:
    monkeypatch.setattr(settings, "environment", "production")
    monkeypatch.setattr(settings, "debug", True)
    caplog.set_level(logging.DEBUG)
    if outcome == "success":
        google_http.responses.extend([_token(), _sent()])
        _send()
    else:
        failure = httpx.Response(400, text=f"Authorization: Bearer {PRIVATE_TEXT}")
        if outcome == "oauth_error":
            google_http.responses.append(failure)
        elif outcome == "send_error":
            google_http.responses.extend([_token(), failure])
        else:
            google_http.responses.extend([_token(), httpx.ConnectError(PRIVATE_TEXT)])
        with pytest.raises(IntegrationUnavailableError):
            _send()

    # Check raw structured events before redaction as well as HTTP library logs.
    logs = repr(google_http.log.calls) + caplog.text
    for private in [CLIENT_SECRET, REFRESH_TOKEN, ACCESS_TOKEN, CODE, RECIPIENT, "Authorization", "Bearer"]:
        assert private not in logs
    assert "c***@example.com" in logs
    assert "otp_email_sent" in logs if outcome == "success" else "otp_email_failed" in logs


def test_smtp_provider_retains_existing_delivery(
    google_http: GoogleHTTP, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(settings, "email_otp_provider", "smtp")
    monkeypatch.setattr(settings, "smtp_user", "smtp-user@example.com")
    monkeypatch.setattr(settings, "smtp_password", SecretStr("smtp-test-password"))
    monkeypatch.setattr(settings, "smtp_starttls", True)
    google_http.smtp.side_effect = None
    _send()

    smtp = google_http.smtp.return_value.__enter__.return_value
    google_http.smtp.assert_called_once_with(
        "smtp.example.com", settings.smtp_port, timeout=settings.smtp_timeout_seconds
    )
    smtp.starttls.assert_called_once_with()
    smtp.login.assert_called_once_with("smtp-user@example.com", "smtp-test-password")
    smtp.send_message.assert_called_once()
    message = smtp.send_message.call_args.args[0]
    assert message["To"] == RECIPIENT
    assert CODE in message.get_content()
    assert google_http.requests == []


@pytest.mark.parametrize("environment", ["development", "production"])
def test_log_only_provider_only_logs_otp_in_development(
    google_http: GoogleHTTP, monkeypatch: pytest.MonkeyPatch, environment: str
) -> None:
    monkeypatch.setattr(settings, "email_otp_provider", "log_only")
    monkeypatch.setattr(settings, "environment", environment)
    monkeypatch.setattr(settings, "debug", True)
    _send()

    logs = repr(google_http.log.calls)
    assert (CODE in logs) == (environment == "development")
    assert "c***@example.com" in logs
    assert not settings.email_configured
    assert google_http.requests == []
    google_http.smtp.assert_not_called()


def test_unconfigured_smtp_keeps_log_only_fallback(
    google_http: GoogleHTTP, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(settings, "email_otp_provider", "smtp")
    monkeypatch.setattr(settings, "smtp_host", "")
    _send()

    assert google_http.log.calls[-1].args == ("otp_email_unconfigured",)
    assert google_http.requests == []
    google_http.smtp.assert_not_called()


def test_settings_read_gmail_environment_and_hide_secrets(monkeypatch: pytest.MonkeyPatch) -> None:
    for key, value in {
        "EMAIL_OTP_PROVIDER": "gmail_api",
        "GMAIL_CLIENT_ID": CLIENT_ID,
        "GMAIL_CLIENT_SECRET": CLIENT_SECRET,
        "GMAIL_REFRESH_TOKEN": REFRESH_TOKEN,
        "GMAIL_SENDER_EMAIL": "sender@example.com",
        "GMAIL_SENDER_NAME": "Home Services",
    }.items():
        monkeypatch.setenv(key, value)
    configured = Settings(_env_file=None)

    assert configured.email_otp_provider == "gmail_api"
    assert configured.email_configured
    assert configured.gmail_client_id == CLIENT_ID
    assert isinstance(configured.gmail_client_secret, SecretStr)
    assert isinstance(configured.gmail_refresh_token, SecretStr)
    assert configured.gmail_client_secret.get_secret_value() == CLIENT_SECRET
    assert configured.gmail_refresh_token.get_secret_value() == REFRESH_TOKEN
    assert configured.gmail_sender_email == "sender@example.com"
    assert configured.gmail_sender_name == "Home Services"
    assert CLIENT_SECRET not in repr(configured)
    assert REFRESH_TOKEN not in configured.model_dump_json()


def test_settings_reject_unknown_email_provider(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("EMAIL_OTP_PROVIDER", "typo")
    with pytest.raises(ValidationError):
        Settings(_env_file=None)


def test_root_env_example_has_empty_gmail_credentials() -> None:
    text = (Path(__file__).resolve().parents[2] / ".env.example").read_text(encoding="utf-8")
    for key in ["GMAIL_CLIENT_ID", "GMAIL_CLIENT_SECRET", "GMAIL_REFRESH_TOKEN", "GMAIL_SENDER_EMAIL"]:
        assert f"{key}=\n" in text
    assert "EMAIL_OTP_PROVIDER=gmail_api\n" in text


def test_otp_endpoint_uses_gmail_and_configured_ttl(
    client: TestClient, db: Session, google_http: GoogleHTTP, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(auth_service, "generate_otp", lambda: CODE)
    monkeypatch.setattr(settings, "smtp_host", "")
    google_http.responses.extend([_token(), _sent()])
    response = client.post("/api/v1/auth/request-otp", json={"email": RECIPIENT})

    assert response.status_code == 202
    assert response.json()["expires_in_seconds"] == TTL * 60
    assert "code" not in response.json()
    assert CODE not in response.text
    assert f"expires in {TTL} minutes" in _message(google_http.requests[1]).get_content()
    delivery = db.query(OtpDeliveryLog).one()
    assert delivery.provider == "gmail_api"
    assert delivery.delivered is True
    assert delivery.destination_masked == "c***@example.com"
    assert db.query(User).filter(User.email == RECIPIENT).one().phone is None
    google_http.smtp.assert_not_called()

    verified = client.post("/api/v1/auth/verify-otp", json={"email": RECIPIENT, "code": CODE})
    assert verified.status_code == 200
    assert verified.json()["tokens"]["access_token"]


@pytest.mark.parametrize("failure", ["oauth", "send", "timeout", "missing_config"])
def test_gmail_failure_propagates_to_otp_endpoint_without_delivery_success(
    client: TestClient,
    db: Session,
    google_http: GoogleHTTP,
    monkeypatch: pytest.MonkeyPatch,
    failure: str,
) -> None:
    monkeypatch.setattr(auth_service, "generate_otp", lambda: CODE)
    if failure == "oauth":
        google_http.responses.append(httpx.Response(400, text=PRIVATE_TEXT))
    elif failure == "send":
        google_http.responses.extend([_token(), httpx.Response(403, text=PRIVATE_TEXT)])
    elif failure == "timeout":
        google_http.responses.append(httpx.ReadTimeout(PRIVATE_TEXT))
    else:
        monkeypatch.setattr(settings, "gmail_refresh_token", None)

    response = client.post("/api/v1/auth/request-otp", json={"email": RECIPIENT})
    assert response.status_code == 503
    assert response.json() == {
        "code": "INTEGRATION_UNAVAILABLE",
        "message": "Sending the verification email failed. Please try again.",
        "details": {},
    }
    for private in [CLIENT_SECRET, REFRESH_TOKEN, ACCESS_TOKEN, CODE, RECIPIENT]:
        assert private not in response.text
    assert db.query(OtpDeliveryLog).count() == 0
    google_http.smtp.assert_not_called()
