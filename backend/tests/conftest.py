"""Shared pytest fixtures (§138).

Every test runs against an isolated in-memory SQLite database with the full
model graph created from metadata. Rate limiting and external integrations are
disabled so the suite is deterministic and offline.
"""

from __future__ import annotations

import hashlib
import os
from collections.abc import Generator, Iterator
from datetime import timedelta
from decimal import Decimal
from uuid import uuid4

import pytest

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("DATABASE_URL", "sqlite+pysqlite:///:memory:")
os.environ.setdefault("RATE_LIMIT_ENABLED", "false")
os.environ.setdefault("AI_ENABLED", "false")
os.environ.setdefault("SUPABASE_AUTH_ENABLED", "false")
# 32 bytes minimum: PyJWT warns on every encode and decode below that, which
# buried the warnings worth reading. Still not a real key.
os.environ.setdefault("JWT_SECRET", "test-secret-not-for-production-at-all")
# The audience Google's ID tokens are checked against; tests still exercise the
# rejection path by overriding the setting rather than by clearing it.
os.environ.setdefault(
    "GOOGLE_CLIENT_IDS", "test-web-client.apps.googleusercontent.com"
)
os.environ.setdefault("STORAGE_ROOT", "./var/test-storage")

# These are assigned, not setdefault: a developer's real ``backend/.env`` sets
# SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY, and pydantic-settings reads that
# file. Left alone, `settings.supabase_configured` becomes true and the suite
# starts writing to live private buckets instead of ``STORAGE_ROOT``. Tests must
# be hermetic, so Supabase Storage is switched off here and the opt-in live
# integration test re-enables it via an explicit marker/flag.
# Opt in with SUPABASE_LIVE_STORAGE_TEST=1 to run the real bucket tests.
_LIVE_STORAGE = os.environ.get("SUPABASE_LIVE_STORAGE_TEST", "").strip().lower() in {
    "1",
    "true",
    "yes",
}
if not _LIVE_STORAGE:
    os.environ["SUPABASE_URL"] = ""
    os.environ["SUPABASE_SERVICE_ROLE_KEY"] = ""
    os.environ["SUPABASE_PUBLISHABLE_KEY"] = ""
    os.environ["SUPABASE_ANON_KEY"] = ""
os.environ["FIREBASE_ENABLED"] = "false"

from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import create_engine  # noqa: E402
from sqlalchemy.orm import Session  # noqa: E402
from sqlalchemy.pool import StaticPool  # noqa: E402

from app.api import dependencies  # noqa: E402
from app.core.enums import PaymentMethod, PaymentStatus, Urgency  # noqa: E402
from app.core.security import hash_password  # noqa: E402
from app.db.models import (  # noqa: E402
    Base,
    CoverageZone,
    CustomerProfile,
    OtpChallenge,
    Payment,
    PricingRule,
    ProblemType,
    Property,
    RequestMedia,
    Role,
    RolePermission,
    ServiceCategory,
    ServiceRequest,
    StaffRoleAssignment,
    StaffUser,
    Technician,
    User,
)
from app.main import app  # noqa: E402
from app.utils.time import now_utc  # noqa: E402


@pytest.fixture(scope="session")
def engine() -> Iterator[object]:
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
        future=True,
    )
    Base.metadata.create_all(bind=engine)
    yield engine
    engine.dispose()


@pytest.fixture()
def db(engine) -> Generator[Session, None, None]:
    session = Session(bind=engine, autoflush=False, expire_on_commit=False)
    try:
        yield session
    finally:
        session.rollback()
        for table in reversed(Base.metadata.sorted_tables):
            session.execute(table.delete())
        session.commit()
        session.close()


@pytest.fixture()
def client(db: Session) -> Generator[TestClient, None, None]:
    """TestClient wired to the test session, re-raising server exceptions.

    A 500 in this project is always a defect, so letting the traceback escape
    is far more useful than a bare "Internal Server Error" assertion.
    """

    def override_db() -> Generator[Session, None, None]:
        yield db

    app.dependency_overrides[dependencies.get_db] = override_db
    with TestClient(app, raise_server_exceptions=True) as test_client:
        try:
            yield test_client
        finally:
            app.dependency_overrides.clear()


# ------------------------------------------------------------------ catalogue


@pytest.fixture()
def zone(db: Session) -> CoverageZone:
    row = CoverageZone(
        code="CAI",
        name_ar="القاهرة",
        governorate="Cairo",
        city="Cairo",
        is_active=True,
        center_latitude=Decimal("30.0444"),
        center_longitude=Decimal("31.2357"),
        radius_km=40,
        urgent_multiplier=Decimal("1.00"),
    )
    db.add(row)
    db.flush()
    return row


