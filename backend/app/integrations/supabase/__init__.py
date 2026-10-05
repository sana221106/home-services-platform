"""Supabase adapters (database, private object storage).

Supabase is used here for **infrastructure only**:

* PostgreSQL hosting, reached over ``psycopg``/SQLAlchemy from the existing
  Alembic-managed models — see :mod:`app.db.session`;
* private Storage buckets for uploaded media — see
  :mod:`app.integrations.supabase.storage`.

Supabase **Auth is deliberately not used**. The platform owns its own OTP/JWT
flow (:mod:`app.core.security`), so ``SUPABASE_AUTH_ENABLED`` stays ``false``
and enabling it would introduce a second, conflicting identity system.
"""

from app.integrations.supabase.storage import (
    BUCKET_BY_PREFIX,
    StorageObjectNotFound,
    SupabaseStorage,
    resolve_storage_path,
)

__all__ = [
    "BUCKET_BY_PREFIX",
    "StorageObjectNotFound",
    "SupabaseStorage",
    "resolve_storage_path",
]