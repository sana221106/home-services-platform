"""Image intake validation and private storage paths (§79, §80, §81).

Binary blobs never touch PostgreSQL. This module:

* sniffs the *real* format from magic bytes instead of trusting the declared
  MIME type or the filename;
* enforces size and pixel-dimension ceilings;
* derives the storage path server-side, keyed by
  ``request-media/{customer}/{request}/{uuid}.{ext}``;
* rejects anything whose header cannot be parsed.

Dimension parsing is implemented directly against the JPEG/PNG/WebP headers so
the service keeps a small dependency surface and never decodes untrusted pixels
during validation.
"""

from __future__ import annotations

import hashlib
import io
import struct
import uuid
from dataclasses import dataclass
from pathlib import Path

from app.core.config import settings
from app.core.exceptions import UploadRejectedError

JPEG_MAGIC = b"\xff\xd8\xff"
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
RIFF_MAGIC = b"RIFF"
WEBP_TAG = b"WEBP"

_JPEG_SOF_MARKERS = frozenset(range(0xC0, 0xD0)) - {0xC4, 0xC8, 0xCC}

# Public: three call sites referenced the un-prefixed name, so extension checks
# on upload raised NameError instead of validating anything.
EXTENSION_BY_FORMAT: dict[str, str] = {
    "jpeg": ".jpg",
    "png": ".png",
    "webp": ".webp",
}

MIME_BY_FORMAT: dict[str, str] = {
    "jpeg": "image/jpeg",
    "png": "image/png",
    "webp": "image/webp",
}


@dataclass(frozen=True, slots=True)
class ValidatedImage:
    format: str
    mime_type: str
    extension: str
    width: int
    height: int
    size_bytes: int
    checksum_sha256: str
    content: bytes


@dataclass(frozen=True, slots=True)
class ImageDimensions:
    width: int
    height: int


def sniff_format(header: bytes) -> str | None:
    if header.startswith(JPEG_MAGIC):
        return "jpeg"
    if header.startswith(PNG_MAGIC):
        return "png"
    if header.startswith(RIFF_MAGIC) and header[8:12] == WEBP_TAG:
        return "webp"
    return None


def _png_dimensions(data: bytes) -> ImageDimensions | None:
    if len(data) < 24 or data[12:16] != b"IHDR":
        return None
    width, height = struct.unpack(">II", data[16:24])
    return ImageDimensions(width=width, height=height)


def _jpeg_dimensions(data: bytes) -> ImageDimensions | None:
    index = 2
    length = len(data)
    while index < length - 9:
        if data[index] != 0xFF:
            index += 1
            continue
        marker = data[index + 1]
        if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
            index += 2
            continue
        if index + 4 > length:
            return None
        segment_length = struct.unpack(">H", data[index + 2 : index + 4])[0]
        if marker in _JPEG_SOF_MARKERS:
            if index + 9 > length:
                return None
            height, width = struct.unpack(">HH", data[index + 5 : index + 9])
            return ImageDimensions(width=width, height=height)
        index += 2 + segment_length
    return None


def _webp_dimensions(data: bytes) -> ImageDimensions | None:
    if len(data) < 30:
        return None
    chunk = data[12:16]
    if chunk == b"VP8 ":
        width = int.from_bytes(data[26:28], "little") & 0x3FFF
        height = int.from_bytes(data[28:30], "little") & 0x3FFF
        return ImageDimensions(width=width, height=height)
    if chunk == b"VP8L":
        bits = int.from_bytes(data[21:25], "little")
        return ImageDimensions(width=(bits & 0x3FFF) + 1, height=((bits >> 14) & 0x3FFF) + 1)
    if chunk == b"VP8X":
        width = int.from_bytes(data[24:27], "little") + 1
        height = int.from_bytes(data[27:30], "little") + 1
        return ImageDimensions(width=width, height=height)
    return None


def read_dimensions(fmt: str, data: bytes) -> ImageDimensions | None:
    if fmt == "png":
        return _png_dimensions(data)
    if fmt == "jpeg":
        return _jpeg_dimensions(data)
    if fmt == "webp":
        return _webp_dimensions(data)
    return None


