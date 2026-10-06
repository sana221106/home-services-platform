"""merge migration heads

Revision ID: 12cbf8b6db29
Revises: 7c4e1a90b2d5, c7e19f4a83d2
Create Date: 2026-10-06 12:34:40.112388

"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy import Text
from sqlalchemy.dialects import postgresql

# Custom column types (GUID) render as fully-qualified app.* expressions.
import app.db.base  # noqa: F401


revision: str = '12cbf8b6db29'
down_revision: str | None = ('7c4e1a90b2d5', 'c7e19f4a83d2')
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
