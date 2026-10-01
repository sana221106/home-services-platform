"""Arabic display labels for business enums.

Client-facing copy lives here so the wording is identical in the app, the API
and the admin dashboard (§20, §112). No English leaks into the customer UI.
"""

from __future__ import annotations

from app.core.enums import (
    AssignmentStatus,
    CancellationReason,
    ComplaintReason,
    ComplaintStatus,
    DepositStatus,
    InspectionStatus,
    PaymentMethod,
    PaymentStatus,
    QuoteStatus,
    RefundStatus,
    RequestStatus,
    TechnicianStatus,
    Urgency,
)

REQUEST_STATUS_LABELS: dict[RequestStatus, str] = {
    RequestStatus.DRAFT: "مسودة",
    RequestStatus.SUBMITTED: "تم الاستلام",
    RequestStatus.UNDER_REVIEW: "قيد المراجعة",
    RequestStatus.NEED_MORE_INFORMATION: "مطلوب معلومات إضافية",
    RequestStatus.INSPECTION_REQUIRED: "مطلوب معاينة",
    RequestStatus.INSPECTION_SCHEDULED: "تم جدولة المعاينة",
    RequestStatus.INSPECTION_IN_PROGRESS: "المعاينة جارية",
    RequestStatus.INSPECTION_COMPLETED: "اكتملت المعاينة",
    RequestStatus.QUOTE_PREPARATION: "قيد إعداد عرض السعر",
    RequestStatus.QUOTE_SENT: "تم إرسال عرض السعر",
    RequestStatus.AWAITING_CUSTOMER_APPROVAL: "بانتظار موافقتك",
    RequestStatus.QUOTE_REJECTED: "تم رفض عرض السعر",
    RequestStatus.DEPOSIT_PENDING: "في انتظار الدفع المقدم",
    RequestStatus.DEPOSIT_VERIFICATION: "قيد التحقق من الدفع المقدم",
    RequestStatus.CONFIRMED: "تم تأكيد الحجز",
    RequestStatus.TECHNICIAN_ASSIGNMENT_PENDING: "في انتظار تعيين فني",
    RequestStatus.TECHNICIAN_ASSIGNED: "تم تعيين فني",
    RequestStatus.ON_THE_WAY: "الفني في الطريق",
    RequestStatus.ARRIVED: "وصل الفني",
    RequestStatus.WORK_IN_PROGRESS: "العمل جارٍ",
    RequestStatus.SERVICE_COMPLETED: "تم إنجاز الخدمة",
    RequestStatus.PAYMENT_PENDING: "في انتظار الدفع",
    RequestStatus.PAYMENT_VERIFICATION: "قيد التحقق من الدفع",
    RequestStatus.PAID: "تم الدفع",
    RequestStatus.AWAITING_RATING: "بانتظار التقييم",
    RequestStatus.COMPLAINT_OPEN: "شكوى مفتوحة",
    RequestStatus.COMPLAINT_UNDER_REVIEW: "شكوى قيد المراجعة",
    RequestStatus.REVISIT_SCHEDULED: "تمت جدولة زيارة إصلاح",
    RequestStatus.RESOLVED: "تم الحل",
    RequestStatus.CLOSED: "تم إغلاق الطلب",
    RequestStatus.CANCELLED: "تم إلغاء الطلب",
}

ASSIGNMENT_STATUS_LABELS: dict[AssignmentStatus, str] = {
    AssignmentStatus.ASSIGNED: "مُعيَّن",
    AssignmentStatus.EN_ROUTE: "في الطريق",
    AssignmentStatus.ARRIVED: "وصل",
    AssignmentStatus.IN_PROGRESS: "قيد التنفيذ",
    AssignmentStatus.COMPLETED: "مكتمل",
    AssignmentStatus.CANCELLED: "ملغي",
    AssignmentStatus.NO_SHOW: "تعذر الحضور",
}

URGENCY_LABELS: dict[Urgency, str] = {
    Urgency.NORMAL: "عادي",
    Urgency.URGENT: "عاجل",
}

PAYMENT_STATUS_LABELS: dict[PaymentStatus, str] = {
    PaymentStatus.PENDING: "قيد الإرسال",
    PaymentStatus.VERIFICATION_PENDING: "تم الإرسال للمراجعة",
    PaymentStatus.VERIFIED: "تم التحقق",
    PaymentStatus.REJECTED: "مرفوض",
    PaymentStatus.REFUNDED: "تم الاسترداد",
    PaymentStatus.PARTIALLY_REFUNDED: "تم استرداد جزئي",
}

