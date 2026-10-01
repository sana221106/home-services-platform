// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'خدمات المنزل';

  @override
  String get appTagline => 'كل ما يحتاجه منزلك، في مكان واحد';

  @override
  String get commonRetry => 'إعادة المحاولة';

  @override
  String get commonCancel => 'إلغاء';

  @override
  String get commonConfirm => 'تأكيد';

  @override
  String get commonContinue => 'متابعة';

  @override
  String get commonBack => 'رجوع';

  @override
  String get commonNext => 'التالي';

  @override
  String get commonSkip => 'تخطي';

  @override
  String get commonSave => 'حفظ';

  @override
  String get commonSubmit => 'إرسال';

  @override
  String get commonSearch => 'بحث';

  @override
  String get commonClose => 'إغلاق';

  @override
  String get commonDelete => 'حذف';

  @override
  String get commonEdit => 'تعديل';

  @override
  String get commonSeeAll => 'عرض الكل';

  @override
  String get commonSeeDetails => 'عرض التفاصيل';

  @override
  String get commonLoading => 'جارٍ التحميل…';

  @override
  String get commonSomethingWentWrong => 'حدث خطأ غير متوقع. حاول مرة أخرى.';

  @override
  String get commonNoResults => 'لا توجد نتائج';

  @override
  String get commonRequiredField => 'هذا الحقل مطلوب';

  @override
  String get commonOptional => 'اختياري';

  @override
  String get comingSoon => 'هذه الشاشة قيد الإنشاء.';

  @override
  String get homeTabLabel => 'الرئيسية';

  @override
  String get requestsTabLabel => 'الطلبات';

  @override
  String get propertiesTabLabel => 'عقاراتي';

  @override
  String get supportTabLabel => 'الدعم';

  @override
  String get profileTabLabel => 'حسابي';

  @override
  String get onboardingWelcomeTitle => 'أهلاً بك';

  @override
  String get onboardingWelcomeBody =>
      'اطلب سباكاً، كهربائياً، تكييف أو تنظيف — وتابع التنفيذ لحظة بلحظة.';

  @override
  String get onboardingHowItWorksTitle => 'كيف تعمل الخدمة؟';

  @override
  String get onboardingStepChoose => 'اختر الخدمة';

  @override
  String get onboardingStepDescribe => 'اشرح المشكلة وصفّرها';

  @override
  String get onboardingStepQuote => 'استلم عرض السعر';

  @override
  String get onboardingStepTrack => 'تابع التنفيذ والتقييم';

  @override
  String get onboardingGetStarted => 'ابدأ الآن';

  @override
  String get authPhoneTitle => 'رقم الهاتف';

  @override
  String get authPhoneBody => 'أدخل رقم هاتفك للمتابعة';

  @override
  String get authPhoneLabel => 'رقم الهاتف';

  @override
  String get authPhoneHint => '01xxxxxxxxx';

  @override
  String get authPhoneInvalid => 'رقم الهاتف غير صحيح';

  @override
  String get authPhoneNewAccountHint =>
      'رقم جديد؟ سننشئ لك حساباً تلقائياً عند التحقق.';

  @override
  String get authPhoneRequired => 'رقم الهاتف غير معروف. أعد إدخاله.';

  @override
  String get authNameLabel => 'الاسم بالكامل';

  @override
  String get authNameHint => 'اكتب اسمك';

  @override
  String get authOtpTitle => 'رمز التحقق';

  @override
  String authOtpBody(Object count) {
    return 'أرسلنا رمزاً مكوّناً من $count أرقام إلى رقمك';
  }

  @override
  String authOtpResendIn(Object seconds) {
    return 'إعادة الإرسال خلال $seconds ثانية';
  }

  @override
  String get authOtpResendNow => 'إعادة إرسال الرمز';

  @override
  String get authOtpVerify => 'تحقق';

  @override
  String get authOtpChangeNumber => 'تغيير رقم الهاتف';

  @override
  String get authOtpField => 'رمز التحقق';

  @override
  String get authOtpSent => 'تم إرسال رمز التحقق';

  @override
  String homeGreeting(Object name) {
    return 'أهلاً، $name';
  }

  @override
  String get homeActiveRequestTitle => 'طلب نشط';

  @override
  String get homeQuickActions => 'خدمات سريعة';

  @override
  String get homeRecentRequests => 'طلباتك الأخيرة';

  @override
  String get homeSeeAllRequests => 'عرض كل الطلبات';

  @override
  String get homeNoActiveRequest => 'لا يوجد طلب نشط حالياً';

  @override
  String get homeStartRequest => 'ابدأ طلباً جديداً';

  @override
  String get homeUpcomingVisit => 'موعدك القادم';

  @override
  String get requestsTitle => 'الطلبات';

  @override
  String get requestsNew => 'طلب جديد';

  @override
  String get requestsActive => 'نشط';

  @override
  String get requestsHistory => 'السجل';

  @override
  String get requestsEmptyTitle => 'لا توجد طلبات بعد';

  @override
  String get requestsEmptyBody => 'ابدأ بطلب أول خدمة لك';

  @override
  String get requestsCategoryTitle => 'اختر الخدمة';

  @override
  String get requestsProblemTitle => 'ما المشكلة؟';

  @override
  String get requestsDescribeTitle => 'اشرح المشكلة';

  @override
  String get requestsDescribeHint => 'اكتب وصفاً واضحاً للمشكلة…';

  @override
  String get requestsPhotosTitle => 'أضف صوراً';

  @override
  String get requestsPhotosHint => 'صور واضحة تساعد الفني على تقدير العمل بدقة';

  @override
  String requestsPhotosMax(Object count) {
    return 'حتى $count صور';
  }

  @override
  String get requestsAddressTitle => 'العنوان';

  @override
  String get requestsPropertyTitle => 'اختر العقار';

  @override
  String get requestsScheduleTitle => 'موعد الزيارة';

  @override
  String get requestsScheduleUrgent => 'طارئ';

  @override
  String get requestsScheduleUrgentHint => 'سنحاول خدمتك في أقرب وقت متاح';

  @override
  String get requestsReviewTitle => 'راجع الطلب';

  @override
  String get requestsSubmit => 'إرسال الطلب';

  @override
  String get requestsSubmitSuccess => 'تم إرسال طلبك بنجاح';

  @override
  String get requestDetailTitle => 'تفاصيل الطلب';

  @override
  String get requestTimelineTitle => 'مراحل الطلب';

  @override
  String get requestQuoteTitle => 'عرض السعر';

  @override
  String get requestQuoteAccept => 'قبول عرض السعر';

  @override
  String get requestQuoteReject => 'رفض';

  @override
  String get requestQuoteExpired => 'انتهت صلاحية عرض السعر';

  @override
  String get requestQuoteNeedsInfo => 'مطلوب معلومات إضافية';

  @override
  String get requestDepositTitle => 'العربون';

  @override
  String get requestDepositAmount => 'قيمة العربون';

  @override
  String get requestCancelTitle => 'إلغاء الطلب';

  @override
  String get requestCancelWarning =>
      'قد يستغرق استرداع العربون وقتًا أطول حسب سياسة الإلغاء.';

  @override
  String get requestCancelConfirm => 'تأكيد الإلغاء';

  @override
  String get requestAddInfo => 'إرسال معلومات إضافية';

  @override
  String get ordersTitle => 'طلباتي';

  @override
  String get orderTrackTitle => 'تتبع الطلب';

  @override
  String get orderTechnicianOnWay => 'الفني في الطريق إليك';

  @override
  String get orderTechnicianArrived => 'الفني وصل';

  @override
  String get orderTimelineTitle => 'خطوات التنفيذ';

  @override
  String get orderEta => 'الوصول المتوقع';

  @override
  String get orderCancel => 'إلغاء';

  @override
  String get paymentsTitle => 'الدفع';

  @override
  String get paymentsMethods => 'طرق الدفع المتاحة';

  @override
  String get paymentsUploadProof => 'رفع إثبات الدفع';

  @override
  String get paymentsProofHint => 'صورة واضحة للإيصال أو التحويل';

  @override
  String get paymentsPendingVerification => 'بانتظار التحقق';

  @override
  String get paymentsVerified => 'تم التحقق';

  @override
  String get paymentsRejected => 'مرفوض';

  @override
  String get paymentsRefundPending => 'الاسترجاع قيد المعالجة';

  @override
  String get propertiesTitle => 'عقاراتي';

  @override
  String get propertiesAdd => 'إضافة عقار';

  @override
  String get propertiesEmptyTitle => 'لا توجد عقارات';

  @override
  String get propertiesEmptyBody => 'أضف عقاراتك لتسريع إنشاء الطلبات';

  @override
  String get propertiesLabel => 'اسم العقار';

  @override
  String get propertiesSetDefault => 'تعيين كافتراضي';

  @override
  String get propertiesHistory => 'سجل الصيانة';

  @override
  String get supportTitle => 'الدعم';

  @override
  String get supportChatTitle => 'الدردشة';

  @override
  String get supportMessageHint => 'اكتب رسالتك…';

  @override
  String get supportSend => 'إرسال';

  @override
  String get supportComplaintTitle => 'تقديم شكوى';

  @override
  String get supportComplaintReasons => 'نوع الشكوى';

  @override
  String get supportComplaintDetails => 'تفاصيل الشكوى';

  @override
  String get supportComplaintSubmit => 'إرسال الشكوى';

  @override
  String get reviewsTitle => 'تقييماتك';

  @override
  String get reviewsWrite => 'اكتب تقييماً';

  @override
  String get reviewsRatingLabel => 'تقييمك للخدمة';

  @override
  String get reviewsCommentHint => 'اكتب تعليقك (اختياري)';

  @override
  String get reviewsSubmit => 'إرسال التقييم';

  @override
  String get profileTitle => 'حسابي';

  @override
  String get profileEdit => 'تعديل الملف الشخصي';

  @override
  String get profileSettings => 'الإعدادات';

  @override
  String get profileLanguage => 'اللغة';

  @override
  String get profileTheme => 'المظهر';

  @override
  String get profileNotifications => 'الإشعارات';

  @override
  String get profileLogout => 'تسجيل الخروج';

  @override
  String get profileSupport => 'تواصل معنا';

  @override
  String get themeLight => 'فاتح';

  @override
  String get themeDark => 'داكن';

  @override
  String get themeSystem => 'النظام';

  @override
  String get errorNetwork =>
      'تعذر الاتصال بالخادم. تحقق من اتصالك وحاول مرة أخرى.';

  @override
  String get errorTimeout => 'استغرق الطلب وقتًا طويلًا. حاول مرة أخرى.';

  @override
  String get errorUnauthorized => 'انتهت الجلسة. يرجى تسجيل الدخول مرة أخرى.';

  @override
  String get errorForbidden => 'ليس لديك صلاحية للقيام بهذا الإجراء.';

  @override
  String get errorNotFound => 'العنصر المطلوب غير موجود.';

  @override
  String get errorConflict =>
      'تم تعديل البيانات بالفعل. حدّث الصفحة وحاول مجددًا.';

  @override
  String get errorRateLimited => 'طلبات كثيرة جدًا. حاول مرة أخرى بعد قليل.';

  @override
  String get errorServer => 'خدمة غير متاحة مؤقتًا. حاول مرة أخرى.';

  @override
  String get errorGeneric => 'حدث خطأ غير متوقع. حاول مرة أخرى.';
}
