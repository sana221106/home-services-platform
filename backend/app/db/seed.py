"""Seed reference data for a fresh installation.

Idempotent: every row is matched on its natural key and updated in place, so
running this repeatedly converges instead of duplicating.

Usage::

    python -m app.db.seed            # reference data only
    python -m app.db.seed --demo     # + a demo super admin (dev only)

The demo admin password is read from ``SEED_ADMIN_PASSWORD`` and defaults to a
random value that is printed once, so nothing ships with a known credential.
"""

from __future__ import annotations

import argparse
import secrets
import sys
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.enums import Permission, StaffRole
from app.core.enums import ROLE_PERMISSIONS
from app.core.security import hash_password
from app.db.models import (
    CancellationPolicy,
    CoverageZone,
    PermissionRecord,
    ProblemType,
    Role,
    RolePermission,
    ServiceCategory,
    StaffRoleAssignment,
    StaffUser,
    User,
)
from app.db.session import SessionLocal, session_scope

# --------------------------------------------------------------------- roles

ROLE_NAMES_AR: dict[StaffRole, str] = {
    StaffRole.SUPER_ADMIN: "مدير عام",
    StaffRole.OPERATIONS: "إدارة العمليات",
    StaffRole.CALL_CENTER: "خدمة العملاء",
    StaffRole.FINANCE: "المالية",
    StaffRole.INSPECTION_QC: "الجودة والفحص",
    StaffRole.CONTENT: "إدارة المحتوى",
    StaffRole.MANAGEMENT_READ_ONLY: "إدارة (قراءة فقط)",
}

# --------------------------------------------------------------------- zones

ZONES: tuple[dict[str, object], ...] = (
    {
        "code": "cai_madint_nasr",
        "name_ar": "مدينة نصر - القاهرة",
        "governorate": "Cairo",
        "city": "Cairo",
        "district": "مدينة نصر",
        "center_latitude": Decimal("30.044400"),
        "center_longitude": Decimal("31.235700"),
        "radius_km": Decimal("12"),
        "urgent_multiplier": Decimal("1.30"),
    },
    {
        "code": "cai_maadi",
        "name_ar": "المعادي - القاهرة",
        "governorate": "Cairo",
        "city": "Cairo",
        "district": "المعادي",
        "center_latitude": Decimal("29.953000"),
        "center_longitude": Decimal("31.261000"),
        "radius_km": Decimal("12"),
        "urgent_multiplier": Decimal("1.30"),
    },
    {
        "code": "cai_heliopolis",
        "name_ar": "مصر الجديدة - القاهرة",
        "governorate": "Cairo",
        "city": "Cairo",
        "district": "مصر الجديدة",
        "center_latitude": Decimal("30.113000"),
        "center_longitude": Decimal("31.333000"),
        "radius_km": Decimal("14"),
        "urgent_multiplier": Decimal("1.35"),
    },
    {
        "code": "giza_agouza",
        "name_ar": "الجزيرة - الجيزة",
        "governorate": "Giza",
        "city": "Giza",
        "district": "الجزيرة",
        "center_latitude": Decimal("30.031000"),
        "center_longitude": Decimal("31.216000"),
        "radius_km": Decimal("12"),
        "urgent_multiplier": Decimal("1.30"),
    },
    {
        "code": "giza_zamalek",
        "name_ar": "الزمالك - الجيزة",
        "governorate": "Giza",
        "city": "Giza",
        "district": "الزمالك",
        "center_latitude": Decimal("30.044000"),
        "center_longitude": Decimal("31.224000"),
        "radius_km": Decimal("10"),
        "urgent_multiplier": Decimal("1.35"),
    },
    {
        "code": "alex_smouha",
        "name_ar": "سموحة - الإسكندرية",
        "governorate": "Alexandria",
        "city": "Alexandria",
        "district": "سموحة",
        "center_latitude": Decimal("31.216000"),
        "center_longitude": Decimal("29.959000"),
        "radius_km": Decimal("14"),
        "urgent_multiplier": Decimal("1.30"),
    },
    {
        "code": "damietta_city",
        "name_ar": "دمياط",
        "governorate": "Damietta",
        "city": "Damietta",
        "district": "دمياط",
        "center_latitude": Decimal("31.416700"),
        "center_longitude": Decimal("31.808300"),
        "radius_km": Decimal("14"),
        "urgent_multiplier": Decimal("1.30"),
    },
    {
        "code": "damietta_new",
        "name_ar": "دمياط الجديدة",
        "governorate": "Damietta",
        "city": "New Damietta",
        "district": "دمياط الجديدة",
        "center_latitude": Decimal("31.150000"),
        "center_longitude": Decimal("31.416700"),
        "radius_km": Decimal("18"),
        "urgent_multiplier": Decimal("1.30"),
    },
)

