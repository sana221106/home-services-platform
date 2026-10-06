"""allow phone-less users and store a Google identifier

Google Sign-In proves identity with an ID token that carries an email, never a
phone number, so a customer who signs in with Google has no phone at all. The
column was `nullable=False`, which would have forced a fake number into it and
would then have shown that fake number in the customer's own profile.

`google_sub` is what makes the next sign-in land on the same row: the email can
be changed or aliased and is not unique across Google Workspace, while `sub` is
stable for the life of the account.

Revision ID: 7c4e1a90b2d5
Revises: b3f1d29c7a04
Create Date: 2026-10-04 16:45:00.000000

"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "7c4e1a90b2d5"
down_revision: str | None = "b3f1d29c7a04"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    with op.batch_alter_table("users", schema=None) as batch_op:
        batch_op.alter_column(
            "phone",
            existing_type=sa.String(length=32),
            nullable=True,
        )
    with op.batch_alter_table("users", schema=None) as batch_op:
        batch_op.add_column(
            sa.Column("google_sub", sa.String(length=128), nullable=True)
        )
    with op.batch_alter_table("users", schema=None) as batch_op:
        batch_op.create_unique_constraint(batch_op.f("uq_users_google_sub"), ["google_sub"])


def downgrade() -> None:
    with op.batch_alter_table("users", schema=None) as batch_op:
        batch_op.drop_constraint(batch_op.f("uq_users_google_sub"), type_="unique")
    with op.batch_alter_table("users", schema=None) as batch_op:
        batch_op.drop_column("google_sub")
    # Refuses if any phone-less user exists, which is correct: reverting means
    # deciding what phone those accounts get, not inventing one for them.
    with op.batch_alter_table("users", schema=None) as batch_op:
        batch_op.alter_column(
            "phone",
            existing_type=sa.String(length=32),
            nullable=False,
        )