def validate_image(
    content: bytes,
    *,
    declared_mime: str | None = None,
    filename: str | None = None,
) -> ValidatedImage:
    """Authoritative upload gate. Raises :class:`UploadRejectedError` on any
    mismatch between the declared type and the real bytes."""
    if not content:
        raise UploadRejectedError("The uploaded file is empty.")

    if len(content) > settings.max_upload_bytes:
        raise UploadRejectedError(
            "The image exceeds the maximum allowed size.",
            details={"max_bytes": settings.max_upload_bytes, "received_bytes": len(content)},
        )

    fmt = sniff_format(content[:16])
    if fmt is None:
        raise UploadRejectedError(
            "Unsupported or corrupt image. Allowed formats: JPEG, PNG, WebP."
        )

    mime = MIME_BY_FORMAT[fmt]
    if mime not in settings.allowed_image_mimes:
        raise UploadRejectedError("This image format is not permitted.")

    if declared_mime and declared_mime != mime and declared_mime != "application/octet-stream":
        raise UploadRejectedError(
            "The declared file type does not match the actual file content.",
            details={"declared": declared_mime, "detected": mime},
        )

    if filename:
        suffix = Path(filename).suffix.lower()
        expected = EXTENSION_BY_FORMAT[fmt]
        if suffix and suffix not in {expected, ".jpeg" if expected == ".jpg" else expected}:
            raise UploadRejectedError(
                "The file extension does not match the actual file content.",
                details={"extension": suffix, "detected": mime},
            )

    dimensions = read_dimensions(fmt, content)
    if dimensions is None:
        raise UploadRejectedError("The image header could not be parsed.")
    if dimensions.width <= 0 or dimensions.height <= 0:
        raise UploadRejectedError("The image reports invalid dimensions.")
    if dimensions.width > settings.max_image_dimension or dimensions.height > settings.max_image_dimension:
        raise UploadRejectedError(
            "The image resolution is too large.",
            details={
                "max_dimension": settings.max_image_dimension,
                "width": dimensions.width,
                "height": dimensions.height,
            },
        )

    return ValidatedImage(
        format=fmt,
        mime_type=mime,
        extension=EXTENSION_BY_FORMAT[fmt],
        width=dimensions.width,
        height=dimensions.height,
        size_bytes=len(content),
        checksum_sha256=hashlib.sha256(content).hexdigest(),
        content=content,
    )


def build_storage_path(
    *, customer_id: uuid.UUID, request_id: uuid.UUID, extension: str, media_id: uuid.UUID
) -> str:
    """Server-generated path. The client's filename is never used (§81)."""
    return (
        f"request-media/{customer_id}/{request_id}/{media_id}{extension}"
    )


def build_conversation_attachment_path(
    *, customer_id: uuid.UUID, conversation_id: uuid.UUID, extension: str, attachment_id: uuid.UUID
) -> str:
    return f"chat-media/{customer_id}/{conversation_id}/{attachment_id}{extension}"


def build_payment_proof_path(
    *, customer_id: uuid.UUID, payment_id: uuid.UUID, extension: str, proof_id: uuid.UUID
) -> str:
    return f"payment-proofs/{customer_id}/{payment_id}/{proof_id}{extension}"


def build_complaint_attachment_path(
    *, customer_id: uuid.UUID, complaint_id: uuid.UUID, extension: str, attachment_id: uuid.UUID
) -> str:
    return f"complaint-media/{customer_id}/{complaint_id}/{attachment_id}{extension}"


class LocalPrivateStorage:
    """Filesystem-backed private storage used when Supabase is unconfigured.

    Files are written outside the web root and are only reachable through a
    signed, authorised endpoint — the same contract the Supabase adapter uses.
    """

    provider = "local"

    def __init__(self, root: str | None = None) -> None:
        self._root = Path(root or settings.storage_root)

    def write(self, path: str, content: bytes) -> str:
        target = self._root / Path(path)
        target.parent.mkdir(parents=True, exist_ok=True)
        # Guard against path traversal: resolve and confirm containment.
        resolved = target.resolve()
        if not str(resolved).startswith(str(self._root.resolve())):
            raise UploadRejectedError("Invalid storage path.")
        target.write_bytes(content)
        return path

    def read(self, path: str) -> bytes:
        target = (self._root / Path(path)).resolve()
        if not str(target).startswith(str(self._root.resolve())):
            raise UploadRejectedError("Invalid storage path.")
        return target.read_bytes()

    def exists(self, path: str) -> bool:
        target = (self._root / Path(path)).resolve()
        return str(target).startswith(str(self._root.resolve())) and target.is_file()

    def delete(self, path: str) -> None:
        target = (self._root / Path(path)).resolve()
        if str(target).startswith(str(self._root.resolve())) and target.is_file():
            target.unlink(missing_ok=True)


def make_storage_client():
    """Return the configured storage adapter (§135).

    Supabase is used when credentials exist; otherwise local private storage
    keeps the flow runnable locally with identical semantics.
    """
    if settings.supabase_configured:
        from app.integrations.supabase.storage import SupabaseStorage

        return SupabaseStorage()
    return LocalPrivateStorage()


def image_from_upload_stream(file: io.BufferedReader | io.BytesIO) -> bytes:
    return file.read()


__all__ = [
    "EXTENSION_BY_FORMAT",
    "LocalPrivateStorage",
    "MIME_BY_FORMAT",
    "ValidatedImage",
    "build_complaint_attachment_path",
    "build_conversation_attachment_path",
    "build_payment_proof_path",
    "build_storage_path",
    "make_storage_client",
    "read_dimensions",
    "sniff_format",
    "validate_image",
]