# ---------------------------------------------------------------- categories

CATEGORIES: tuple[dict[str, object], ...] = (
    {
        "code": "plumbing",
        "name_ar": "سباكة",
        "name_en": "Plumbing",
        "description_ar": "مواسير، صنابير، تسريبات، سخانات",
        "icon_key": "plumbing",
        "color_hex": "#1D4ED8",
        "soft_background_hex": "#DBEAFE",
        "sort_order": 10,
        "estimated_duration_minutes": 90,
    },
    {
        "code": "electrical",
        "name_ar": "كهرباء",
        "name_en": "Electrical",
        "description_ar": "لوحات، فيوشات، إنارة، تماسلات",
        "icon_key": "electrical",
        "color_hex": "#B45309",
        "soft_background_hex": "#FEF3C7",
        "sort_order": 20,
        "estimated_duration_minutes": 90,
    },
    {
        "code": "ac",
        "name_ar": "تكييف",
        "name_en": "Air Conditioning",
        "description_ar": "صيانة، تنظيف، شحن فريون، تركيب",
        "icon_key": "ac",
        "color_hex": "#0891B2",
        "soft_background_hex": "#CFFAFE",
        "sort_order": 30,
        "estimated_duration_minutes": 120,
        "requires_inspection_default": True,
    },
    {
        "code": "appliances",
        "name_ar": "أجهزة منزلية",
        "name_en": "Home Appliances",
        "description_ar": "غسالة، ثلاجة، ميكروويف، بوتاجاز",
        "icon_key": "appliances",
        "color_hex": "#7C3AED",
        "soft_background_hex": "#EDE9FE",
        "sort_order": 40,
        "estimated_duration_minutes": 75,
    },
    {
        "code": "carpentry",
        "name_ar": "نجارة",
        "name_en": "Carpentry",
        "description_ar": "أبواب، خزائن، تركيبات خشبية",
        "icon_key": "carpentry",
        "color_hex": "#92400E",
        "soft_background_hex": "#FEF3C7",
        "sort_order": 50,
        "estimated_duration_minutes": 120,
    },
    {
        "code": "painting",
        "name_ar": "دهانات",
        "name_en": "Painting",
        "description_ar": "دهان جدران، أسقف، معجون",
        "icon_key": "painting",
        "color_hex": "#BE185D",
        "soft_background_hex": "#FCE7F3",
        "sort_order": 60,
        "estimated_duration_minutes": 180,
    },
    {
        "code": "cleaning",
        "name_ar": "تنظيف",
        "name_en": "Cleaning",
        "description_ar": "تنظيف شامل، تعقيم، تنظيف سجاد",
        "icon_key": "cleaning",
        "color_hex": "#0D9488",
        "soft_background_hex": "#CCFBF1",
        "sort_order": 70,
        "estimated_duration_minutes": 150,
    },
    {
        "code": "pest_control",
        "name_ar": "مكافحة حشرات",
        "name_en": "Pest Control",
        "description_ar": "صراصير، نمل، بق، نمل أبيض",
        "icon_key": "pest_control",
        "color_hex": "#4D7C0F",
        "soft_background_hex": "#ECFCCB",
        "sort_order": 80,
        "estimated_duration_minutes": 90,
    },
)

# ------------------------------------------------------- problem types

