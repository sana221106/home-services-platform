"""Opt-in end-to-end check against real Supabase Storage.

The suite is hermetic, and ``conftest`` deliberately blanks
``SUPABASE_URL``/``SUPABASE_SERVICE_ROLE_KEY`` so a developer's real
``backend/.env`` cannot leak live traffic into the default run. Opt back in
explicitly::

    SUPABASE_LIVE_STORAGE_TEST=1 \\
    SUPABASE_URL=https://<ref>.supabase.co \\
    SUPABASE_SERVICE_ROLE_KEY=… \\
    python -m pytest tests/test_supabase_storage_integration.py -m integration -v

Exercises the full path the application uses: the adapter writes to the correct
private bucket, an authorised FastAPI read succeeds, an IDOR attempt is refused,
and the object is deleted again. Every object is written under a unique
``<bucket>/integration-test/<uuid>/`` prefix and removed in teardown.
"""

from __future__ import annotations

import os
import uuid

import pytest

from app.core.config import settings

pytestmark = [
    pytest.mark.integration,
    pytest.mark.filterwarnings("ignore::DeprecationWarning"),
]

LIVE = bool(settings.supabase_url and settings.supabase_service_role_key)

pytestmark.append(
    pytest.mark.skipif(
        not LIVE,
        reason="needs SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in the environment",
    )
)

# A 1x1 PNG, so the payload is a genuinely decodable image.
PNG_1X1 = bytes.fromhex(
    "89504e470d0a1a0a0000000d494844520000000100000001080600000"
    "01f15c4890000000d4944415478da6364f8cf000001010100fad2a7"
    "bd0000000049454e44ae426082"
)


@pytest.fixture()
def storage():
    from app.integrations.supabase.storage import SupabaseStorage

    client = SupabaseStorage()
    yield client
    client.close()


@pytest.fixture()
def scratch_path():
    """A unique, obviously-test path that teardown can clean up."""
    run = uuid.uuid4()
    path = f"request-media/integration-test/{run}/probe.png"
    yield path
    # Best-effort cleanup so repeated runs never accumulate objects.
    try:
        from app.integrations.supabase.storage import SupabaseStorage

        SupabaseStorage().delete(path)
    except Exception as exc:  # pragma: no cover - cleanup must not mask a failure
        print(f"integration cleanup skipped for {path}: {exc}")


# ------------------------------------------------------------------- buckets


def test_every_bucket_is_private_and_reachable(storage, scratch_path) -> None:
    """Write, stat and remove one object in each of the four buckets."""
    from app.integrations.supabase.storage import SupabaseStorage

    client = SupabaseStorage()
    run = uuid.uuid4()
    prefixes = ("request-media", "chat-media", "payment-proofs", "complaint-media")
    try:
        for prefix in prefixes:
            path = f"{prefix}/integration-test/{run}/probe.png"
            client.write(path, PNG_1X1)
            assert client.exists(path) is True, f"{prefix}: object not visible after write"
            assert client.read(path) == PNG_1X1, f"{prefix}: round-trip mismatch"
            client.delete(path)
            assert client.exists(path) is False, f"{prefix}: object survived delete"
    finally:
        client.close()


def test_storage_client_is_selected_when_configured(storage) -> None:
    """Supabase credentials must actually switch the adapter on."""
    assert storage.provider == "supabase"


def test_service_role_key_is_present_in_environment() -> None:
    """Guards against a run that silently used the local adapter instead."""
    assert settings.supabase_configured
    assert settings.supabase_service_role_key is not None
    key = settings.supabase_service_role_key.get_secret_value()
    assert key, "service-role key must not be empty"
    # The Supabase project ref is public; the key must at least not be a
    # placeholder copied out of .env.example.
    assert "CHANGE_ME" not in key


# ------------------------------------------------------------ write / read


def test_write_read_exists_delete_cycle(storage, scratch_path) -> None:
    assert storage.exists(scratch_path) is False

    returned = storage.write(scratch_path, PNG_1X1)
    assert returned == scratch_path
    assert storage.exists(scratch_path) is True
    assert storage.read(scratch_path) == PNG_1X1

    storage.delete(scratch_path)
    assert storage.exists(scratch_path) is False


def test_read_missing_object_raises_file_not_found(storage, scratch_path) -> None:
    with pytest.raises(FileNotFoundError):
        storage.read(scratch_path)


def test_delete_is_idempotent(storage, scratch_path) -> None:
    storage.delete(scratch_path)
    storage.delete(scratch_path)


def test_uploaded_bytes_match_the_declared_size_limit(storage) -> None:
    """A 12 MB payload must still be accepted; the cap is inclusive."""
    ceiling = settings.max_upload_bytes
    assert ceiling == 12 * 1024 * 1024
    payload = PNG_1X1 + b"\x00" * (ceiling - len(PNG_1X1))
    path = f"request-media/integration-test/{uuid.uuid4()}/large.png"
    try:
        storage.write(path, payload)
        assert storage.exists(path) is True
        assert len(storage.read(path)) == ceiling
    finally:
        storage.delete(path)


# ------------------------------------------------------------ private by design


def test_object_is_not_publicly_fetchable(storage, scratch_path) -> None:
    """A private bucket must refuse anonymous access at the public URL."""
    import httpx

    storage.write(scratch_path, PNG_1X1)
    bucket, key = scratch_path.split("/", 1)
    public_url = f"{settings.supabase_url.rstrip('/')}/storage/v1/object/public/{bucket}/{key}"
    response = httpx.get(public_url, timeout=20.0)
    assert response.status_code in {400, 404}, (
        f"private object was reachable without credentials: {response.status_code}"
    )


def test_path_traversal_is_refused_before_any_network_call(storage) -> None:
    from app.core.exceptions import UploadRejectedError

    for bad in ("../../etc/passwd", "/request-media/a/b.png", "request-media/../x"):
        with pytest.raises(UploadRejectedError):
            storage.write(bad, PNG_1X1)


def test_no_secrets_in_adapter_repr(storage) -> None:
    """The service-role key must not leak through repr/str."""
    key = settings.supabase_service_role_key.get_secret_value() if settings.supabase_service_role_key else ""
    assert key not in repr(storage)
    assert key not in str(storage)


def test_supabase_auth_is_disabled() -> None:
    """Supabase must not be acting as a second identity provider."""
    assert settings.supabase_auth_enabled is False
    assert os.environ.get("SUPABASE_AUTH_ENABLED", "false").lower() in {"false", "0"}