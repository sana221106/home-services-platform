# Home Services Platform

A home-maintenance booking platform: a Flutter customer app, a FastAPI backend
that owns all business logic, and Supabase for managed PostgreSQL and private
media storage.

```
Flutter app ──HTTPS──▶ FastAPI ──psycopg/TLS──▶ Supabase PostgreSQL
                          │
                          └──service-role key──▶ Supabase Storage (private)
```

The mobile app talks **only** to FastAPI. It holds no database credentials and
no Supabase keys.

## Repository layout

| Path | What it is |
|---|---|
| `apps/mobile/` | Flutter customer app (Dart, RTL Arabic, `go_router`) |
| `backend/app/api/` | FastAPI routers and dependencies |
| `backend/app/services/` | Business logic — the authoritative layer |
| `backend/app/db/` | SQLAlchemy models, session, seed data |
| `backend/alembic/` | Migration history (source of truth for the schema) |
| `backend/tests/` | pytest suite |
| `docs/supabase.md` | **Supabase setup, migrations, storage, security** |
| `infra/` | Windows helper scripts for demo/APK publishing |

## Quick start

### Backend

```bash
cd backend
python -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -e ".[dev]"

cp ../.env.example .env       # fill in values; see docs/supabase.md
export DATABASE_URL="sqlite+pysqlite:///./local.db"
export JWT_SECRET="$(python -c 'import secrets; print(secrets.token_urlsafe(48))')"

python -m alembic upgrade head
python -m app.db.seed
uvicorn app.main:app --reload
```

Interactive API docs: <http://127.0.0.1:8000/docs>

### Mobile

```bash
cd apps/mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

`10.0.2.2` is how the Android emulator reaches the host machine. For a physical
device, pass your machine's LAN address.

The app needs **one** build-time value, `API_BASE_URL`. Never pass it a database
URL, a JWT secret, or a Supabase key.

## Checks

```bash
cd backend
python -m pytest
python -m ruff check .
python -m mypy app
python -m alembic check
```

```bash
cd apps/mobile
flutter analyze
flutter test
```

## Authentication

The platform runs its own email OTP flow and issues its own JWTs. A customer
gives a name, an email address and an optional phone number; the 6-digit code is
sent to that address. No SMS is involved anywhere.

**Supabase Auth is deliberately not used** — `SUPABASE_AUTH_ENABLED` stays
`false`, and enabling it would introduce a second, conflicting identity system.

Authorisation is enforced in FastAPI: every route declares its dependency
(customer vs staff) and every staff route checks an explicit permission.
Ownership is re-checked on read, not just on write, so knowing an id is never
enough to fetch someone else's data.

## Documentation

* [docs/supabase.md](docs/supabase.md) — Supabase setup, migration process,
  environment variables, local development, production configuration, storage
  architecture, security decisions