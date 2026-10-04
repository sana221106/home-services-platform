"""Regression tests for ``.env`` parsing of list-typed settings (§87).

pydantic-settings JSON-decodes a complex-typed environment variable *before* any
``mode="before"`` validator runs. Without :class:`NoDecode`, a perfectly ordinary

    CORS_ALLOW_ORIGINS=*

aborts startup with::

    SettingsError: error parsing value for field "cors_allow_origins"

because ``*`` is not valid JSON. The comma-separated forms of
``ALLOWED_IMAGE_MIMES`` fail the same way.

These tests build ``Settings`` against a real temporary ``.env`` file rather than
passing ``_env_file=`` overrides, so they exercise the same code path as an
operator's environment.
"""

from __future__ import annotations

import os
from pathlib import Path

import pytest
from pydantic import ValidationError
from pydantic_settings import SettingsError

from app.core.config import Settings

pytestmark = pytest.mark.filterwarnings("ignore::DeprecationWarning")

BASE = """
ENVIRONMENT=development
JWT_SECRET=a-real-random-secret-value-for-tests-only
DATABASE_URL=postgresql+psycopg://postgres:secret@db.example.supabase.co:5432/postgres?sslmode=require
"""


def write_env(tmp_path: Path, *extra: str) -> Path:
    env = tmp_path / ".env"
    env.write_text(BASE + "".join(f"{line}\n" for line in extra), encoding="utf-8")
    return env


def load(tmp_path: Path, *extra: str) -> Settings:
    """Build Settings the way the app does, with no ambient env interference."""
    saved = {k: os.environ.pop(k, None) for k in ("CORS_ALLOW_ORIGINS", "ALLOWED_IMAGE_MIMES")}
    try:
        return Settings(_env_file=write_env(tmp_path, *extra))
    finally:
        for key, value in saved.items():
            if value is not None:
                os.environ[key] = value


# ------------------------------------------------------- the regression itself


def test_cors_star_does_not_crash_startup(tmp_path: Path) -> None:
    """The shipped default must be loadable from an env file.

    This is the exact failure that broke boot: `CORS_ALLOW_ORIGINS=*` raised
    SettingsError before the app could serve a single request.
    """
    settings = load(tmp_path, "CORS_ALLOW_ORIGINS=*")
    assert settings.cors_allow_origins == ["*"]


def test_cors_comma_separated(tmp_path: Path) -> None:
    settings = load(tmp_path, "CORS_ALLOW_ORIGINS=http://a.test,http://b.test")
    assert settings.cors_allow_origins == ["http://a.test", "http://b.test"]


def test_cors_single_origin(tmp_path: Path) -> None:
    settings = load(tmp_path, "CORS_ALLOW_ORIGINS=https://app.example.com")
    assert settings.cors_allow_origins == ["https://app.example.com"]


def test_cors_whitespace_is_trimmed(tmp_path: Path) -> None:
    settings = load(tmp_path, "CORS_ALLOW_ORIGINS= http://a.test , http://b.test ")
    assert settings.cors_allow_origins == ["http://a.test", "http://b.test"]


def test_cors_omitted_falls_back_to_the_default(tmp_path: Path) -> None:
    settings = load(tmp_path)
    assert settings.cors_allow_origins == ["*"]


# --------------------------------------------------------- allowed_image_mimes


def test_image_mimes_comma_separated(tmp_path: Path) -> None:
    settings = load(tmp_path, "ALLOWED_IMAGE_MIMES=image/png,image/webp")
    assert settings.allowed_image_mimes == frozenset({"image/png", "image/webp"})


def test_image_mimes_single_value(tmp_path: Path) -> None:
    settings = load(tmp_path, "ALLOWED_IMAGE_MIMES=image/jpeg")
    assert settings.allowed_image_mimes == frozenset({"image/jpeg"})


def test_image_mimes_default_is_the_platform_set(tmp_path: Path) -> None:
    settings = load(tmp_path)
    assert settings.allowed_image_mimes == frozenset(
        {"image/jpeg", "image/png", "image/webp"}
    )


def test_image_mimes_keep_the_upload_limit_consistent(tmp_path: Path) -> None:
    """A narrowed MIME list must not silently change the documented size cap."""
    settings = load(tmp_path, "ALLOWED_IMAGE_MIMES=image/png")
    assert settings.max_upload_bytes == 12 * 1024 * 1024


# ------------------------------------------------------------------- edge cases


def test_empty_cors_value_yields_an_empty_list(tmp_path: Path) -> None:
    """An explicitly empty value means "no origins", not "all origins"."""
    settings = load(tmp_path, "CORS_ALLOW_ORIGINS=")
    assert settings.cors_allow_origins == []


def test_shipped_example_env_is_loadable() -> None:
    """`.env.example` must parse, or every new setup breaks on first run."""
    example = Path(__file__).resolve().parents[2] / ".env.example"
    assert example.is_file(), ".env.example is missing from the repository"
    saved = {
        k: os.environ.pop(k, None)
        for k in ("CORS_ALLOW_ORIGINS", "ALLOWED_IMAGE_MIMES", "ENVIRONMENT")
    }
    try:
        # placeholders only: assert_production_safe would reject them, so this
        # deliberately does not call it.
        settings = Settings(_env_file=example)
    finally:
        for key, value in saved.items():
            if value is not None:
                os.environ[key] = value
    assert settings.cors_allow_origins, "example file produced no CORS origins"
    assert settings.allowed_image_mimes, "example file produced no MIME allow-list"


def test_tests_are_hermetic_despite_a_real_env_file() -> None:
    """conftest must neutralise Supabase so ``backend/.env`` cannot reach live buckets.

    Regression: with a populated SUPABASE_URL and service-role key in the
    developer's env file, ``make_storage_client()`` returned the real adapter
    and 14 media tests tried to upload to private production buckets. ``conftest``
    has already run by the time this executes, so the assertion is simply that
    its neutralisation took effect.
    """
    if os.environ.get("SUPABASE_LIVE_STORAGE_TEST", "").lower() in {"1", "true", "yes"}:
        pytest.skip("live storage mode is enabled by design")

    from app.core.config import settings

    assert not settings.supabase_configured, (
        "the test suite must run without Supabase credentials"
    )
    assert not settings.supabase_url, "conftest did not clear SUPABASE_URL"

    from app.services.media_service import make_storage_client

    assert make_storage_client().provider == "local"


def test_a_genuinely_invalid_scalar_still_raises(tmp_path: Path) -> None:
    """NoDecode must not have disabled validation in general.

    Scalar fields are unaffected by ``NoDecode``; a non-numeric int still fails
    at construction time rather than silently defaulting.
    """
    with pytest.raises((SettingsError, ValidationError)):
        load(tmp_path, "MAX_UPLOAD_BYTES=not-a-number")


def test_a_genuinely_invalid_environment_still_raises(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """``conftest`` exports ENVIRONMENT=test, and os.environ outranks any .env file,
    so the bogus value has to be injected into the process environment."""
    monkeypatch.setenv("ENVIRONMENT", "productionn")
    with pytest.raises((SettingsError, ValidationError)):
        Settings(_env_file=None)