@pytest.fixture()
def category(db: Session) -> ServiceCategory:
    row = ServiceCategory(
        code="plumbing",
        name_ar="سباكة",
        name_en="Plumbing",
        description_ar="خدمات السباكة",
        icon_key="plumbing",
        color_hex="#1D4ED8",
        soft_background_hex="#DBEAFE",
        sort_order=1,
        is_active=True,
        estimated_duration_minutes=90,
    )
    db.add(row)
    db.flush()
    return row


@pytest.fixture()
def problem_type(db: Session, category: ServiceCategory) -> ProblemType:
    row = ProblemType(
        category_id=category.id,
        code="leak",
        name_ar="تسريب",
        name_en="Leak",
        description_ar="تسريب مياه",
        sort_order=1,
        is_active=True,
        requires_inspection_default=False,
        default_duration_minutes=60,
    )
    db.add(row)
    db.flush()
    return row


@pytest.fixture()
def pricing_rule(db: Session, category: ServiceCategory, zone: CoverageZone) -> PricingRule:
    row = PricingRule(
        category_id=category.id,
        zone_id=zone.id,
        base_service_cost=Decimal("200.00"),
        materials_cost=Decimal("50.00"),
        urgency_multiplier=Decimal("1.00"),
        urgent_flat_fee=Decimal("50.00"),
        inspection_fee=Decimal("80.00"),
        deposit_percent=Decimal("20.00"),
        estimated_duration_minutes=90,
        valid_from=now_utc(),
        is_active=True,
    )
    db.add(row)
    db.flush()
    return row


# ------------------------------------------------------------------- actors


@pytest.fixture()
def customer(db: Session) -> CustomerProfile:
    user = User(phone="+201000000001", is_active=True, is_staff=False)
    db.add(user)
    db.flush()
    row = CustomerProfile(
        user_id=user.id,
        full_name="أحمد محمد",
        email="ahmed@example.com",
        preferred_language="ar",
    )
    db.add(row)
    db.flush()
    return row


@pytest.fixture()
def other_customer(db: Session) -> CustomerProfile:
    user = User(phone="+201000000002", is_active=True, is_staff=False)
    db.add(user)
    db.flush()
    row = CustomerProfile(
        user_id=user.id,
        full_name="سارة علي",
        email="sara@example.com",
        preferred_language="ar",
    )
    db.add(row)
    db.flush()
    return row


@pytest.fixture()
def property_row(db: Session, customer: CustomerProfile) -> Property:
    row = Property(
        customer_id=customer.id,
        label="الشقة الأساسية",
        is_default=True,
        property_type="apartment",
        governorate="Cairo",
        city="Cairo",
        street="شارع التحرير",
        building="10",
        floor="3",
        apartment="7",
    )
    db.add(row)
    db.flush()
    return row


@pytest.fixture()
def technician(db: Session, zone: CoverageZone) -> Technician:
    row = Technician(
        name="محمود حسن",
        phone="+201111111111",
        status="ACTIVE",
        active=True,
        base_zone_id=zone.id,
        total_assignments=0,
        completed_assignments=0,
        late_arrivals=0,
        no_show_count=0,
    )
    db.add(row)
    db.flush()
    return row


@pytest.fixture()
def skilled_technician(db: Session, technician: Technician, category: ServiceCategory, zone: CoverageZone) -> Technician:
    """A technician that `assert_assignable` will accept (§74).

    Assignment requires an ACTIVE technician with a TechnicianSkill row for the
    request's category, so the bare `technician` fixture is deliberately *not*
    assignable — tests that need a real assignment must use this one.
    """
    from app.db.models import TechnicianSkill, TechnicianZone

    db.add(TechnicianSkill(technician_id=technician.id, category_id=category.id, proficiency="EXPERT"))
    db.add(TechnicianZone(technician_id=technician.id, zone_id=zone.id))
    db.flush()
    db.refresh(technician)
    return technician


@pytest.fixture()
def super_admin_staff(db: Session) -> StaffUser:
    user = User(phone="+201222222222", is_active=True, is_staff=True)
    db.add(user)
    db.flush()
    row = StaffUser(
        user_id=user.id,
        employee_code="EMP-1",
        full_name="مدير النظام",
        password_hash=hash_password("ChangeMe!2024"),
        is_active=True,
    )
    db.add(row)
    db.flush()

    role = Role(code="SUPER_ADMIN", name_ar="مدير عام")
    db.add(role)
    db.flush()
    db.add(StaffRoleAssignment(staff_id=row.id, role_id=role.id))
    db.flush()
    return row


