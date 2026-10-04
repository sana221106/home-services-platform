"""Supabase Storage adapter unit tests (§79, §135).

Uses an ``httpx.MockTransport`` so the contract (URL shape, bucket routing,
headers, status handling, path safety) is verified without touching a real
project. The end-to-end check against live buckets is a separate opt-in
integration test — see ``tests/test_supabase_storage_integration.py``.
"""

from __future__ import annotations

import httpx
import pytest

from app.core.exceptions import IntegrationUnavailableError, UploadRejectedError
from app.integrations.supabase.storage import (
    BUCKET_BY_PREFIX,
    SupabaseStorage,
    resolve_storage_path,
)

pytestmark = pytest.mark.filterwarnings("ignore::DeprecationWarning")

SERVICE_KEY = "test-service-role-key-not-real"
SAMPLE = b"\x89PNG\r\n\x1a\nbinary-image-bytes"


class Recorder:
    """Captures requests and replays queued responses."""

    def __init__(self, responses: list[httpx.Response] | None = None) -> None:
        self.requests: list[httpx.Request] = []
        self._responses = list(responses or [])

    def handler(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        if self._responses:
            return self._responses.pop(0)
        return httpx.Response(200, json={"Key": "ok"})

    @property
    def transport(self) -> httpx.MockTransport:
        return httpx.MockTransport(self.handler)

    def last(self) -> httpx.Request:
        return self.requests[-1]


def make_storage(recorder: Recorder) -> SupabaseStorage:
    client = httpx.Client(
        base_url="https://project.supabase.co", transport=recorder.transport
    )
    return SupabaseStorage(
        url="https://project.supabase.co",
        service_role_key=SERVICE_KEY,
        client=client,
    )


# ------------------------------------------------------------ path routing


@pytest.mark.parametrize("prefix,bucket", sorted(BUCKET_BY_PREFIX.items()))
def test_each_prefix_routes_to_its_own_bucket(prefix: str, bucket: str) -> None:
    resolved_bucket, key = resolve_storage_path(
        f"{prefix}/11111111-1111-1111-1111-111111111111/22222222-2222-2222-2222-222222222222/a.jpg"
    )
    assert resolved_bucket == bucket
    assert key.endswith("/a.jpg")
    assert not key.startswith(prefix)


def test_all_four_buckets_are_covered() -> None:
    assert set(BUCKET_BY_PREFIX.values()) == {
        "request-media",
        "chat-media",
        "payment-proofs",
        "complaint-media",
    }


@pytest.mark.parametrize(
    "bad_path",
    [
        "",
        "   ",
        "/request-media/a/b.jpg",
        "request-media/../../../etc/passwd",
        "request-media/..",
        "request-media/a/../../b.jpg",
        "request-media//a.jpg",
        "request-media/a/",
        "request-media\\a\\b.jpg",
        "unknown-bucket/a/b.jpg",
        "storage.objects/a/b.jpg",
        "request-media/a b/c.jpg",
        "request-media/a/b.jpg\x00",
    ],
)
def test_traversal_and_unknown_buckets_are_rejected(bad_path: str) -> None:
    with pytest.raises(UploadRejectedError):
        resolve_storage_path(bad_path)


# ------------------------------------------------------------------ write


def test_write_targets_the_mapped_bucket_and_object_key() -> None:
    recorder = Recorder([httpx.Response(200, json={"Key": "k"})])
    storage = make_storage(recorder)

    path = "request-media/customer-1/request-2/photo.jpg"
    assert storage.write(path, SAMPLE) == path

    request = recorder.last()
    assert request.method == "POST"
    assert request.url.path == (
        "/storage/v1/object/request-media/customer-1/request-2/photo.jpg"
    )
    assert request.content == SAMPLE
    assert request.headers["content-type"] == "application/octet-stream"
    assert request.headers["x-upsert"] == "false"


def test_write_authenticates_with_service_role_key() -> None:
    recorder = Recorder([httpx.Response(200, json={"Key": "k"})])
    storage = make_storage(recorder)
    storage.write("chat-media/c/conv/a.png", SAMPLE)

    request = recorder.last()
    assert request.headers["authorization"] == f"Bearer {SERVICE_KEY}"
    assert request.headers["apikey"] == SERVICE_KEY


@pytest.mark.parametrize(
    "path",
    [
        "request-media/c/r/a.jpg",
        "chat-media/c/conv/a.jpg",
        "payment-proofs/c/p/a.jpg",
        "complaint-media/c/comp/a.jpg",
    ],
)
def test_every_bucket_can_be_written(path: str) -> None:
    recorder = Recorder([httpx.Response(200, json={"Key": "k"})])
    storage = make_storage(recorder)
    storage.write(path, SAMPLE)
    assert recorder.last().url.path.startswith("/storage/v1/object/")


def test_write_rejects_empty_content() -> None:
    storage = make_storage(Recorder())
    with pytest.raises(UploadRejectedError):
        storage.write("request-media/c/r/a.jpg", b"")


def test_write_surfaces_upstream_failure_without_leaking_body() -> None:
    recorder = Recorder([httpx.Response(500, text="internal secret detail")])
    storage = make_storage(recorder)
    with pytest.raises(IntegrationUnavailableError) as excinfo:
        storage.write("request-media/c/r/a.jpg", SAMPLE)
    assert "internal secret detail" not in str(excinfo.value)
    assert excinfo.value.details["status"] == 500


# ------------------------------------------------------------------- read


def test_read_returns_stored_bytes() -> None:
    recorder = Recorder([httpx.Response(200, content=SAMPLE)])
    storage = make_storage(recorder)
    assert storage.read("request-media/c/r/a.png") == SAMPLE
    assert recorder.last().method == "GET"


def test_read_raises_file_not_found_for_missing_object() -> None:
    """Must be indistinguishable from the local adapter so one handler covers both."""
    recorder = Recorder([httpx.Response(404, json={"message": "Object not found"})])
    storage = make_storage(recorder)
    with pytest.raises(FileNotFoundError):
        storage.read("request-media/c/r/a.png")


# --------------------------------------------------------- exists / delete


def test_exists_true_and_false() -> None:
    recorder = Recorder([httpx.Response(200, json={"name": "a.jpg"})])
    assert make_storage(recorder).exists("request-media/c/r/a.jpg") is True

    missing = Recorder([httpx.Response(404, json={})])
    assert make_storage(missing).exists("request-media/c/r/a.jpg") is False


def test_delete_is_idempotent() -> None:
    ok = Recorder([httpx.Response(200, json={})])
    make_storage(ok).delete("request-media/c/r/a.jpg")
    assert ok.last().method == "DELETE"

    already_gone = Recorder([httpx.Response(404, json={})])
    make_storage(already_gone).delete("request-media/c/r/a.jpg")


def test_whitespace_in_object_keys_is_rejected_not_encoded() -> None:
    """Server-generated keys are UUIDs and extensions, so a space is a red flag.

    Rejecting beats silently percent-encoding: it keeps what lands in Storage
    identical to what is recorded in ``storage_path``.
    """
    with pytest.raises(UploadRejectedError):
        resolve_storage_path("request-media/c/r/a b.jpg")


def test_buckets_method_lists_configured_buckets() -> None:
    assert set(make_storage(Recorder()).buckets()) == set(BUCKET_BY_PREFIX.values())


# -------------------------------------------------------------- lifecycle


def test_close_is_safe_before_any_client_is_created() -> None:
    """``close`` must tolerate a lazily-created client that never existed.

    No network call here on purpose: this exercises the lifecycle only.
    """
    storage = SupabaseStorage(
        url="https://project.supabase.co", service_role_key=SERVICE_KEY
    )
    storage.close()
    storage.close()


def test_unconfigured_supabase_raises_integration_unavailable() -> None:
    with pytest.raises(IntegrationUnavailableError):
        SupabaseStorage(url="", service_role_key="", default_bucket=None)