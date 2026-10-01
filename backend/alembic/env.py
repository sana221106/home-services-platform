"""Alembic environment (§60).

The database URL always comes from :class:`app.core.config.Settings` so there is
exactly one place that knows how to reach the database. ``render_as_batch`` is
enabled so migrations also work against SQLite in local/CI runs.
"""

from __future__ import annotations

from logging.config import fileConfig

from alembic import context
from sqlalchemy import engine_from_config, pool

from app.core.config import settings
from app.db.base import Base

# The model registry must be imported so every table is attached to
# Base.metadata before autogenerate runs.
import app.db.models  # noqa: E402,F401

config = context.config
config.set_main_option("sqlalchemy.url", settings.database_url)

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def render_item(type_: str, obj: object, autogen_context: object) -> str | bool:
    """Render *project* column types as importable, fully-qualified expressions.

    Only top-level column types declared inside this package are rewritten.
    Constructor arguments (e.g. ``JSONB(astext_type=Text())``) must keep
    Alembic's own rendering, or we would emit unimportable bare names.
    """
    if type_ != "type":
        return False
    cls = obj if isinstance(obj, type) else type(obj)
    module = getattr(cls, "__module__", "")
    if not module.startswith("app."):
        return False
    return f"{module}.{getattr(cls, '__qualname__', cls.__name__)}()"


def run_migrations_offline() -> None:
    context.configure(
        url=settings.database_url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
        compare_server_default=True,
        render_item=render_item,
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            compare_type=True,
            compare_server_default=True,
            render_item=render_item,
            render_as_batch=connection.dialect.name == "sqlite",
        )
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