PROBLEM_TYPES: tuple[tuple[str, tuple[tuple[str, str, str], ...]], ...] = (
    (
        "plumbing",
        (
            ("leak", "تسريب مياه", "Water leak", 10, "صوّر مكان التسريب وهو مفتوح"),
            ("blocked_pipe", "انسداد مواسير", "Blocked pipe", 20, "صوّر نقطة الانسداد"),
            ("tap", "خلاط أو مازج", "Tap or mixer", 30, "صوّر نوع الخلاط"),
            ("water_heater", "سخان مياه", "Water heater", 40, "صوّر السخان والتمديدات"),
            ("toilet", "مرحاض", "Toilet", 50, "صوّر المرحاض"),
        ),
    ),
    (
        "electrical",
        (
            ("no_power", "انقطاع الكهرباء", "No power", 10, "صوّر القاطع الرئيسي"),
            ("short_circuit", "دائرة كهربائية", "Short circuit", 20, "افصل القاطع قبل التصوير"),
            ("lighting", "إنارة", "Lighting", 30, "صوّر المصباح والبلكة"),
            ("outlet", "بلك", "Power outlet", 40, "صوّر البلك"),
            ("panel", "لوحة توزيع", "Distribution panel", 50, "لا تفتح اللوحة بنفسك"),
        ),
    ),
    (
        "ac",
        (
            ("not_cooling", "لا يبرد", "Not cooling", 10, "صوّر الوحدة من الخارج"),
            ("leaking_water", "تسريب مياه من الوحدة", "Unit leaking", 20, "أوقف التشغيل فوراً"),
            ("noisy", "صوت مرتفع", "Noisy unit", 30, "صوّر الوحدة أثناء التشغيل"),
            ("cleaning", "تنظيف وصيانة", "Cleaning and maintenance", 40, None),
            ("install", "تركيب وحدة جديدة", "New unit installation", 50, None),
        ),
    ),
    (
        "appliances",
        (
            ("washing_machine", "غسالة", "Washing machine", 10, "صوّر لوحة الجهاز"),
            ("refrigerator", "ثلاجة", "Refrigerator", 20, "صوّر的错误 كود إن ظهر"),
            ("microwave", "ميكروويف", "Microwave", 30, None),
            ("stove", "بوتاجاز", "Stove", 40, "تأكد من فصل الكهرباء/الغاز"),
            ("dishwasher", "غسالة أطباق", "Dishwasher", 50, None),
        ),
    ),
    (
        "carpentry",
        (
            ("door", "باب", "Door", 10, "قِس أبعاد الباب"),
            ("cabinet", "خزانة", "Cabinet", 20, "صوّر الخزانة"),
            ("furniture", "أثاث", "Furniture", 30, "صوّر القطعة بالكامل"),
            ("installation", "تركيب", "Installation", 40, None),
        ),
    ),
    (
        "painting",
        (
            ("wall", "دهان حائط", "Wall painting", 10, "صوّر الحائط كاملاً"),
            ("ceiling", "دهان سقف", "Ceiling painting", 20, None),
            ("exterior", "دهان خارجي", "Exterior painting", 30, None),
        ),
    ),
    (
        "cleaning",
        (
            ("deep_clean", "تنظيف شامل", "Deep cleaning", 10, "حدّد المساحة التقريبية"),
            ("sofa", "تنظيف كنب", "Sofa cleaning", 20, None),
            ("carpet", "تنظيف سجاد", "Carpet cleaning", 30, None),
            ("sanitizing", "تعقيم", "Sanitizing", 40, None),
        ),
    ),
    (
        "pest_control",
        (
            ("cockroaches", "صراصير", "Cockroaches", 10, "صوّر أماكن ظهورها"),
            ("ants", "نمل", "Ants", 20, None),
            ("bedbugs", "بق", "Bed bugs", 30, None),
            ("termites", "نمل أبيض", "Termites", 40, None),
        ),
    ),
)

# ---------------------------------------------------- cancellation policies

CANCELLATION_POLICIES: tuple[dict[str, object], ...] = (
    {
        "name_ar": "إلغاء مجاني قبل 24 ساعة",
        "window_minutes": 1440,
        "refund_percent": Decimal("100"),
        "requires_approval": False,
        "rules": [{"code": "FULL_REFUND", "label_ar": "استرجاع كامل"}],
    },
    {
        "name_ar": "إلغاء قبل 12 ساعة - استرجاع جزئي",
        "window_minutes": 720,
        "refund_percent": Decimal("50"),
        "requires_approval": False,
        "rules": [{"code": "PARTIAL_REFUND", "label_ar": "استرجاع 50% من العربون"}],
    },
    {
        "name_ar": "إلغاء بعد بدء التنفيذ - يتطلب موافقة",
        "window_minutes": 120,
        "refund_percent": Decimal("0"),
        "requires_approval": True,
        "rules": [
            {
                "code": "NO_REFUND",
                "label_ar": "لا يوجد استرجاع - يتطلب موافقة مدير",
            }
        ],
    },
)


# ------------------------------------------------------------------ helpers


def seed_permissions(session: Session) -> dict[str, PermissionRecord]:
    existing = {record.code: record for record in session.scalars(select(PermissionRecord))}
    for permission in Permission:
        if permission.value not in existing:
            record = PermissionRecord(code=permission.value)
            session.add(record)
            existing[permission.value] = record
    session.flush()
    return existing