PAYMENT_METHOD_LABELS: dict[PaymentMethod, str] = {
    PaymentMethod.CASH: "نقدًا",
    PaymentMethod.VODAFONE_CASH: "فودافون كاش",
    PaymentMethod.INSTAPAY: "إنستا باي",
}

DEPOSIT_STATUS_LABELS: dict[DepositStatus, str] = {
    DepositStatus.NOT_REQUIRED: "غير مطلوب",
    DepositStatus.PENDING: "مطلوب",
    DepositStatus.SUBMITTED: "تم الإرسال للمراجعة",
    DepositStatus.VERIFIED: "تم التحقق",
    DepositStatus.REJECTED: "مرفوض",
    DepositStatus.REFUNDED: "تم الاسترداد",
    DepositStatus.PARTIALLY_REFUNDED: "تم استرداد جزئي",
}

REFUND_STATUS_LABELS: dict[RefundStatus, str] = {
    RefundStatus.PENDING: "معلق",
    RefundStatus.APPROVED: "معتمد",
    RefundStatus.PROCESSED: "تمت المعالجة",
    RefundStatus.REJECTED: "مرفوض",
}

QUOTE_STATUS_LABELS: dict[QuoteStatus, str] = {
    QuoteStatus.DRAFT: "مسودة",
    QuoteStatus.SENT: "مرسل",
    QuoteStatus.ACCEPTED: "مقبول",
    QuoteStatus.REJECTED: "مرفوض",
    QuoteStatus.EXPIRED: "منتهي",
    QuoteStatus.SUPERSEDED: "مستبدل",
}

COMPLAINT_STATUS_LABELS: dict[ComplaintStatus, str] = {
    ComplaintStatus.OPEN: "مفتوحة",
    ComplaintStatus.UNDER_REVIEW: "قيد المراجعة",
    ComplaintStatus.QC_REQUIRED: "تحتاج فحص جودة",
    ComplaintStatus.REVISIT_REQUIRED: "تحتاج زيارة إصلاح",
    ComplaintStatus.REVISIT_SCHEDULED: "تمت جدولة زيارة إصلاح",
    ComplaintStatus.RESOLVED: "تم الحل",
    ComplaintStatus.CLOSED: "مغلقة",
}

COMPLAINT_REASON_LABELS: dict[ComplaintReason, str] = {
    ComplaintReason.WORK_NOT_DONE: "العمل لم يُنجز بالكامل",
    ComplaintReason.POOR_QUALITY: "جودة الخدمة غير مرضية",
    ComplaintReason.OVERCHARGE: "السعر أعلى من المتفق عليه",
    ComplaintReason.TECHNICIAN_LATE: "تأخر الفني عن الموعد",
    ComplaintReason.DAMAGE: "ضرر بممتلكات",
    ComplaintReason.RECURRING_FAULT: "المشكلة متكررة",
    ComplaintReason.OTHER: "أخرى",
}

TECHNICIAN_STATUS_LABELS: dict[TechnicianStatus, str] = {
    TechnicianStatus.ACTIVE: "نشط",
    TechnicianStatus.ON_LEAVE: "في إجازة",
    TechnicianStatus.SUSPENDED: "موقوف",
    TechnicianStatus.INACTIVE: "غير نشط",
}

INSPECTION_STATUS_LABELS: dict[InspectionStatus, str] = {
    InspectionStatus.PENDING: "مطلوبة",
    InspectionStatus.SCHEDULED: "تم جدولتها",
    InspectionStatus.IN_PROGRESS: "جارية",
    InspectionStatus.COMPLETED: "مكتملة",
    InspectionStatus.CANCELLED: "ملغاة",
}

CANCELLATION_REASON_LABELS: dict[CancellationReason, str] = {
    CancellationReason.CUSTOMER_REQUEST: "طلب العميل",
    CancellationReason.NO_SHOW: "عدم حضور الفني",
    CancellationReason.TECHNICIAN_UNAVAILABLE: "عدم توفر الفني",
    CancellationReason.OUT_OF_COVERAGE: "خارج نطاق الخدمة",
    CancellationReason.POLICY_VIOLATION: "مخالفة لسياسة الخدمة",
    CancellationReason.OTHER: "أخرى",
}


def request_status_label(status: str) -> str:
    try:
        return REQUEST_STATUS_LABELS[RequestStatus(status)]
    except (KeyError, ValueError):
        return ""


def assignment_status_label(status: str) -> str:
    try:
        return ASSIGNMENT_STATUS_LABELS[AssignmentStatus(status)]
    except (KeyError, ValueError):
        return ""