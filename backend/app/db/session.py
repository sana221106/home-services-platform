"""Engine + session management (§60, §138).

A single session per request. Multi-step authoritative operations must use
``session.begin_nested()`` or explicit transactions — see
:mod:`app.services.order_service`.
"""

from __future__ import annotations

from collections.abc import Generator, Iterator
from contextlib import contextmanager

from sqlalchemy import Engine, create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import settings

_connect_args: dict[str, object] = {}
_engine_kwargs: dict[str, object] = {
    "echo": settings.sql_echo,
    "pool_pre_ping": settings.db_pool_pre_ping,
    "future": True,
}

if settings.database_url.startswith("sqlite"):
    _engine_kwargs.pop("pool_pre_ping")
    _connect_args["check_same_thread"] = False
else:
    _engine_kwargs["pool_size"] = settings.db_pool_size
    _engine_kwargs["max_overflow"] = settings.db_max_overflow

engine: Engine = create_engine(
    settings.database_url, connect_args=_connect_args, **_engine_kwargs
)

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