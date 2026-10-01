"""Domain enumerations.

Single source of truth for every lifecycle state in the platform.
SQLAlchemy columns and Pydantic schemas both import from here so a state can
never drift between the API contract and the database enum.
"""

from __future__ import annotations

from enum import StrEnum


class RequestStatus(StrEnum):
    """Service request lifecycle (§62)."""

    DRAFT = "DRAFT"
    SUBMITTED = "SUBMITTED"
    UNDER_REVIEW = "UNDER_REVIEW"
    NEED_MORE_INFORMATION = "NEED_MORE_INFORMATION"
    INSPECTION_REQUIRED = "INSPECTION_REQUIRED"
    INSPECTION_SCHEDULED = "INSPECTION_SCHEDULED"
    INSPECTION_IN_PROGRESS = "INSPECTION_IN_PROGRESS"
    INSPECTION_COMPLETED = "INSPECTION_COMPLETED"
    QUOTE_PREPARATION = "QUOTE_PREPARATION"
    QUOTE_SENT = "QUOTE_SENT"
    AWAITING_CUSTOMER_APPROVAL = "AWAITING_CUSTOMER_APPROVAL"
    QUOTE_REJECTED = "QUOTE_REJECTED"
    DEPOSIT_PENDING = "DEPOSIT_PENDING"
    DEPOSIT_VERIFICATION = "DEPOSIT_VERIFICATION"
    CONFIRMED = "CONFIRMED"
    TECHNICIAN_ASSIGNMENT_PENDING = "TECHNICIAN_ASSIGNMENT_PENDING"
    TECHNICIAN_ASSIGNED = "TECHNICIAN_ASSIGNED"
    ON_THE_WAY = "ON_THE_WAY"
    ARRIVED = "ARRIVED"
    WORK_IN_PROGRESS = "WORK_IN_PROGRESS"
    SERVICE_COMPLETED = "SERVICE_COMPLETED"
    PAYMENT_PENDING = "PAYMENT_PENDING"
    PAYMENT_VERIFICATION = "PAYMENT_VERIFICATION"
    PAID = "PAID"
    AWAITING_RATING = "AWAITING_RATING"
    COMPLAINT_OPEN = "COMPLAINT_OPEN"
    COMPLAINT_UNDER_REVIEW = "COMPLAINT_UNDER_REVIEW"
    REVISIT_SCHEDULED = "REVISIT_SCHEDULED"
    RESOLVED = "RESOLVED"
    CLOSED = "CLOSED"
    CANCELLED = "CANCELLED"


