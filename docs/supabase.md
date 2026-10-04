# Supabase integration

How the platform uses Supabase, and how to run it safely.

- [Architecture](#architecture)
- [What Supabase is and is not used for](#what-supabase-is-and-is-not-used-for)
- [One-time Supabase project setup](#one-time-supabase-project-setup)
- [Environment variables](#environment-variables)
- [Applying migrations](#applying-migrations)
- [Storage architecture](#storage-architecture)
- [Database security](#database-security)
- [Seeding reference data](#seeding-reference-data)
- [Local development](#local-development)
- [Production configuration](#production-configuration)
- [Running the checks](#running-the-checks)
- [Troubleshooting](#troubleshooting)

---

## Architecture

```
Flutter app  ──HTTP/JSON──▶  FastAPI  ──psycopg (TLS)──▶  Supabase PostgreSQL
   (public)   JWT in header     (sole       SQLAlchemy            (private)
                                holder of
                                privileged
                                credentials)
                     │
                     └──service-role key──▶  Supabase Storage (4 private buckets)
```

The mobile app never talks to PostgreSQL or to Supabase directly. FastAPI is the
only component that holds the database password, the JWT signing secret, or the
Supabase service-role key. Every read of an uploaded file is authorised in
FastAPI *before* the storage layer is touched.

## What Supabase is and is not used for

| Capability | Used | Why |
|---|---|---|
| PostgreSQL hosting | **Yes** | Managed, TLS-terminated, backed by the existing SQLAlchemy models and Alembic history. |
| Private Storage buckets | **Yes** | Four private buckets for uploaded media. |
| Supabase Auth | **No** | The platform has its own OTP + JWT flow. `SUPABASE_AUTH_ENABLED` stays `false`; enabling Supabase Auth would create a second, conflicting identity system. |
| Realtime | No | Not required. |
| Edge Functions | No | Business logic stays in FastAPI. |

The service-role key is used **only** by the storage adapter, and only from
inside the API process. It bypasses Row Level Security and every Storage policy,
so it is treated as a production secret.

---

## One-time Supabase project setup

### 1. Database password

Supabase → **Project Settings → Database** → reset or copy the database
password. This is the password that goes in `DATABASE_URL`. It is *not* the
service-role key.

### 2. Buckets

Create four buckets, all **private**:

| Bucket | Holds | Path prefix |
|---|---|---|
| `request-media` | Customer photos attached to a service request | `request-media/` |
| `chat-media` | Support-chat attachments | `chat-media/` |
| `payment-proofs` | Deposit/payment proof images | `payment-proofs/` |
| `complaint-media` | Complaint attachments | `complaint-media/` |

Enforce the allowed media types on each bucket
(**image/jpeg**, **image/png**, **image/webp**) and a **12 MB** file-size limit.

> No bucket may be public. The API streams media itself through authorised
> routes; it never hands out a public or signed URL.

### 3. API keys

Supabase → **Project Settings → API**:

* Project URL
* Publishable key (aka anon key)
* **Service-role key**

Store the service-role key only in the API host's secret store.

---

## Environment variables

Copy the template and fill it in:

```bash
cp .env.example backend/.env
```

`.env` is git-ignored. `backend/tests/test_config_hygiene.py` fails the build if
a real credential ever lands in `.env.example`, or if the template documents a
variable the application does not actually read.

| Variable | Required | Notes |
|---|---|---|
| `DATABASE_URL` | yes | `postgresql+psycopg://…?sslmode=require`. Must use the `psycopg` driver. |
| `JWT_SECRET` | yes | Startup aborts in production if left at its built-in value. |
| `SUPABASE_URL` | for storage | `https://<ref>.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` | for storage | Server-side only. Never in Flutter. |
| `SUPABASE_PUBLISHABLE_KEY` | no | Accepted for completeness. Not needed by the mobile app. |
| `SUPABASE_AUTH_ENABLED` | — | Must stay `false`. |
| `SUPABASE_STORAGE_BUCKET` | no | Fallback bucket for unprefixed paths. |
| `DB_POOL_SIZE`, `DB_MAX_OVERFLOW` | no | See [production configuration](#production-configuration). |
| `DB_SSLMODE` | no | Applied only when `DATABASE_URL` has no `sslmode`. |

### Connection string

Direct connection (port 5432):

```
postgresql+psycopg://postgres:<DB_PASSWORD>@db.<PROJECT_REF>.supabase.co:5432/postgres?sslmode=require
```

Transaction pooler (port 6543) — use when several API workers share one project,
because each worker keeps its own pool:

```
postgresql+psycopg://postgres.<POOLER_USER>:<DB_PASSWORD>@aws-0-eu-central-1.pooler.supabase.com:6543/postgres?sslmode=require
```

URL-encode the password if it contains `@`, `:`, `/` or `#`.

---

## Applying migrations

The Alembic history is the source of truth. **Never** hand-create tables and
never apply a second, parallel schema.

```bash
cd backend

# 1. What will run, without connecting
python -m alembic history
python -m alembic upgrade head --sql     # review the SQL

# 2. Apply
python -m alembic upgrade head

# 3. Confirm
python -m alembic current                # expect: b3f1d29c7a04 (head)
```

`alembic/env.py` reads the URL from `app.core.config.Settings`, so there is a
single place that knows how to reach the database.

The current chain is linear and has no branches:

```
<base> ──▶ 487120c696fd  initial schema
              │
              └──▶ b3f1d29c7a04  add zone_code to order address snapshots  (head)
```

### Adding a migration

```bash
python -m alembic revision --autogenerate -m "describe the change"
```

Review the generated file before committing. Project column types (such as
`GUID`) render as fully-qualified `app.*` expressions via `render_item` in
`env.py`; keep that behaviour.

### Verifying the ORM and the migrations still agree

```bash
python -m alembic upgrade head
python tools/verify_migration.py
# OK: migration matches the ORM metadata exactly
```

---

## Storage architecture

`backend/app/integrations/supabase/storage.py` implements the adapter that
`media_service.make_storage_client()` returns when Supabase is configured. Its
contract matches the local fallback exactly:

```python
write(path, content) -> str
read(path) -> bytes
exists(path) -> bool
delete(path) -> None
```

### Bucket routing

`media_service` generates paths whose first segment is the logical bucket name.
The adapter splits that into `(bucket, object_key)`:

```
request-media/<customer>/<request>/<media>.jpg
  → bucket "request-media", key "<customer>/<request>/<media>.jpg"
```

Only the four prefixes in `BUCKET_BY_PREFIX` are accepted. Anything else is
rejected with `UploadRejectedError`, so a buggy or compromised caller cannot
address an arbitrary bucket.

### Path safety

Every operation runs the same validation first, so `write`, `read`, `exists` and
`delete` can never disagree about a path. Rejected: empty paths, absolute paths,
trailing slashes, `..` segments, backslashes, NUL bytes, whitespace and any
segment outside `[A-Za-z0-9._-]`. Paths are always generated server-side from
UUIDs — the client's filename is never used.

### Authorisation

Storage paths are never exposed to a client. The API exposes ids and re-checks
ownership on every read:

| Route | Who may read |
|---|---|
| `GET /api/v1/media/{media_id}/content` | the customer who owns the request |
| `GET /api/v1/media/staff/request-media/{media_id}/content` | staff with `REQUEST_READ` |
| `GET /api/v1/media/message-attachments/{id}/content` | the customer whose conversation holds it |
| `GET /api/v1/media/staff/message-attachments/{id}/content` | staff with `CHAT_READ` |
| `GET /api/v1/media/staff/payment-proofs/{id}/content` | staff with `PAYMENT_READ` |

Responses are sent with `Cache-Control: private`, so a shared cache will not
serve one customer's photo to another.

### Uploads

Validation happens before anything is stored, and it trusts the bytes rather
than the caller: the real format is sniffed from the magic bytes, then the
declared MIME type, the file extension, the size ceiling and the pixel
dimensions must all agree. See `media_service.validate_image`.

### Why `httpx` and not the Supabase SDK

The adapter speaks the Storage REST API through `httpx`, already a project
dependency. The `supabase` SDK would pull in PostgREST, GoTrue and realtime
clients that this architecture does not use — the database goes through
SQLAlchemy and authentication is ours.

---

## Database security

The Flutter app authenticates against FastAPI and must not be able to mutate
business tables directly. Defence in depth:

1. **The mobile app has no database credentials at all.** It receives only an
   API base URL via `--dart-define=API_BASE_URL=…`. There is no Supabase or
   Postgres package in `apps/mobile/pubspec.yaml`.
2. **Revoke Data API access for the anon/authenticated roles.** The app never
   uses the Data API, so the default grants are pure attack surface:

   ```sql
   revoke all on all tables in schema public from anon, authenticated;
   revoke all on all sequences in schema public from anon, authenticated;
   revoke all on schema public from anon, authenticated;
   alter default privileges in schema public
     revoke all on tables from anon, authenticated;
   alter default privileges in schema public
     revoke all on sequences from anon, authenticated;
   ```

   FastAPI connects as the owner role (`postgres` or a dedicated owner), so
   migrations and runtime queries are unaffected.

3. **Keep RLS as a backstop.** Enable RLS on every business table with no
   permissive policy. With the grants above removed, an accidentally shipped
   anon key still cannot read a row.

   ```sql
   alter table <table> enable row level security;
   ```

4. **Private buckets.** Never mark a media bucket public.

5. **Advisors.** After changing the schema, run Supabase → **Database →
   Advisors** (Security and Performance) and resolve what is legitimate. Expect
   and dismiss the advisories that only make sense for a service-role-only
   architecture — for example "RLS disabled" once no client role can reach the
   table at all.

---

## Seeding reference data

Reference data only — roles, permissions, coverage zones, service categories,
problem types and cancellation policies. It is idempotent: every row is matched
on its natural key and updated in place.

```bash
cd backend
python -m app.db.seed
```

This includes the three categories the app needs to function:

* **Plumbing** (`plumbing`, سباكة)
* **Electrical** (`electrical`, كهرباء)
* **Painting** (`painting`, دهانات)

…plus Air Conditioning, Home Appliances, Carpentry, Cleaning and Pest Control,
each with its problem types.

### Demo data

`--demo` additionally creates a super-admin login. It is refused by the
production guard, and the password is random and printed once unless
`SEED_ADMIN_PASSWORD` is set:

```bash
SEED_ADMIN_PASSWORD='…' python -m app.db.seed --demo
```

Never run `--demo` against production.

---

## Local development

SQLite is enough for day-to-day work; the model graph is portable and the test
suite runs entirely in memory.

```bash
cd backend
python -m venv .venv && source .venv/bin/activate    # Windows: .venv\Scripts\activate
pip install -e ".[dev]"

cp ../.env.example .env        # or just export the variables you need

export DATABASE_URL="sqlite+pysqlite:///./local.db"
export JWT_SECRET="$(python -c 'import secrets; print(secrets.token_urlsafe(48))')"
export ENVIRONMENT=development

python -m alembic upgrade head
python -m app.db.seed
uvicorn app.main:app --reload
```

With no Supabase credentials configured, `make_storage_client()` returns
`LocalPrivateStorage`, which writes to `STORAGE_ROOT` (default `./var/storage`)
with identical semantics — so uploads, streaming and deletion all work offline.

To exercise real Supabase Storage locally, set `SUPABASE_URL` and
`SUPABASE_SERVICE_ROLE_KEY`; the adapter is selected automatically.

API docs are at `/docs` outside production.

---

## Production configuration

Checklist:

- [ ] `ENVIRONMENT=production`
- [ ] `DATABASE_URL` uses `postgresql+psycopg://` **and** `sslmode=require`
- [ ] `JWT_SECRET` is a real random secret (`secrets.token_urlsafe(48)`)
- [ ] `SUPABASE_SERVICE_ROLE_KEY` comes from a secret store, not a file in the repo
- [ ] `SUPABASE_AUTH_ENABLED=false`
- [ ] All four buckets are private and size/type-limited
- [ ] `anon`/`authenticated` have no grants on `public` (see [database security](#database-security))
- [ ] `RATE_LIMIT_ENABLED=true` with a shared rate-limit store if you run more
      than one worker
- [ ] `CORS_ALLOW_ORIGINS` lists real origins, not `*`
- [ ] `/docs` is disabled automatically in production

Startup refuses to boot in production if `JWT_SECRET` is still the built-in
development value, if `DATABASE_URL` is missing `sslmode`, or if
`SUPABASE_AUTH_ENABLED` has been switched on. The check is
`Settings.assert_production_safe()`, called from the FastAPI lifespan.

### Connection limits

`DB_POOL_SIZE + DB_MAX_OVERFLOW` is the maximum number of PostgreSQL connections
one API process may open. Multiply by the number of workers and keep the total
under your plan's limit, or point every worker at the transaction pooler
(port 6543).

`pool_pre_ping` detects connections closed while idle, and `pool_recycle`
replaces them before Supabase drops them, so the first request after a quiet
period does not fail on a stale socket.

---

## Running the checks

```bash
cd backend

python -m pytest                    # full suite
python -m pytest tests/test_media.py tests/test_supabase_storage.py
python -m ruff check .
python -m mypy app
python -m alembic check             # model/migration drift
python tools/verify_migration.py    # ORM vs migration tables
```

Test coverage of the integration:

| File | Covers |
|---|---|
| `tests/test_supabase_storage.py` | bucket routing, path traversal, auth headers, status handling (offline, mocked transport) |
| `tests/test_media.py` | streaming authorisation, IDOR, staff permissions, soft-delete regression |
| `tests/test_config_hygiene.py` | no secrets in `.env.example`, no template/config drift |

### Live storage integration test

The end-to-end check — FastAPI → Supabase Storage → metadata → authorised fetch
→ unauthorised fetch denied → delete — needs real credentials:

```bash
export SUPABASE_URL=https://<ref>.supabase.co
export SUPABASE_SERVICE_ROLE_KEY=…
python -m pytest tests/test_supabase_storage_integration.py -m integration
```

It writes only under a `request-media/<test-uuid>/` prefix and deletes what it
created.

---

## Troubleshooting

**`sslmode` errors / `certificate verify failed`**
The direct connection requires TLS. Confirm `?sslmode=require` is present, and
that the system CA bundle is available to `psycopg`.

**`too many connections`**
Lower `DB_POOL_SIZE`/`DB_MAX_OVERFLOW`, reduce worker count, or move to the
transaction pooler on port 6543.

**`server closed the connection unexpectedly` on the first request after a pause**
Idle reaping. Confirm `DB_POOL_PRE_PING=true` and a `DB_POOL_RECYCLE_SECONDS`
value comfortably below the proxy's idle timeout.

**`Storage upload failed` (503)**
The bucket name is wrong or missing, the key lacks `SUPABASE_SERVICE_ROLE_KEY`,
or the object exceeded the bucket's size limit. The adapter reports only the
upstream status, never the response body, to avoid echoing the key.

**`Invalid storage path` (415)**
The path's first segment is not one of the four known prefixes, or the path
contains a rejected character. Paths must be generated by `media_service`.

**`Refusing to start in production with unsafe configuration`**
Working as intended. The message names each problem; fix `.env` rather than
setting `DB_REJECT_INSECURE_PRODUCTION_URL=false` to silence it.