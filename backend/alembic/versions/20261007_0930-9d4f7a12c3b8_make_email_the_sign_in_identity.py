"""make email the sign-in identity

Sign-in moved off SMS. The customer now gives a name, an email address and an
optional phone number, and the same 6-digit OTP is delivered to that address
instead of a handset. `email` becomes the unique key the challenge is issued
against, which is why it carries a unique index rather than a plain one: two
live challenges must never be addressed to the same account.

`phone` loses its unique index at the same time. It used to be the identity, so
uniqueness was load-bearing; now it is only contact detail, and two customers
from the same household sharing a number would otherwise trip an integrity
error on a field the form advertises as optional. It stays indexed because staff
login still looks employees up by number, and it stays nullable for the same
reason it did before.

Revision ID: 9d4f7a12c3b8
Revises: 12cbf8b6db29
Create Date: 2026-10-07 09:30:00.000000

"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "9d4f7a12c3b8"
down_revision: str | None = "12cbf8b6db29"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    with op.batch_alter_table("users", schema=None) as batch_op:
        batch_op.add_column(sa.Column("email", sa.String(length=255), nullable=True))
    with op.batch_alter_table("users", schema=None) as batch_op:
        batch_op.create_index(batch_op.f("ix_users_email"), ["email"], unique=True)
    with op.batch_alter_table("users", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_users_phone"))
    with op.batch_alter_table("users", schema=None) as batch_op:
        batch_op.create_index(batch_op.f("ix_users_phone"), ["phone"], unique=False)


def downgrade() -> None:
    # Refuses if two accounts share a phone number, which is correct: going back
    # means deciding which of them keeps it, not silently merging two people.
    with op.batch_alter_table("users", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_users_phone"))
    with op.batch_alter_table("users", schema=None) as batch_op:
        batch_op.create_index(batch_op.f("ix_users_phone"), ["phone"], unique=True)
    with op.batch_alter_table("users", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_users_email"))
    with op.batch_alter_table("users", schema=None) as batch_op:
        batch_op.drop_column("email")
