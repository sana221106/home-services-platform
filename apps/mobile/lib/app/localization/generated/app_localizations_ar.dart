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

  @override
  String get propertiesSubtitle => 'إدارة منازل وعناوينك لطلبات الخدمة.';

  @override
  String get propertiesDefault => 'افتراضي';

  @override
  String get propertyHistoryTitle => 'سجل الصيانة';

  @override
  String get propertyHistorySubtitle => 'كل الزيارات السابقة لهذا العنوان';

  @override
  String get propertyHistoryEmptyTitle => 'لا يوجد سجل بعد';

  @override
  String get propertyHistoryEmptyBody =>
      'ستظهر الزيارات المكتملة هنا بعد أول طلب خدمة.';

  @override
  String get propertyRecurringChip => 'مشكلة متكررة';

  @override
  String propertyRecurringBanner(Object count) {
    return '$count زيارة مرتبطة بنفس المشكلة على هذا العنوان.';
  }

  @override
  String get complaintFiledChip => 'تم تقديم شكوى';

  @override
  String get requestReworkChip => 'زيارة إصلاح';

  @override
  String get requestInspectionOnly => 'زيارة معاينة فقط';

  @override
  String get requestUrgencyUrgent => 'عاجل';

  @override
  String get requestTitleFallback => 'طلب خدمة';

  @override
  String get requestDiagnosisLabel => 'التشخيص';

  @override
  String get requestResolutionLabel => 'الحل المنفذ';

  @override
  String get requestMaterialsLabel => 'الخامات المستخدمة';

  @override
  String get requestFinalPriceLabel => 'السعر النهائي';

  @override
  String get requestStatusUnknown => 'حالة غير معروفة';

  @override
  String get requestStatusDraft => 'مسودة';

  @override
  String get requestStatusSubmitted => 'تم الإرسال';

  @override
  String get requestStatusUnderReview => 'قيد المراجعة';

  @override
  String get requestStatusNeedMoreInfo => 'مطلوب معلومات إضافية';

  @override
  String get requestStatusInspectionRequired => 'مطلوب معاينة';

  @override
  String get requestStatusInspectionScheduled => 'معاينة مجدولة';

  @override
  String get requestStatusInspectionInProgress => 'المعاينة جارية';

  @override
  String get requestStatusInspectionCompleted => 'انتهت المعاينة';

  @override
  String get requestStatusQuotePreparation => 'تجهيز عرض السعر';

  @override
  String get requestStatusQuoteSent => 'تم إرسال عرض السعر';

  @override
  String get requestStatusAwaitingApproval => 'بانتظار موافقتك';

  @override
  String get requestStatusQuoteRejected => 'تم رفض عرض السعر';

  @override
  String get requestStatusDepositPending => 'بانتظار دفع التأمين';

  @override
  String get requestStatusDepositVerification => 'جاري التحقق من الدفع';

  @override
  String get requestStatusConfirmed => 'تم التأكيد';

  @override
  String get requestStatusAssignmentPending => 'بانتظار تعيين فني';

  @override
  String get requestStatusTechnicianAssigned => 'تم تعيين فني';

  @override
  String get requestStatusOnTheWay => 'الفني في الطريق';

  @override
  String get requestStatusArrived => 'وصل الفني';

  @override
  String get requestStatusWorkInProgress => 'جاري العمل';

  @override
  String get requestStatusServiceCompleted => 'اكتمل العمل';

  @override
  String get requestStatusPaymentPending => 'بانتظار الدفع';

  @override
  String get requestStatusPaymentVerification => 'جاري التحقق من الدفعة';

  @override
  String get requestStatusPaid => 'تم الدفع';

  @override
  String get requestStatusAwaitingRating => 'بانتظار تقييمك';

  @override
  String get requestStatusComplaintOpen => 'شكوى مفتوحة';

  @override
  String get requestStatusComplaintUnderReview => 'شكوى قيد المراجعة';

  @override
  String get requestStatusRevisitScheduled => 'زيارة إصلاح مجدولة';

  @override
  String get requestStatusResolved => 'تم الحل';

  @override
  String get requestStatusClosed => 'مغلق';

  @override
  String get requestStatusCancelled => 'ملغي';

  @override
  String get timeNow => 'الآن';

  @override
  String timeMinutes(int count) {
    return 'منذ $count دقيقة';
  }

  @override
  String timeHours(int count) {
    return 'منذ $count ساعة';
  }

  @override
  String timeDays(int count) {
    return 'منذ $count يوم';
  }

  @override
  String timeMonths(int count) {
    return 'منذ $count شهر';
  }

  @override
  String timeYears(int count) {
    return 'منذ $count سنة';
  }

  @override
  String get meridiemAm => 'ص';

  @override
  String get timeYesterday => 'أمس';

  @override
  String get meridiemPm => 'م';

  @override
  String get requestsFilterAll => 'الكل';

  @override
  String get requestsFilterActive => 'نشطة';

  @override
  String get requestsFilterAction => 'تحتاج إجراء';

  @override
  String get requestsFilterDone => 'مكتملة';

  @override
  String get requestsStepService => 'الخدمة';

  @override
  String get requestsStepDetails => 'التفاصيل';

  @override
  String get requestsStepPhotos => 'الصور';

  @override
  String get requestsStepLocation => 'الموقع';

  @override
  String get requestsStepReview => 'المراجعة';

  @override
  String requestsStepCounter(int total, int current) {
    return 'الخطوة $current من $total';
  }

  @override
  String get requestsServiceChoose => 'اختر الخدمة';

  @override
  String get requestsServiceEmpty => 'لا توجد خدمات متاحة';

  @override
  String get requestsServiceEmptyBody =>
      'تعذر تحميل قائمة الخدمات، حاول مرة أخرى';

  @override
  String get requestsProblemOptional => 'نوع المشكلة (اختياري)';

  @override
  String get requestsProblemSkip => 'تخطي';

  @override
  String get requestsDescTooShort => 'اكتب 10 أحرف على الأقل';

  @override
  String get requestsDescTooLong => 'الحد الأقصى 4000 حرف';

  @override
  String get requestsPhotosAdd => 'إضافة صورة';

  @override
  String get requestsPhotosRequired => 'يلزم صورة واحدة على الأقل للمتابعة';

  @override
  String requestsPhotosLimit(int max) {
    return 'وصلت للحد الأقصى $max صور';
  }

  @override
  String get requestsPhotosHintSize =>
      'JPG أو PNG أو WebP، بحد أقصى 12 ميجابايت للصورة';

  @override
  String get requestsPhotosUploading => 'جارٍ رفع الصور...';

  @override
  String requestsPhotosCount(int count, int max) {
    return '$count من $max صور';
  }

  @override
  String get requestsLocationPick => 'اختر العقار';

  @override
  String get requestsLocationNoProperty => 'أضف عقاراً أولاً من صفحة العقارات';

  @override
  String get requestsAddressGovernorate => 'المحافظة';

  @override
  String get requestsAddressCity => 'المدينة';

  @override
  String get requestsAddressZone => 'المنطقة';

  @override
  String get requestsAddressDistrict => 'الحي';

  @override
  String get requestsAddressStreet => 'الشارع';

  @override
  String get requestsAddressBuilding => 'المبنى';

  @override
  String get requestsAddressFloor => 'الدور';

  @override
  String get requestsAddressApartment => 'الشقة';

  @override
  String get requestsAddressLandmark => 'علامة مميزة';

  @override
  String get requestsAddressNotes => 'ملاحظات للوصول';

  @override
  String get requestsAddressContactName => 'اسم جهة الاتصال';

  @override
  String get requestsAddressContactPhone => 'رقم جهة الاتصال';

  @override
  String get requestsAddressCoordsMissing => 'حدد الموقع على الخريطة';

  @override
  String get requestsReviewTitle => 'راجع طلبك';

  @override
  String get requestsReviewEdit => 'تعديل';

  @override
  String get requestsReviewMissing => 'ينقصك التالي:';

  @override
  String get requestsReviewMissingService => 'اختر الخدمة';

  @override
  String get requestsReviewMissingLocation => 'أكمل العنوان';

  @override
  String get requestsReviewMissingDetails => 'اكتب وصف المشكلة';

  @override
  String get requestsReviewMissingPhotos => 'أضف صورة واحدة على الأقل';

  @override
  String get requestsSubmitting => 'جارٍ إرسال الطلب...';

  @override
  String get requestsSubmitRetry => 'حاول مرة أخرى';

  @override
  String get requestsCreatedDraft => 'تم إنشاء مسودة، سنكمل الرفع';

  @override
  String get requestsNoProperty => 'لا يوجد عقار مسجل';

  @override
  String get requestsUrgencyNormal => 'عادي';

  @override
  String get requestsUrgencyUrgentLabel => 'عاجل';

  @override
  String get requestsInspectionOnlyHint => 'فحص فقط بدون تنفيذ';

  @override
  String get requestsNoteLabel => 'ملاحظات إضافية';

  @override
  String get requestsReferenceCode => 'رقم الطلب';

  @override
  String requestsCountLabel(int count) {
    return '$count طلب';
  }

  @override
  String get requestsAddressContactPairError =>
      'أدخل رقم جهة الاتصال عند تحديد اسم جهة الاتصال';

  @override
  String get requestsNewActivity => 'تحديث جديد';

  @override
  String requestsListCount(int count) {
    return '$count طلب';
  }

  @override
  String commonCurrency(Object amount) {
    return '$amount ج.م';
  }

  @override
  String get requestDetailProblemTitle => 'وصف المشكلة';

  @override
  String requestDetailPhotos(Object count) {
    return 'الصور ($count)';
  }

  @override
  String get requestDetailAddressTitle => 'عنوان الزيارة';

  @override
  String get requestDetailTechnicianTitle => 'الفني';

  @override
  String get requestDetailNoTimeline => 'لا توجد تحديثات بعد';

  @override
  String get requestDetailAddedByYou => 'أضافته أنت';

  @override
  String get requestDetailAddedByTeam => 'أضافه فريق الخدمة';

  @override
  String get quoteServiceCost => 'الخدمة';

  @override
  String get quoteMaterialsCost => 'المواد';

  @override
  String get quoteUrgencyFee => 'رسوم العاجل';

  @override
  String get quoteInspectionFee => 'رسوم المعاينة';

  @override
  String get quoteDiscount => 'الخصم';

  @override
  String get quoteSubtotal => 'المجموع الفرعي';

  @override
  String get quoteTotal => 'الإجمالي';

  @override
  String get quoteDuration => 'المدة التقديرية';

  @override
  String quoteDurationValue(Object count) {
    return '$count دقيقة';
  }

  @override
  String quoteRevision(Object count) {
    return 'العرض رقم $count';
  }

  @override
  String quoteValidUntil(Object date) {
    return 'صالح حتى $date';
  }

  @override
  String get quoteNotes => 'ملاحظات';

  @override
  String get quoteItemsTitle => 'ما يشمله العرض';

  @override
  String get quoteActionableEnded => 'لم يعد هذا العرض قابلًا للقبول';

  @override
  String get cancelRefundPreview => 'معاينة الاسترداد';

  @override
  String get cancelRefundAmount => 'سيتم رد لك';

  @override
  String get cancelDeductionAmount => 'يُخصم من العربون';

  @override
  String get cancelNeedsApproval => 'هذا الطلب يحتاج موافقة الفريق قبل الإلغاء';

  @override
  String get cancelReasonLabel => 'سبب الإلغاء (اختياري)';

  @override
  String get cancelReasonHint => 'أخبرنا بما حدث حتى نتحسن';

  @override
  String get requestCancelAction => 'إلغاء الطلب';

  @override
  String get requestRateAction => 'تقييم الخدمة';

  @override
  String get requestComplainAction => 'الإبلاغ عن مشكلة';

  @override
  String get ordersEmptyTitle => 'لا توجد طلبات بعد';

  @override
  String get ordersEmptyBody => 'عند حجز أي خدمة ستظهر هنا';

  @override
  String get orderComplaintOpenChip => 'شكوى';

  @override
  String get orderNoTotalYet => 'بانتظار التسعير';

  @override
  String get orderArrivalNotScheduled => 'لم يتم تحديد موعد الوصول بعد';

  @override
  String get orderArrivalNotScheduledBody =>
      'سنعرض موعد الوصول فور تعيين الفني';

  @override
  String get orderWorkStarted => 'بدء العمل';

  @override
  String get orderWorkCompleted => 'انتهاء العمل';

  @override
  String get orderServiceCompleted => 'تم إنجاز الخدمة';

  @override
  String get orderViewFullRequest => 'عرض تفاصيل الطلب';

  @override
  String get ordersEmptyCta => 'احجز خدمة';

  @override
  String get supportDefaultSubject => 'طلب دعم';

  @override
  String get supportThreadClosed => 'مغلق';

  @override
  String supportUnreadCount(Object count) {
    return 'غير مقروء ($count)';
  }

  @override
  String get supportThreadsTitle => 'محادثاتك';

  @override
  String get supportThreadsEmptyTitle => 'لا توجد محادثات بعد';

  @override
  String get supportThreadsEmptyBody => 'راسل الفريق وستظهر الردود هنا';

  @override
  String get supportNewConversation => 'رسالة جديدة';

  @override
  String get supportComplaintsTitle => 'شكاواي';

  @override
  String get supportComplaintsEmptyTitle => 'لا توجد شكاوى';

  @override
  String get supportComplaintsEmptyBody => 'أبلغ عن مشكلة في خدمة منجزة من هنا';

  @override
  String get complaintStatusOpen => 'مفتوحة';

  @override
  String get complaintStatusUnderReview => 'قيد المراجعة';

  @override
  String get complaintStatusQcRequired => 'فحص جودة';

  @override
  String get complaintStatusRevisitRequired => 'زيارة أخرى مطلوبة';

  @override
  String get complaintStatusRevisitScheduled => 'تمت جدولة زيارة أخرى';

  @override
  String get complaintStatusResolved => 'تم الحل';

  @override
  String get complaintStatusClosed => 'مغلقة';

  @override
  String get complaintReworkScheduled => 'تمت جدولة زيارة إصلاح';

  @override
  String get complaintSubjectHint => 'ما موضوع الرسالة؟';

  @override
  String get complaintMessageHint => 'اشرح المشكلة بالتفصيل';

  @override
  String get complaintSubmitHint => '10 أحرف على الأقل';

  @override
  String get complaintFiledSuccess => 'تم إرسال الشكوى';

  @override
  String get complaintPickReason => 'اختر نوع الشكوى';

  @override
  String get supportMessagesEmpty => 'لا توجد رسائل بعد';

  @override
  String get complaintReasonWorkNotDone => 'لم يتم إنجاز العمل';

  @override
  String get complaintReasonPoorQuality => 'جودة عمل غير مقبولة';

  @override
  String get complaintReasonOvercharge => 'سعر أعلى من المتفق';

  @override
  String get complaintReasonTechnicianLate => 'تأخر الفني عن موعده';

  @override
  String get complaintReasonDamage => 'تسبب في ضرر';

  @override
  String get complaintReasonRecurringFault => 'المشكلة تكررت';

  @override
  String get complaintReasonOther => 'سبب آخر';

  @override
  String get paymentViewTitle => 'الدفع';

  @override
  String get paymentAmountDue => 'المبلغ المستحق';

  @override
  String get paymentFullyPaid => 'لا يوجد مستحق';

  @override
  String get paymentQuoteTotal => 'الإجمالي المتفق عليه';

  @override
  String get paymentSubmitEvidence => 'إرسال إثبات الدفع';

  @override
  String get paymentChooseMethod => 'كيف دفعت؟';

  @override
  String get paymentAmount => 'المبلغ';

  @override
  String get paymentReferenceNumber => 'رقم عملية التحويل';

  @override
  String get paymentReferenceHint => 'أدخل الرقم من إيصال التحويل';

  @override
  String get paymentReferenceRequired => 'تحويلات المحافظ تحتاج رقم عملية';

  @override
  String get paymentEvidenceSubmitted => 'تم إرسال إثبات الدفع للمراجعة';

  @override
  String get paymentHistory => 'سجل الدفعات';

  @override
  String get paymentRefunds => 'المبالغ المستردة';

  @override
  String get paymentRefundReason => 'السبب';

  @override
  String get paymentNoHistory => 'لم ترسل أي دفعات بعد';

  @override
  String get paymentDepositPaid => 'تم دفع العربون';

  @override
  String get paymentDepositOutstanding => 'متبقٍ من العربون';

  @override
  String get paymentDepositNotRequired => 'لا يوجد عربون مطلوب';

  @override
  String get paymentAttachReceipt => 'إرفاق الإيصال';

  @override
  String get paymentReceiptAttached => 'تم إرفاق الإيصال';

  @override
  String get paymentReceiptFailed => 'تعذر إرفاق الإيصال';

  @override
  String get paymentVerifiedOn => 'تم التحقق في';

  @override
  String get paymentRejectedReason => 'سبب الرفض';

  @override
  String get paymentIsDeposit => 'هذا المبلغ هو دفع العربون';

  @override
  String get paymentStatusPending => 'معلق';

  @override
  String get paymentStatusVerificationPending => 'بانتظار التحقق';

  @override
  String get paymentStatusVerified => 'تم التحقق';

  @override
  String get paymentStatusRejected => 'مرفوض';

  @override
  String get paymentStatusRefunded => 'تم الاسترداد';

  @override
  String get paymentStatusPartiallyRefunded => 'تم استرداد جزئي';

  @override
  String get paymentMethodCash => 'نقدًا عند الإنجاز';

  @override
  String get paymentMethodVodafoneCash => 'فودافون كاش';

  @override
  String get paymentMethodInstaPay => 'إنستا باي';

  @override
  String get paymentSupportPhone => 'دعم العملاء المالي';

  @override
  String get paymentInstructionsTitle => 'طريقة الدفع';

  @override
  String get paymentRefundProcessed => 'تمت المعالجة';

  @override
  String get paymentRefundApproved => 'معتمد';

  @override
  String get paymentRefundRejected => 'مرفوض';

  @override
  String get paymentAmountPaid => 'المدفوع';

  @override
  String get paymentRefundedAmount => 'المسترد';

  @override
  String get paymentDueDate => 'الاستحقاق';

  @override
  String get paymentRefundPending => 'جارٍ الاسترداد';
}
