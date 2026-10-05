"""index the fourteen foreign keys with no leading index

Supabase's advisor reported fourteen foreign keys whose referencing column was
never indexed. Every one of them is a real access path in this schema, so each
gets an index whose leading column is the FK column:

  * appointments.assignment_id, rework_visits.request_id / technician_id --
    dispatch and rework look-ups.
  * deposits.policy_id, refunds.policy_id -- the cancellation preview joins the
    policy to decide a refund window.
  * invoices.quote_id, quotes.supersedes_quote_id -- quote/invoice history.
  * maintenance_records.related_request_id -- recurring-problem grouping.
  * receipts.invoice_id / payment_id / issued_to_customer_id -- receipt lookup
    from both the invoice and the payment side.
  * role_permissions.permission_id -- permission -> roles, the reverse of the
    existing (role_id, permission_id) primary key.
  * staff_roles.role_id -- role -> staff.
  * technicians.base_zone_id -- filtering active technicians by zone.

None of these are covered today: the composite primary keys and unique
constraints that exist on role_permissions and staff_roles lead with a
*different* column, so Postgres has to scan those small tables. The advisor
still flags them because a FK cascade must be able to find referencing rows by
this column alone.

Reviewed rather than blindly applied -- each index maps to a query in
app/services or a cascade the schema declares. No policy or RLS change is
involved, so the zero-policy posture is untouched.

Revision ID: c7e19f4a83d2
Revises: b3f1d29c7a04
Create Date: 2026-10-05 01:20:00.000000

"""

from __future__ import annotations

from collections.abc import Sequence

from alembic import op

revision: str = "c7e19f4a83d2"
down_revision: str | None = "b3f1d29c7a04"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

# (table, column) pairs, one index each, named by the project convention
# ix_<table>_<column> so the ORM metadata and the database agree.
INDEXES: tuple[tuple[str, str], ...] = (
    ("appointments", "assignment_id"),
    ("deposits", "policy_id"),
    ("invoices", "quote_id"),
    ("maintenance_records", "related_request_id"),
    ("quotes", "supersedes_quote_id"),
    ("receipts", "invoice_id"),
    ("receipts", "issued_to_customer_id"),
    ("receipts", "payment_id"),
    ("refunds", "policy_id"),
    ("rework_visits", "request_id"),
    ("rework_visits", "technician_id"),
    ("role_permissions", "permission_id"),
    ("staff_roles", "role_id"),
    ("technicians", "base_zone_id"),
)


def _index_name(table: str, column: str) -> str:
    return f"ix_{table}_{column}"


def upgrade() -> None:
    for table, column in INDEXES:
        op.create_index(_index_name(table, column), table, [column], unique=False)


def downgrade() -> None:
    for table, column in reversed(INDEXES):
        op.drop_index(_index_name(table, column), table_name=table)