def seed_roles(session: Session) -> dict[StaffRole, Role]:
    permissions = seed_permissions(session)
    existing = {role.code: role for role in session.scalars(select(Role))}
    for role in StaffRole:
        db_role = existing.get(role.value)
        if db_role is None:
            db_role = Role(code=role.value, name_ar=ROLE_NAMES_AR[role])
            session.add(db_role)
            session.flush()
            existing[role.value] = db_role

        granted = {
            row.permission_id
            for row in session.scalars(
                select(RolePermission).where(RolePermission.role_id == db_role.id)
            )
        }
        for permission in ROLE_PERMISSIONS[role]:
            permission_id = permissions[permission.value].id
            if permission_id not in granted:
                session.add(RolePermission(role_id=db_role.id, permission_id=permission_id))
        session.flush()
    return existing


def seed_zones(session: Session) -> None:
    for row in ZONES:
        zone = session.scalar(select(CoverageZone).where(CoverageZone.code == row["code"]))
        if zone is None:
            zone = CoverageZone(code=row["code"])
            session.add(zone)
        for key, value in row.items():
            setattr(zone, key, value)
        zone.is_active = True
    session.flush()


def seed_catalog(session: Session) -> None:
    categories: dict[str, ServiceCategory] = {}
    for row in CATEGORIES:
        category = session.scalar(
            select(ServiceCategory).where(ServiceCategory.code == row["code"])
        )
        if category is None:
            category = ServiceCategory(code=row["code"])
            session.add(category)
        for key, value in row.items():
            setattr(category, key, value)
        category.is_active = True
        categories[row["code"]] = category
    session.flush()

    for category_code, problems in PROBLEM_TYPES:
        category = categories[category_code]
        for code, name_ar, name_en, sort_order, hint_ar in problems:
            problem = session.scalar(
                select(ProblemType).where(
                    ProblemType.category_id == category.id, ProblemType.code == code
                )
            )
            if problem is None:
                problem = ProblemType(category_id=category.id, code=code)
                session.add(problem)
            problem.name_ar = name_ar
            problem.name_en = name_en
            problem.sort_order = sort_order
            problem.hint_ar = hint_ar
            problem.is_active = True
    session.flush()


def seed_cancellation_policies(session: Session) -> None:
    for row in CANCELLATION_POLICIES:
        policy = session.scalar(
            select(CancellationPolicy).where(CancellationPolicy.name_ar == row["name_ar"])
        )
        if policy is None:
            policy = CancellationPolicy(name_ar=row["name_ar"])
            session.add(policy)
        for key, value in row.items():
            setattr(policy, key, value)
        policy.is_active = True
    session.flush()


def seed_demo_admin(session: Session) -> tuple[str, str]:
    """Create a super admin for local development. Returns (phone, password)."""
    from app.core.config import settings

    password = settings.seed_admin_password or secrets.token_urlsafe(18)
    phone = settings.seed_admin_phone

    user = session.scalar(select(User).where(User.phone == phone))
    if user is None:
        user = User(phone=phone, is_active=True, is_staff=True)
        session.add(user)
        session.flush()

    staff = session.scalar(select(StaffUser).where(StaffUser.user_id == user.id))
    if staff is None:
        staff = StaffUser(
            user_id=user.id,
            employee_code="EMP-ADMIN",
            full_name="مدير النظام",
            password_hash=hash_password(password),
            is_active=True,
        )
        session.add(staff)
        session.flush()
    else:
        staff.password_hash = hash_password(password)

    role = session.scalar(select(Role).where(Role.code == StaffRole.SUPER_ADMIN.value))
    already = session.scalar(
        select(StaffRoleAssignment).where(
            StaffRoleAssignment.staff_id == staff.id, StaffRoleAssignment.role_id == role.id
        )
    )
    if already is None:
        session.add(StaffRoleAssignment(staff_id=staff.id, role_id=role.id))
    session.flush()
    return phone, password


# ---------------------------------------------------------------------- main


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Seed reference data.")
    parser.add_argument(
        "--demo",
        action="store_true",
        help="also create a development super admin account",
    )
    args = parser.parse_args(argv)

    with session_scope() as session:
        seed_roles(session)
        seed_zones(session)
        seed_catalog(session)
        seed_cancellation_policies(session)

        if args.demo:
            phone, password = seed_demo_admin(session)

    print(f"seeded {len(Permission)} permissions, {len(StaffRole)} roles, "
          f"{len(ZONES)} zones, {len(CATEGORIES)} categories, "
          f"{len(CANCELLATION_POLICIES)} cancellation policies")
    if args.demo:
        print()
        print("  demo super admin")
        print(f"    phone:    {phone}")
        print(f"    password: {password}")
        print("  change this password immediately and never use it in production")
    return 0


if __name__ == "__main__":
    sys.exit(main())