#: Explicit, validated transition graph (§62 "Never allow arbitrary transitions").
#: ``SUBMITTED -> PAID`` is deliberately absent.
REQUEST_TRANSITIONS: dict[RequestStatus, frozenset[RequestStatus]] = {
    RequestStatus.DRAFT: frozenset({RequestStatus.SUBMITTED, RequestStatus.CANCELLED}),
    RequestStatus.SUBMITTED: frozenset(
        {RequestStatus.UNDER_REVIEW, RequestStatus.CANCELLED}
    ),
    RequestStatus.UNDER_REVIEW: frozenset(
        {
            RequestStatus.NEED_MORE_INFORMATION,
            RequestStatus.INSPECTION_REQUIRED,
            RequestStatus.QUOTE_PREPARATION,
            RequestStatus.CANCELLED,
        }
    ),
    RequestStatus.NEED_MORE_INFORMATION: frozenset(
        {
            RequestStatus.UNDER_REVIEW,
            RequestStatus.CANCELLED,
        }
    ),
    RequestStatus.INSPECTION_REQUIRED: frozenset(
        {
            RequestStatus.INSPECTION_SCHEDULED,
            RequestStatus.QUOTE_PREPARATION,
            RequestStatus.CANCELLED,
        }
    ),
    RequestStatus.INSPECTION_SCHEDULED: frozenset(
        {
            RequestStatus.INSPECTION_IN_PROGRESS,
            RequestStatus.CANCELLED,
        }
    ),
    RequestStatus.INSPECTION_IN_PROGRESS: frozenset(
        {RequestStatus.INSPECTION_COMPLETED, RequestStatus.CANCELLED}
    ),
    RequestStatus.INSPECTION_COMPLETED: frozenset(
        {
            RequestStatus.QUOTE_PREPARATION,
            RequestStatus.REVISIT_SCHEDULED,
            RequestStatus.CANCELLED,
        }
    ),
    RequestStatus.QUOTE_PREPARATION: frozenset(
        {
            RequestStatus.QUOTE_SENT,
            RequestStatus.NEED_MORE_INFORMATION,
            RequestStatus.CANCELLED,
        }
    ),
    RequestStatus.QUOTE_SENT: frozenset(
        {
            RequestStatus.AWAITING_CUSTOMER_APPROVAL,
            RequestStatus.QUOTE_PREPARATION,
            RequestStatus.CANCELLED,
        }
    ),
    RequestStatus.AWAITING_CUSTOMER_APPROVAL: frozenset(
        {
            RequestStatus.QUOTE_REJECTED,
            RequestStatus.DEPOSIT_PENDING,
            RequestStatus.CONFIRMED,
            RequestStatus.CANCELLED,
        }
    ),
    RequestStatus.QUOTE_REJECTED: frozenset(
        {
            RequestStatus.QUOTE_PREPARATION,
            RequestStatus.CANCELLED,
        }
    ),
    RequestStatus.DEPOSIT_PENDING: frozenset(
        {
            RequestStatus.DEPOSIT_VERIFICATION,
            RequestStatus.CANCELLED,
        }
    ),
    RequestStatus.DEPOSIT_VERIFICATION: frozenset(
        {
            RequestStatus.CONFIRMED,
            RequestStatus.DEPOSIT_PENDING,
            RequestStatus.CANCELLED,
        }
    ),
    RequestStatus.CONFIRMED: frozenset(
        {
            RequestStatus.TECHNICIAN_ASSIGNMENT_PENDING,
            RequestStatus.CANCELLED,
        }
    ),
    RequestStatus.TECHNICIAN_ASSIGNMENT_PENDING: frozenset(
        {RequestStatus.TECHNICIAN_ASSIGNED, RequestStatus.CANCELLED}
    ),
    RequestStatus.TECHNICIAN_ASSIGNED: frozenset(
        {
            RequestStatus.ON_THE_WAY,
            RequestStatus.ARRIVED,
            RequestStatus.CANCELLED,
        }
    ),
    RequestStatus.ON_THE_WAY: frozenset({RequestStatus.ARRIVED, RequestStatus.CANCELLED}),
    RequestStatus.ARRIVED: frozenset(
        {
            RequestStatus.WORK_IN_PROGRESS,
            RequestStatus.CANCELLED,
        }
    ),
    RequestStatus.WORK_IN_PROGRESS: frozenset(
        {
            RequestStatus.SERVICE_COMPLETED,
            RequestStatus.COMPLAINT_OPEN,
        }
    ),
    RequestStatus.SERVICE_COMPLETED: frozenset(
        {
            RequestStatus.PAYMENT_PENDING,
            RequestStatus.COMPLAINT_OPEN,
            RequestStatus.CLOSED,
        }
    ),
    RequestStatus.PAYMENT_PENDING: frozenset(
        {
            RequestStatus.PAYMENT_VERIFICATION,
            RequestStatus.COMPLAINT_OPEN,
        }
    ),
    RequestStatus.PAYMENT_VERIFICATION: frozenset(
        {
            RequestStatus.PAID,
            RequestStatus.PAYMENT_PENDING,
            RequestStatus.COMPLAINT_OPEN,
        }
    ),
    RequestStatus.PAID: frozenset(
        {
            RequestStatus.AWAITING_RATING,
            RequestStatus.COMPLAINT_OPEN,
            RequestStatus.CLOSED,
        }
    ),
    RequestStatus.AWAITING_RATING: frozenset(
        {
            RequestStatus.CLOSED,
            RequestStatus.COMPLAINT_OPEN,
        }
    ),
    RequestStatus.COMPLAINT_OPEN: frozenset(
        {
            RequestStatus.COMPLAINT_UNDER_REVIEW,
            RequestStatus.RESOLVED,
        }
    ),
    RequestStatus.COMPLAINT_UNDER_REVIEW: frozenset(
        {
            RequestStatus.REVISIT_SCHEDULED,
            RequestStatus.RESOLVED,
        }
    ),
    RequestStatus.REVISIT_SCHEDULED: frozenset(
        {
            RequestStatus.REVISIT_SCHEDULED,
            RequestStatus.RESOLVED,
        }
    ),
    RequestStatus.RESOLVED: frozenset(
        {
            RequestStatus.CLOSED,
            RequestStatus.REVISIT_SCHEDULED,
        }
    ),
    RequestStatus.CLOSED: frozenset(),
    RequestStatus.CANCELLED: frozenset(),
}

#: Terminal states cannot be mutated at all.
TERMINAL_REQUEST_STATUSES: frozenset[RequestStatus] = frozenset(
    {RequestStatus.CLOSED, RequestStatus.CANCELLED}
)


