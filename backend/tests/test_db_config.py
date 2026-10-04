"""Database engine configuration for Supabase (§60, §138).

Asserts the pooling and TLS decisions in :mod:`app.db.session` without opening
a connection, so a misconfigured production DSN is caught in CI rather than on
the first request after a deploy.
"""

from __future__ import annotations

import pytest

from app.core.config import Settings
from app.db.session import _with_sslmode, build_engine_kwargs

pytestmark = pytest.mark.filterwarnings("ignore::DeprecationWarning")

SUPABASE_URL = (
    "postgresql+psycopg://postgres:secret@db.abcdefgh.supabase.co:5432/postgres?sslmode=require"
)


# --------------------------------------------------------------------- TLS


def test_sslmode_is_not_duplicated_when_url_already_has_it() -> None:
    assert "sslmode=require" in _with_sslmode(SUPABASE_URL, "require")
    assert _with_sslmode(SUPABASE_URL, "require").count("sslmode") == 1


def test_sslmode_is_injected_when_url_omits_it() -> None:
    bare = "postgresql+psycopg://postgres:secret@db.abcdefgh.supabase.co:5432/postgres"
    assert _with_sslmode(bare, "require").endswith("sslmode=require")


def test_sslmode_absent_is_left_alone() -> None:
    """An empty DB_SSLMODE must not fabricate a parameter."""
    bare = "postgresql+psycopg://postgres:secret@localhost:5432/home_services"
    assert _with_sslmode(bare, "") == bare


def test_password_survives_sslmode_injection() -> None:
    bare = "postgresql+psycopg://postgres:p%40ssw0rd@db.abcdefgh.supabase.co:5432/postgres"
    result = _with_sslmode(bare, "require")
    assert "p%40ssw0rd" in result
    assert "sslmode=require" in result


# ------------------------------------------------------------------ pooling


def test_postgres_gets_a_tuned_pool() -> None:
    engine_kwargs, connect_args = build_engine_kwargs(SUPABASE_URL)
    assert engine_kwargs["pool_pre_ping"] is True
    assert engine_kwargs["pool_size"] >= 1
    assert engine_kwargs["max_overflow"] >= 0
    assert engine_kwargs["pool_recycle"] > 0
    assert engine_kwargs["pool_timeout"] > 0
    assert connect_args["connect_timeout"] > 0


def test_pool_totals_stay_within_a_sane_range() -> None:
    """A runaway pool would exhaust the plan's connection limit."""
    engine_kwargs, _ = build_engine_kwargs(SUPABASE_URL)
    total = int(engine_kwargs["pool_size"]) + int(engine_kwargs["max_overflow"])
    assert total <= 100, "pool size + overflow is unreasonably large"


def test_application_name_is_reported() -> None:
    _, connect_args = build_engine_kwargs(SUPABASE_URL)
    assert connect_args["application_name"]


def test_sqlite_is_left_on_default_pooling() -> None:
    """SQLite rejects pool_pre_ping, so it must not be passed."""
    engine_kwargs, connect_args = build_engine_kwargs("sqlite+pysqlite:///./x.db")
    assert "pool_pre_ping" not in engine_kwargs
    assert "pool_size" not in engine_kwargs
    assert connect_args["check_same_thread"] is False


# --------------------------------------------------------- production guard


def _production_settings(**overrides) -> Settings:
    base = {
        "environment": "production",
        "jwt_secret": "a-real-random-secret-value-for-tests-only",
        "database_url": SUPABASE_URL,
        "supabase_auth_enabled": False,
    }
    base.update(overrides)
    return Settings(_env_file=None, **base)


def test_production_config_with_sslmode_passes() -> None:
    _production_settings().assert_production_safe()


def test_production_refuses_default_jwt_secret() -> None:
    settings = _production_settings(jwt_secret="dev-only-insecure-secret-change-me")
    with pytest.raises(RuntimeError, match="JWT_SECRET"):
        settings.assert_production_safe()


def test_production_refuses_plaintext_dsn() -> None:
    settings = _production_settings(
        database_url="postgresql+psycopg://postgres:secret@db.abcdefgh.supabase.co:5432/postgres"
    )
    with pytest.raises(RuntimeError, match="sslmode"):
        settings.assert_production_safe()


def test_production_refuses_passwordless_dsn() -> None:
    settings = _production_settings(
        database_url="postgresql+psycopg://db.abcdefgh.supabase.co:5432/postgres?sslmode=require"
    )
    with pytest.raises(RuntimeError, match="password"):
        settings.assert_production_safe()


def test_production_refuses_wrong_driver() -> None:
    settings = _production_settings(
        database_url="postgresql://postgres:secret@db.abcdefgh.supabase.co:5432/postgres?sslmode=require"
    )
    with pytest.raises(RuntimeError, match="psycopg"):
        settings.assert_production_safe()


def test_production_refuses_supabase_auth() -> None:
    """Enabling a second identity provider is an architectural error."""
    settings = _production_settings(supabase_auth_enabled=True)
    with pytest.raises(RuntimeError, match="SUPABASE_AUTH_ENABLED"):
        settings.assert_production_safe()


def test_development_never_blocks_on_those_checks() -> None:
    """Local work must not be gated on production hygiene."""
    Settings(
        _env_file=None,
        environment="development",
        jwt_secret="dev-only-insecure-secret-change-me",
    ).assert_production_safe()


def test_supabase_auth_defaults_to_disabled() -> None:
    assert Settings(_env_file=None).supabase_auth_enabled is False