"""Aggregated model registry.

Import order matters: SQLAlchemy resolves string annotations through this
registry, so every module must be imported here for `Base.metadata` to be
complete before Alembic autogenerate or test setup runs.
"""

from app.db.base import Base
from app.db.models.catalog import (
    CancellationPolicy,
    CoverageZone,
    PricingRule,
    ProblemType,
    ServiceAreaSnapshot,
    ServiceCategory,
)
from app.db.models.finance import (
    Cancellation,
    Deposit,
    Invoice,
    Payment,
    PaymentProof,
    Receipt,
    Refund,
)
from app.db.models.identity import (
    CustomerProfile,
    OtpChallenge,
    OtpDeliveryLog,
    PermissionRecord,
    RefreshToken,
    Role,
    RolePermission,
    StaffRoleAssignment,
    StaffUser,
    User,
)
from app.db.models.intelligence import (
    AiClassification,
    AnalyticsEvent,
    AuditLog,
    MaintenanceRecord,
)
from app.db.models.properties import Property, PropertyContact
from app.db.models.quotes import Quote, QuoteItem, QuoteRevision
from app.db.models.requests import (
    Inspection,
    InspectionReport,
    OrderAddressSnapshot,
    PhotoAnnotation,
    RequestEvent,
    RequestMedia,
    RequestStatusHistory,
    ServiceRequest,
)
from app.db.models.support import (
    Complaint,
    ComplaintAttachment,
    Conversation,
    DeviceToken,
    Message,
    MessageAttachment,
    Notification,
    Review,
    ReworkVisit,
    StaffNote,
    SupportCallLog,
)
from app.db.models.workforce import (
    Appointment,
    Assignment,
    Technician,
    TechnicianAvailability,
    TechnicianSkill,
    TechnicianZone,
)

__all__ = [
    "AiClassification",
    "AnalyticsEvent",
    "Appointment",
    "Assignment",
    "AuditLog",
    "Base",
    "Cancellation",
    "CancellationPolicy",
    "Complaint",
    "ComplaintAttachment",
    "Conversation",
    "CoverageZone",
    "CustomerProfile",
    "Deposit",
    "DeviceToken",
    "Inspection",
    "InspectionReport",
    "Invoice",
    "MaintenanceRecord",
    "Message",
    "MessageAttachment",
    "Notification",
    "OrderAddressSnapshot",
    "OtpChallenge",
    "OtpDeliveryLog",
    "Payment",
    "PaymentProof",
    "PermissionRecord",
    "PhotoAnnotation",
    "PricingRule",
    "ProblemType",
    "Property",
    "PropertyContact",
    "Quote",
    "QuoteItem",
    "QuoteRevision",
    "Receipt",
    "RefreshToken",
    "Refund",
    "RequestEvent",
    "RequestMedia",
    "RequestStatusHistory",
    "Review",
    "ReworkVisit",
    "Role",
    "RolePermission",
    "ServiceAreaSnapshot",
    "ServiceCategory",
    "ServiceRequest",
    "StaffNote",
    "StaffRoleAssignment",
    "StaffUser",
    "SupportCallLog",
    "Technician",
    "TechnicianAvailability",
    "TechnicianSkill",
    "TechnicianZone",
    "User",
]