def can_transition(current: RequestStatus, target: RequestStatus) -> bool:
    """Return whether ``current -> target`` is a legal lifecycle move."""
    return target in REQUEST_TRANSITIONS.get(current, frozenset())


class Urgency(StrEnum):
    NORMAL = "NORMAL"
    URGENT = "URGENT"


class InspectionStatus(StrEnum):
    PENDING = "PENDING"
    SCHEDULED = "SCHEDULED"
    IN_PROGRESS = "IN_PROGRESS"
    COMPLETED = "COMPLETED"
    CANCELLED = "CANCELLED"


class QuoteStatus(StrEnum):
    DRAFT = "DRAFT"
    SENT = "SENT"
    ACCEPTED = "ACCEPTED"
    REJECTED = "REJECTED"
    EXPIRED = "EXPIRED"
    SUPERSEDED = "SUPERSEDED"


class PaymentMethod(StrEnum):
    CASH = "CASH"
    VODAFONE_CASH = "VODAFONE_CASH"
    INSTAPAY = "INSTAPAY"


class PaymentStatus(StrEnum):
    PENDING = "PENDING"
    VERIFICATION_PENDING = "VERIFICATION_PENDING"
    VERIFIED = "VERIFIED"
    REJECTED = "REJECTED"
    REFUNDED = "REFUNDED"
    PARTIALLY_REFUNDED = "PARTIALLY_REFUNDED"


class DepositStatus(StrEnum):
    NOT_REQUIRED = "NOT_REQUIRED"
    PENDING = "PENDING"
    SUBMITTED = "SUBMITTED"
    VERIFIED = "VERIFIED"
    REJECTED = "REJECTED"
    REFUNDED = "REFUNDED"
    PARTIALLY_REFUNDED = "PARTIALLY_REFUNDED"


class RefundStatus(StrEnum):
    PENDING = "PENDING"
    APPROVED = "APPROVED"
    PROCESSED = "PROCESSED"
    REJECTED = "REJECTED"


class CancellationReason(StrEnum):
    CUSTOMER_REQUEST = "CUSTOMER_REQUEST"
    NO_SHOW = "NO_SHOW"
    TECHNICIAN_UNAVAILABLE = "TECHNICIAN_UNAVAILABLE"
    OUT_OF_COVERAGE = "OUT_OF_COVERAGE"
    POLICY_VIOLATION = "POLICY_VIOLATION"
    OTHER = "OTHER"


class ComplaintStatus(StrEnum):
    OPEN = "OPEN"
    UNDER_REVIEW = "UNDER_REVIEW"
    QC_REQUIRED = "QC_REQUIRED"
    REVISIT_REQUIRED = "REVISIT_REQUIRED"
    REVISIT_SCHEDULED = "REVISIT_SCHEDULED"
    RESOLVED = "RESOLVED"
    CLOSED = "CLOSED"


class ComplaintReason(StrEnum):
    WORK_NOT_DONE = "WORK_NOT_DONE"
    POOR_QUALITY = "POOR_QUALITY"
    OVERCHARGE = "OVERCHARGE"
    TECHNICIAN_LATE = "TECHNICIAN_LATE"
    DAMAGE = "DAMAGE"
    RECURRING_FAULT = "RECURRING_FAULT"
    OTHER = "OTHER"


class ReviewStatus(StrEnum):
    PENDING = "PENDING"
    APPROVED = "APPROVED"
    HIDDEN = "HIDDEN"
    REJECTED = "REJECTED"


class TechnicianStatus(StrEnum):
    ACTIVE = "ACTIVE"
    ON_LEAVE = "ON_LEAVE"
    SUSPENDED = "SUSPENDED"
    INACTIVE = "INACTIVE"


class AssignmentStatus(StrEnum):
    ASSIGNED = "ASSIGNED"
    EN_ROUTE = "EN_ROUTE"
    ARRIVED = "ARRIVED"
    IN_PROGRESS = "IN_PROGRESS"
    COMPLETED = "COMPLETED"
    CANCELLED = "CANCELLED"
    NO_SHOW = "NO_SHOW"


