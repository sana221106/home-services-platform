"""Permission helpers (§75-§78).

Authorisation is always evaluated server-side. Roles come from the database;
the constants in :mod:`app.core.enums` define the seeded default mapping and are
used to seed ``role_permissions`` for new installations.
"""

from __future__ import annotations

from collections.abc import Iterable

from app.core.enums import Permission, ROLE_PERMISSIONS, StaffRole


def permissions_for_roles(roles: Iterable[StaffRole | str]) -> frozenset[Permission]:
    resolved: set[Permission] = set()
    for role in roles:
        try:
            resolved |= ROLE_PERMISSIONS[StaffRole(str(role))]
        except (ValueError, KeyError):
            continue
    return frozenset(resolved)


def has_permission(granted: Iterable[Permission | str], required: Permission) -> bool:
    for item in granted:
        if str(item) == str(required):
            return True
    return False


def has_any_permission(
    granted: Iterable[Permission | str], required: Iterable[Permission]
) -> bool:
    required_set = {str(item) for item in required}
    return any(str(item) in required_set for item in granted)


def is_super_admin(roles: Iterable[Permission | str] | Iterable[str]) -> bool:
    return any(str(role) == str(StaffRole.SUPER_ADMIN) for role in roles)


def assert_permission(granted: Iterable[Permission | str], required: Permission) -> None:
    """Dependency-style guard raising ``PermissionDeniedError`` on failure."""
    from app.core.exceptions import PermissionDeniedError

    if not has_permission(granted, required):
        raise PermissionDeniedError(
            f"Missing required permission: {required.value}",
            details={"required": required.value},
        )