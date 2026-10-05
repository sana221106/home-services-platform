-- Security hardening for a service-role-only architecture (§135).
--
-- The mobile app never uses the Supabase Data API: it talks only to FastAPI,
-- which authenticates its own OTP/JWT flow. Supabase Auth stays disabled. So
-- the anon and authenticated roles have no legitimate use here, and their
-- default grants on the public schema are pure attack surface.
--
-- This removes those grants, then enables RLS with no policies as a backstop.
-- Enabling RLS alone is NOT enough: without revoking the grants, a permissive
-- policy would still be reachable, and a stray anon key would still read
-- every row via PostgREST. The two steps are complementary and both are applied.
--
-- Safe to re-run. FastAPI connects as the owner role (postgres), which is not
-- affected by any of this.
--
-- Deliberately NOT done:
--   * no permissive policies for anon/authenticated
--   * no revoke of the storage schema (owned by supabase_storage_admin)
--   * no Supabase Auth objects
--   * no change to service_role, which the storage adapter needs

BEGIN;

-- ---------------------------------------------------------------- schema
-- USAGE alone is enough for a client to resolve object names; without it even
-- a direct grant on a single table is unreachable.
REVOKE ALL ON SCHEMA public FROM anon, authenticated;

-- ---------------------------------------------------------------- tables
-- Covers the 57 tables plus alembic_version. Existing rows are included.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon, authenticated;

-- -------------------------------------------------------------- sequences
-- Sequences leak row counts and accelerate id enumeration. FastAPI never uses
-- a client sequence directly, so no grant is needed.
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon, authenticated;

-- -------------------------------------------------------- default privileges
-- Without this, any table or sequence created by a future migration is granted
-- back to anon/authenticated automatically by Supabase's defaults. This closes
-- that recurring hole permanently for this database.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    REVOKE ALL ON TABLES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    REVOKE ALL ON SEQUENCES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    REVOKE ALL ON FUNCTIONS FROM anon, authenticated;

-- ------------------------------------------------------------------- RLS
-- Defense in depth. With no policies at all, any role that somehow regains a
-- grant reads zero rows rather than everything. The owner role bypasses RLS,
-- so migrations and runtime queries are unaffected.
DO $$
DECLARE
    t text;
BEGIN
    FOR t IN
        SELECT tablename FROM pg_tables WHERE schemaname = 'public'
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format('ALTER TABLE public.%I FORCE ROW LEVEL SECURITY', t);
    END LOOP;
END
$$;

COMMIT;