class NotificationType(StrEnum):
    REQUEST_RECEIVED = "REQUEST_RECEIVED"
    NEED_MORE_INFORMATION = "NEED_MORE_INFORMATION"
    QUOTE_READY = "QUOTE_READY"
    QUOTE_REVISED = "QUOTE_REVISED"
    DEPOSIT_REQUIRED = "DEPOSIT_REQUIRED"
    DEPOSIT_VERIFIED = "DEPOSIT_VERIFIED"
    REQUEST_CONFIRMED = "REQUEST_CONFIRMED"
    APPOINTMENT_SCHEDULED = "APPOINTMENT_SCHEDULED"
    TECHNICIAN_ASSIGNED = "TECHNICIAN_ASSIGNED"
    EXPECTED_ARRIVAL_UPDATED = "EXPECTED_ARRIVAL_UPDATED"
    ON_THE_WAY = "ON_THE_WAY"
    SERVICE_STARTED = "SERVICE_STARTED"
    SERVICE_COMPLETED = "SERVICE_COMPLETED"
    PAYMENT_REQUIRED = "PAYMENT_REQUIRED"
    PAYMENT_CONFIRMED = "PAYMENT_CONFIRMED"
    COMPLAINT_UPDATE = "COMPLAINT_UPDATE"
    RATING_REMINDER = "RATING_REMINDER"


class StaffRole(StrEnum):
    """Core RBAC roles (§75)."""

    SUPER_ADMIN = "SUPER_ADMIN"
    OPERATIONS = "OPERATIONS"
    CALL_CENTER = "CALL_CENTER"
    FINANCE = "FINANCE"
    INSPECTION_QC = "INSPECTION_QC"
    CONTENT = "CONTENT"
    MANAGEMENT_READ_ONLY = "MANAGEMENT_READ_ONLY"


class Permission(StrEnum):
    """Granular permissions mapped onto roles by ``role_permissions``."""

    # Requests / operations
    REQUEST_READ = "request:read"
    REQUEST_REVIEW = "request:review"
    REQUEST_STATUS_OVERRIDE = "request:status_override"
    REQUEST_REQUEST_INFO = "request:request_info"
    QUOTE_READ = "quote:read"
    QUOTE_WRITE = "quote:write"
    QUOTE_DISCOUNT_APPROVE = "quote:discount_approve"
    # Workforce
    TECHNICIAN_READ = "technician:read"
    TECHNICIAN_WRITE = "technician:write"
    TECHNICIAN_ASSIGN = "technician:assign"
    # Customers / support
    CUSTOMER_READ = "customer:read"
    CUSTOMER_READ_PII = "customer:read_pii"
    COMPLAINT_READ = "complaint:read"
    COMPLAINT_WRITE = "complaint:write"
    COMPLAINT_ASSIGN = "complaint:assign"
    COMPLAINT_RESOLVE = "complaint:resolve"
    CHAT_READ = "chat:read"
    CHAT_SEND = "chat:send"
    CALL_LOG_WRITE = "call_log:write"
    FOLLOW_UP_WRITE = "follow_up:write"
    # Finance
    PAYMENT_READ = "payment:read"
    PAYMENT_RECORD = "payment:record"
    PAYMENT_VERIFY = "payment:verify"
    REFUND_APPROVE = "refund:approve"
    REFUND_PROCESS = "refund:process"
    # Quality
    INSPECTION_READ = "inspection:read"
    INSPECTION_WRITE = "inspection:write"
    QC_REVIEW = "qc:review"
    REWORK_WRITE = "rework:write"
    REVIEW_READ = "review:read"
    REVIEW_MODERATE = "review:moderate"
    # Platform
    CATALOG_WRITE = "catalog:write"
    PRICING_WRITE = "pricing:write"
    ANALYTICS_READ = "analytics:read"
    AUDIT_READ = "audit:read"
    STAFF_READ = "staff:read"
    STAFF_WRITE = "staff:write"
    ROLE_WRITE = "role:write"
    SETTINGS_WRITE = "settings:write"
    AI_CLASSIFY = "ai:classify"
    AI_REVIEW = "ai:review"


