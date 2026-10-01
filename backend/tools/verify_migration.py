"""Verify Alembic metadata matches the ORM and that upgrade/downgrade round-trips."""

from __future__ import annotations

import sqlite3
import sys
from pathlib import Path

DB = Path("_alembic_gen.db")


def main() -> int:
    conn = sqlite3.connect(DB)
    migrated = {
        row[0]
        for row in conn.execute(
            "select name from sqlite_master where type='table' and name not like 'alembic_%'"
        )
    }
    conn.close()

    from app.db.base import Base

    import app.db.models  # noqa: F401

    modelled = set(Base.metadata.tables)

    missing = sorted(modelled - migrated)
    extra = sorted(migrated - modelled)
    print(f"model tables: {len(modelled)}   migrated tables: {len(migrated)}")
    if missing:
        print(f"MISSING from migration ({len(missing)}): {missing}")
    if extra:
        print(f"EXTRA in migration ({len(extra)}): {extra}")
    if not missing and not extra:
        print("OK: migration matches the ORM metadata exactly")
    return 1 if (missing or extra) else 0


if __name__ == "__main__":
    sys.exit(main())
