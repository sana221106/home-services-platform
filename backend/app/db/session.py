"""Engine + session management (§60, §138).

A single session per request. Multi-step authoritative operations must use
``session.begin_nested()`` or explicit transactions — see
:mod:`app.services.order_service`.

Supabase
--------
The production database is Supabase PostgreSQL reached through ``psycopg`` (v3),
which is the driver already declared in ``pyproject.toml``. Two things differ
from a local server and are handled here:

* **TLS** — Supabase terminates TLS at the proxy. ``sslmode=require`` is injected
  into the DSN when ``DATABASE_URL`` does not already carry one, so an operator
  cannot accidentally ship a plaintext connection.
* **Idle-connection reaping** — PgBouncer/SPgrow and the Supabase pooler drop
  idle sessions well before an hour. ``pool_pre_ping`` detects a socket that was
  closed while it sat idle, and ``pool_recycle`` replaces connections before the
  far end gives up on them. Without both, the first request after a quiet period
  fails with a stale-connection error.

Pool sizing is deliberately conservative: ``db_pool_size + db_max_overflow`` is
the maximum number of PostgreSQL connections one API process may open. Keep the
sum across all workers below the plan's connection limit, or use the Supabase
transaction pooler (port 6543) instead of the direct connection.
"""

from __future__ import annotations

from collections.abc import Generator, Iterator
from contextlib import contextmanager

from sqlalchemy import Engine, create_engine, event
from sqlalchemy.engine import URL, make_url
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import settings


def _with_sslmode(url: str, sslmode: str) -> str:
    """Return *url* with ``sslmode`` applied unless it already specifies one."""
    if not sslmode:
        return url
    parsed: URL = make_url(url)
    if "sslmode" in parsed.query:
        return url
    return parsed.update_query_dict({"sslmode": sslmode}).render_as_string(
        hide_password=False
    )


def build_engine_kwargs(database_url: str) -> tuple[dict[str, object], dict[str, object]]:
    """Engine and connect-args for *database_url*. Split out so tests can assert
    on the configuration without opening a connection."""
    engine_kwargs: dict[str, object] = {
        "echo": settings.sql_echo,
        "future": True,
    }
    connect_args: dict[str, object] = {}

    if database_url.startswith("sqlite"):
        # SQLite has no server-side pool to tune and rejects pool_pre_ping.
        engine_kwargs.pop("pool_pre_ping", None)
        connect_args["check_same_thread"] = False
        return engine_kwargs, connect_args

    engine_kwargs["pool_pre_ping"] = settings.db_pool_pre_ping
    engine_kwargs["pool_size"] = settings.db_pool_size
    engine_kwargs["max_overflow"] = settings.db_max_overflow
    engine_kwargs["pool_recycle"] = settings.db_pool_recycle_seconds
    engine_kwargs["pool_timeout"] = settings.db_pool_timeout_seconds
    connect_args["connect_timeout"] = settings.db_connect_timeout_seconds
    connect_args["application_name"] = settings.db_application_name
    return engine_kwargs, connect_args


_engine_kwargs, _connect_args = build_engine_kwargs(settings.database_url)
_engine_url = _with_sslmode(settings.database_url, settings.db_sslmode)

engine: Engine = create_engine(_engine_url, connect_args=_connect_args, **_engine_kwargs)


def _set_session_defaults(dbapi_connection, _record) -> None:  # noqa: ANN001
    """Pin a predictable timezone so ``timestamptz`` round-trips identically.

    Supabase defaults to UTC, but stating it removes the dependency on server
    configuration. Uses ``SET`` rather than ``SET SESSION`` so it cannot leak
    into a transaction that later rolls back.
    """
    cursor = dbapi_connection.cursor()
    try:
        cursor.execute("SET TIME ZONE 'UTC'")
        dbapi_connection.commit()
    finally:
        cursor.close()


if engine.dialect.name == "postgresql":
    event.listen(engine, "connect", _set_session_defaults)


SessionLocal = sessionmaker(
    bind=engine,
    class_=Session,
    autoflush=False,
    autocommit=False,
    expire_on_commit=False,
)


def get_db() -> Generator[Session, None, None]:
    """FastAPI dependency yielding a request-scoped session."""
    session = SessionLocal()
    try:
        yield session
    finally:
        session.close()


@contextmanager
def session_scope() -> Iterator[Session]:
    """Transactional scope for workers, scripts and tests."""
    session = SessionLocal()
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()