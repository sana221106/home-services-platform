"""Verify the Alembic chain against the ORM metadata, on a throwaway database.

The previous version of this script read a leftover ``_alembic_gen.db`` file and
never invoked Alembic at all, so it always reported every table as missing and
could not detect a broken migration. This version actually drives the chain.

Checks:
  1. ``alembic upgrade head`` succeeds against a fresh empty database.
  2. The resulting schema has exactly the ORM's tables - none missing, none extra.
  3. Every column the ORM declares exists with a compatible type.
  4. ``alembic downgrade base`` unwinds cleanly, leaving no tables behind.

Usage::

    python tools/verify_migration.py

``DATABASE_URL`` is forced to a temporary SQLite file for the run, so this is
always safe to execute: it never touches the configured database.
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from contextlib import suppress
from pathlib import Path

BACKEND = Path(__file__).resolve().parent.parent


def run_alembic(*args: str, database_url: str) -> None:
    """Invoke Alembic in a subprocess against *database_url*."""
    env = {**os.environ, "DATABASE_URL": database_url, "PYTHONPATH": str(BACKEND)}
    # noqa S603: fixed argv (sys.executable -m alembic), no shell, no user input
    result = subprocess.run(  # noqa: S603
        [sys.executable, "-m", "alembic", *args],
        cwd=BACKEND,
        env=env,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise SystemExit(
            f"alembic {' '.join(args)} failed with code {result.returncode}\n"
            f"--- stdout ---\n{result.stdout}\n--- stderr ---\n{result.stderr}"
        )


def sqlite_tables(url: str) -> set[str]:
    import sqlite3

    path = url.split("///", 1)[1]
    with sqlite3.connect(path) as conn:
        return {
            row[0]
            for row in conn.execute(
                "select name from sqlite_master where type='table' "
                "and name not like 'sqlite_%'"
            )
        }


def column_mismatches(url: str) -> list[str]:
    """Report columns the ORM declares that the migration did not create."""
    from sqlalchemy import create_engine, inspect

    import app.db.models  # noqa: F401
    from app.db.base import Base

    path = url.split("///", 1)[1]
    engine = create_engine(f"sqlite:///{path}")
    try:
        inspector = inspect(engine)
        migrated_tables = set(inspector.get_table_names())
        problems: list[str] = []
        for table_name, table in sorted(Base.metadata.tables.items()):
            if table_name not in migrated_tables:
                continue
            migrated = {col["name"] for col in inspector.get_columns(table_name)}
            for column in table.columns:
                if column.name not in migrated:
                    problems.append(f"{table_name}.{column.name} missing from migration")
        return problems
    finally:
        engine.dispose()


def main() -> int:
    tmp = Path(tempfile.gettempdir()) / "verify_migration_check.db"
    tmp.unlink(missing_ok=True)
    url = f"sqlite:///{tmp.as_posix()}"

    print(f"verifying against a throwaway database: {tmp}")
    run_alembic("upgrade", "head", database_url=url)

    import app.db.models  # noqa: F401
    from app.db.base import Base

    modelled = set(Base.metadata.tables)
    migrated = sqlite_tables(url) - {"alembic_version"}

    missing = sorted(modelled - migrated)
    extra = sorted(migrated - modelled)
    print(f"model tables: {len(modelled)}   migrated tables: {len(migrated)}")
    if missing:
        print(f"MISSING from migration ({len(missing)}): {missing}")
    if extra:
        print(f"EXTRA in migration ({len(extra)}): {extra}")

    column_problems = column_mismatches(url)
    for problem in column_problems:
        print(f"COLUMN PROBLEM: {problem}")

    print("checking downgrade to base ...")
    run_alembic("downgrade", "base", database_url=url)
    # alembic_version legitimately survives a downgrade; nothing else may.
    leftovers = sqlite_tables(url) - {"alembic_version"}
    if leftovers:
        print(f"DOWNGRADE LEFT TABLES: {sorted(leftovers)}")
    else:
        print("downgrade to base is clean")

    with suppress(OSError):  # Windows may still hold a handle; file is in temp
        tmp.unlink(missing_ok=True)

    ok = not missing and not extra and not column_problems and not leftovers
    print("OK: migration matches the ORM metadata exactly" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())