#: Role -> permission mapping (§75, §76, §77).
#:
#: Finance deliberately has no ``staff:write`` / ``role:write`` /
#: ``technician:write`` / ``settings:write`` (spec §76).
#: Call Center deliberately has no ``pricing:write`` / ``role:write`` /
#: ``settings:write`` (spec §77).
ROLE_PERMISSIONS: dict[StaffRole, frozenset[Permission]] = {
    StaffRole.SUPER_ADMIN: frozenset(Permission),
    StaffRole.OPERATIONS: frozenset(
        {
            Permission.REQUEST_READ,
            Permission.REQUEST_REVIEW,
            Permission.REQUEST_REQUEST_INFO,
            Permission.REQUEST_STATUS_OVERRIDE,
            Permission.QUOTE_READ,
            Permission.QUOTE_WRITE,
            Permission.QUOTE_DISCOUNT_APPROVE,
            Permission.TECHNICIAN_READ,
            Permission.TECHNICIAN_WRITE,
            Permission.TECHNICIAN_ASSIGN,
            Permission.CUSTOMER_READ,
            Permission.CUSTOMER_READ_PII,
            Permission.COMPLAINT_READ,
            Permission.COMPLAINT_WRITE,
            Permission.COMPLAINT_ASSIGN,
            Permission.COMPLAINT_RESOLVE,
            Permission.CHAT_READ,
            Permission.CHAT_SEND,
            Permission.INSPECTION_READ,
            Permission.INSPECTION_WRITE,
            Permission.REWORK_WRITE,
            Permission.REVIEW_READ,
            Permission.REVIEW_MODERATE,
            Permission.CATALOG_WRITE,
            Permission.ANALYTICS_READ,
            Permission.AI_CLASSIFY,
            Permission.AI_REVIEW,
        }
    ),
    StaffRole.CALL_CENTER: frozenset(
        {
            Permission.REQUEST_READ,
            Permission.QUOTE_READ,
            Permission.PAYMENT_READ,
            Permission.CUSTOMER_READ,
            Permission.CUSTOMER_READ_PII,
            Permission.COMPLAINT_READ,
            Permission.COMPLAINT_WRITE,
            Permission.CHAT_READ,
            Permission.CHAT_SEND,
            Permission.CALL_LOG_WRITE,
            Permission.FOLLOW_UP_WRITE,
            Permission.INSPECTION_READ,
            Permission.REVIEW_READ,
            Permission.PAYMENT_RECORD,
        }
    ),
    StaffRole.FINANCE: frozenset(
        {
            Permission.REQUEST_READ,
            Permission.QUOTE_READ,
            Permission.PAYMENT_READ,
            Permission.PAYMENT_RECORD,
            Permission.PAYMENT_VERIFY,
            Permission.REFUND_APPROVE,
            Permission.REFUND_PROCESS,
            Permission.CUSTOMER_READ,
            Permission.ANALYTICS_READ,
        }
    ),
    StaffRole.INSPECTION_QC: frozenset(
        {
            Permission.REQUEST_READ,
            Permission.QUOTE_READ,
            Permission.INSPECTION_READ,
            Permission.INSPECTION_WRITE,
            Permission.QC_REVIEW,
            Permission.REWORK_WRITE,
            Permission.COMPLAINT_READ,
            Permission.COMPLAINT_WRITE,
            Permission.CUSTOMER_READ,
            Permission.TECHNICIAN_READ,
        }
    ),
    StaffRole.CONTENT: frozenset(
        {
            Permission.REVIEW_READ,
            Permission.REVIEW_MODERATE,
            Permission.CATALOG_WRITE,
        }
    ),
    StaffRole.MANAGEMENT_READ_ONLY: frozenset(
        {
            Permission.REQUEST_READ,
            Permission.QUOTE_READ,
            Permission.PAYMENT_READ,
            Permission.CUSTOMER_READ,
            Permission.TECHNICIAN_READ,
            Permission.COMPLAINT_READ,
            Permission.INSPECTION_READ,
            Permission.REVIEW_READ,
            Permission.ANALYTICS_READ,
            Permission.AUDIT_READ,
        }
    ),
}


class AuditAction(StrEnum):
    PRICE_CHANGE = "PRICE_CHANGE"
    QUOTE_CREATED = "QUOTE_CREATED"
    QUOTE_REVISED = "QUOTE_REVISED"
    DISCOUNT_CHANGE = "DISCOUNT_CHANGE"
    REFUND = "REFUND"
    PAYMENT_VERIFICATION = "PAYMENT_VERIFICATION"
    TECHNICIAN_ASSIGNMENT = "TECHNICIAN_ASSIGNMENT"
    STATUS_OVERRIDE = "STATUS_OVERRIDE"
    COMPLAINT_RESOLUTION = "COMPLAINT_RESOLUTION"
    REVIEW_MODERATION = "REVIEW_MODERATION"
    ROLE_CHANGE = "ROLE_CHANGE"
    PERMISSION_CHANGE = "PERMISSION_CHANGE"
    DEPOSIT_POLICY_CHANGE = "DEPOSIT_POLICY_CHANGE"


class MediaKind(StrEnum):
    IMAGE = "IMAGE"


class AnnotationType(StrEnum):
    """Normalized geometry primitives (§80)."""

    CIRCLE = "circle"
    RECT = "rect"
    ARROW = "arrow"
    FREEHAND = "freehand"
    POINT = "point"


class FollowUpOutcome(StrEnum):
    NO_ANSWER = "NO_ANSWER"
    CALLBACK_SCHEDULED = "CALLBACK_SCHEDULED"
    RESOLVED = "RESOLVED"
    ESCALATED = "ESCALATED"