@pytest.fixture()
def service_request(
    db: Session, customer: CustomerProfile, category: ServiceCategory, property_row: Property
) -> ServiceRequest:
    row = ServiceRequest(
        reference_code="REQ-TEST-0001",
        customer_id=customer.id,
        property_id=property_row.id,
        category_id=category.id,
        status="DRAFT",
        urgency=Urgency.NORMAL,
        inspection_only=False,
        inspection_required=False,
        problem_description="تسريب تحت الحوض",
    )
    db.add(row)
    db.flush()
    return row


# ------------------------------------------------------------------ helpers


def attach_media(
    db: Session,
    *,
    request: ServiceRequest,
    customer: CustomerProfile,
    kind: str = "IMAGE",
    content: bytes = b"\x89PNG\r\n\x1a\n",
    mime_type: str = "image/png",
    extension: str = "png",
) -> RequestMedia:
    """Attach a stored image to a request, as the upload route would."""
    from app.db.models import RequestMedia
    from app.services.media_service import build_storage_path, make_storage_client

    media_id = uuid4()
    storage_path = build_storage_path(
        customer_id=customer.id,
        request_id=request.id,
        extension=extension,
        media_id=media_id,
    )
    make_storage_client().write(storage_path, content)
    row = RequestMedia(
        id=media_id,
        request_id=request.id,
        kind=kind,
        storage_path=storage_path,
        storage_provider="local",
        mime_type=mime_type,
        size_bytes=len(content),
        width=1,
        height=1,
        checksum_sha256=hashlib.sha256(content).hexdigest(),
        sort_order=0,
        uploaded_by_id=customer.user_id,
    )
    db.add(row)
    db.flush()
    return row


def make_payment(
    db: Session,
    *,
    request: ServiceRequest,
    customer: CustomerProfile,
    amount: str = "100.00",
    method: PaymentMethod = PaymentMethod.CASH,
    status: str = "VERIFIED",
) -> Payment:
    row = Payment(
        request_id=request.id,
        customer_id=customer.id,
        amount=Decimal(amount),
        method=method,
        status=PaymentStatus(status),
        is_deposit=True,
        recorded_at=now_utc(),
        verified_at=now_utc() if status == "VERIFIED" else None,
    )
    db.add(row)
    db.flush()
    return row


def latest_otp(db: Session, phone: str) -> str:
    """Tests cannot reverse the OTP hash, so re-issue a known challenge code."""
    from app.services import auth_service

    user = db.query(User).filter(User.phone == phone).one()
    challenge = (
        db.query(OtpChallenge)
        .filter(OtpChallenge.user_id == user.id, OtpChallenge.consumed_at.is_(None))
        .order_by(OtpChallenge.created_at.desc())
        .first()
    )
    code = "123456"
    import hashlib

    challenge.code_hash = hashlib.sha256(f"otp:{code}".encode()).hexdigest()
    challenge.max_attempts = 99
    challenge.expires_at = now_utc() + timedelta(minutes=30)
    db.flush()
    assert auth_service is not None
    return code


def staff_token(db: Session, staff: StaffUser) -> str:
    """Mint an access token directly, bypassing the login rate limit."""
    from app.core.security import token_service

    token, _expires_at = token_service.create_access_token(
        subject=str(staff.user_id),
        staff_id=str(staff.id),
        roles=tuple(assignment.role.code for assignment in staff.roles),
    )
    return token


def customer_token(db: Session, customer: CustomerProfile) -> str:
    from app.core.security import token_service

    token, _expires_at = token_service.create_access_token(
        subject=str(customer.user_id),
        customer_id=str(customer.id),
    )
    return token


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def grant_all_permissions(db: Session, staff: StaffUser) -> None:
    from app.core.enums import Permission
    from app.db.models import PermissionRecord

    role_ids = [
        assignment.role_id
        for assignment in db.query(StaffRoleAssignment)
        .filter(StaffRoleAssignment.staff_id == staff.id)
        .all()
    ]
    by_code = {
        record.code: record
        for record in db.query(PermissionRecord).all()
    }
    for role_id in role_ids:
        for permission in Permission:
            record = by_code.get(permission.value)
            if record is None:
                record = PermissionRecord(code=permission.value)
                db.add(record)
                db.flush()
                by_code[permission.value] = record
            db.merge(RolePermission(role_id=role_id, permission_id=record.id))
    db.flush()
