"""add zone_code to order address snapshots

The snapshot stored the governorate and city exactly as the customer typed them,
which meant every downstream consumer had to guess at geography. Storing the
canonical served area next to it lets dispatch, analytics and pricing group by
coverage zone without re-parsing free Arabic text.

Revision ID: b3f1d29c7a04
Revises: 487120c696fd
Create Date: 2026-10-03 12:40:00.000000

"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "b3f1d29c7a04"
down_revision: str | None = "487120c696fd"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    with op.batch_alter_table("order_address_snapshots", schema=None) as batch_op:
        batch_op.add_column(sa.Column("zone_code", sa.String(length=60), nullable=True))
    with op.batch_alter_table("order_address_snapshots", schema=None) as batch_op:
        batch_op.create_index(batch_op.f("ix_order_address_snapshots_zone_code"), ["zone_code"], unique=False)


def downgrade() -> None:
    with op.batch_alter_table("order_address_snapshots", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_order_address_snapshots_zone_code"))
    with op.batch_alter_table("order_address_snapshots", schema=None) as batch_op:
        batch_op.drop_column("zone_code")
