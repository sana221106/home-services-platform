"""Configuration hygiene: ``.env.example`` must stay safe and truthful (§12).

Two failure modes are guarded here:

* a real credential leaking into a committed file, and
* the template drifting away from :class:`~app.core.config.Settings`, so an
  operator follows a variable name the application does not read.

These are cheap, offline checks that run in the normal suite.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from app.core.config import Settings

pytestmark = pytest.mark.filterwarnings("ignore::DeprecationWarning")

REPO_ROOT = Path(__file__).resolve().parents[2]
ENV_EXAMPLE = REPO_ROOT / ".env.example"


def _example_text() -> str:
    assert ENV_EXAMPLE.is_file(), ".env.example is missing from the repository"
    return ENV_EXAMPLE.read_text(encoding="utf-8")


def _keys() -> list[str]:
    return re.findall(r"^([A-Z][A-Z0-9_]*)\s*=", _example_text(), flags=re.MULTILINE)


# ------------------------------------------------------------------ present


def test_env_example_exists() -> None:
    assert ENV_EXAMPLE.is_file()


def test_env_example_is_tracked_and_env_is_ignored() -> None:
    ignore = (REPO_ROOT / ".gitignore").read_text(encoding="utf-8")
    assert re.search(r"^\.env$", ignore, flags=re.MULTILINE)
    assert re.search(r"^\!\.env\.example$", ignore, flags=re.MULTILINE)


# ------------------------------------------------------------------- safe


def test_no_real_looking_secrets() -> None:
    """Everything credential-shaped must still be an obvious placeholder."""
    text = _example_text()
    for marker in (
        "SUPABASE_SERVICE_ROLE_KEY=",
        "SUPABASE_PUBLISHABLE_KEY=",
        "SUPABASE_ANON_KEY=",
    ):
        line = next(row for row in text.splitlines() if row.startswith(marker))
        value = line.split("=", 1)[1].strip()
        assert value == "", f"{marker} must ship empty, found {value!r}"

    for key in ("JWT_SECRET", "SEED_ADMIN_PASSWORD", "AI_API_KEY"):
        line = next(row for row in text.splitlines() if row.startswith(key))
        value = line.split("=", 1)[1].strip().strip('"')
        assert not value or "CHANGE_ME" in value or "{" in value, (
            f"{key} must be a placeholder, found {value!r}"
        )


def test_service_role_key_is_never_given_a_value() -> None:
    """The single most dangerous credential must not appear with content."""
    text = _example_text()
    for line in text.splitlines():
        if "service_role" in line.lower() and "=" in line and not line.startswith("#"):
            assert line.split("=", 1)[1].strip() == ""


def test_database_url_has_no_real_password() -> None:
    line = next(
        row for row in _example_text().splitlines() if row.startswith("DATABASE_URL=")
    )
    assert "CHANGE_ME" in line
    assert "YOUR_PROJECT_REF" in line or "CHANGE_ME" in line


def test_supabase_auth_stays_disabled() -> None:
    assert "SUPABASE_AUTH_ENABLED=false" in _example_text()


def test_storage_is_not_configured_for_public_access() -> None:
    assert "STORAGE_PUBLIC_BASE_URL=\n" in _example_text() + "\n"


# --------------------------------------------------------------- truthful


def test_every_example_key_is_a_real_setting() -> None:
    """No documented variable may be silently ignored by pydantic-settings.

    ``BaseSettings`` maps environment variables to fields case-insensitively, so
    the comparison is done in lower case.
    """
    fields = {name.lower() for name in Settings.model_fields}
    unknown = sorted(k for k in _keys() if k.lower() not in fields)
    assert not unknown, f"not read by Settings: {unknown}"


def test_required_settings_are_documented() -> None:
    keys = set(_keys())
    for required in (
        "DATABASE_URL",
        "SUPABASE_URL",
        "SUPABASE_SERVICE_ROLE_KEY",
        "SUPABASE_AUTH_ENABLED",
        "JWT_SECRET",
    ):
        assert required in keys, f"{required} missing from .env.example"


def test_pool_settings_documented() -> None:
    keys = set(_keys())
    assert {"DB_POOL_SIZE", "DB_MAX_OVERFLOW", "DB_POOL_PRE_PING"} <= keys


def test_supabase_sslmode_documented() -> None:
    """Supabase requires TLS; the template must not model a plaintext DSN."""
    assert "sslmode=require" in _example_text()


@pytest.mark.parametrize("prefix", ["request-media", "chat-media", "payment-proofs", "complaint-media"])
def test_private_bucket_names_documented(prefix: str) -> None:
    assert prefix in _example_text()