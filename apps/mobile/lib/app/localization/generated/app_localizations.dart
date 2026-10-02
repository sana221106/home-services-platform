import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In ar, this message translates to:
  /// **'خدمات المنزل'**
  String get appTitle;

  /// No description provided for @appTagline.
  ///
  /// In ar, this message translates to:
  /// **'كل ما يحتاجه منزلك، في مكان واحد'**
  String get appTagline;

  /// No description provided for @commonRetry.
  ///
  /// In ar, this message translates to:
  /// **'إعادة المحاولة'**
  String get commonRetry;

  /// No description provided for @commonCancel.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء'**
  String get commonCancel;

  /// No description provided for @commonConfirm.
  ///
  /// In ar, this message translates to:
  /// **'تأكيد'**
  String get commonConfirm;

  /// No description provided for @commonContinue.
  ///
  /// In ar, this message translates to:
  /// **'متابعة'**
  String get commonContinue;

  /// No description provided for @commonBack.
  ///
  /// In ar, this message translates to:
  /// **'رجوع'**
  String get commonBack;

  /// No description provided for @commonNext.
  ///
  /// In ar, this message translates to:
  /// **'التالي'**
  String get commonNext;

  /// No description provided for @commonSkip.
  ///
  /// In ar, this message translates to:
  /// **'تخطي'**
  String get commonSkip;

  /// No description provided for @commonSave.
  ///
  /// In ar, this message translates to:
  /// **'حفظ'**
  String get commonSave;

  /// No description provided for @commonSubmit.
  ///
  /// In ar, this message translates to:
  /// **'إرسال'**
  String get commonSubmit;

  /// No description provided for @commonSearch.
  ///
  /// In ar, this message translates to:
  /// **'بحث'**
  String get commonSearch;

  /// No description provided for @commonClose.
  ///
  /// In ar, this message translates to:
  /// **'إغلاق'**
  String get commonClose;

  /// No description provided for @commonDelete.
  ///
  /// In ar, this message translates to:
  /// **'حذف'**
  String get commonDelete;

  /// No description provided for @commonEdit.
  ///
  /// In ar, this message translates to:
  /// **'تعديل'**
  String get commonEdit;

  /// No description provided for @commonSeeAll.
  ///
  /// In ar, this message translates to:
  /// **'عرض الكل'**
  String get commonSeeAll;

  /// No description provided for @commonSeeDetails.
  ///
  /// In ar, this message translates to:
  /// **'عرض التفاصيل'**
  String get commonSeeDetails;

  /// No description provided for @commonLoading.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ التحميل…'**
  String get commonLoading;

  /// No description provided for @commonSomethingWentWrong.
  ///
  /// In ar, this message translates to:
  /// **'حدث خطأ غير متوقع. حاول مرة أخرى.'**
  String get commonSomethingWentWrong;

  /// No description provided for @commonNoResults.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد نتائج'**
  String get commonNoResults;

  /// No description provided for @commonRequiredField.
  ///
  /// In ar, this message translates to:
  /// **'هذا الحقل مطلوب'**
  String get commonRequiredField;

  /// No description provided for @commonOptional.
  ///
  /// In ar, this message translates to:
  /// **'اختياري'**
  String get commonOptional;

  /// No description provided for @comingSoon.
  ///
  /// In ar, this message translates to:
  /// **'هذه الشاشة قيد الإنشاء.'**
  String get comingSoon;

  /// No description provided for @homeTabLabel.
  ///
  /// In ar, this message translates to:
  /// **'الرئيسية'**
  String get homeTabLabel;

  /// No description provided for @requestsTabLabel.
  ///
  /// In ar, this message translates to:
  /// **'الطلبات'**
  String get requestsTabLabel;

  /// No description provided for @propertiesTabLabel.
  ///
  /// In ar, this message translates to:
  /// **'عقاراتي'**
  String get propertiesTabLabel;

  /// No description provided for @supportTabLabel.
  ///
  /// In ar, this message translates to:
  /// **'الدعم'**
  String get supportTabLabel;

  /// No description provided for @profileTabLabel.
  ///
  /// In ar, this message translates to:
  /// **'حسابي'**
  String get profileTabLabel;

  /// No description provided for @onboardingWelcomeTitle.
  ///
  /// In ar, this message translates to:
  /// **'أهلاً بك'**
  String get onboardingWelcomeTitle;

  /// No description provided for @onboardingWelcomeBody.
  ///
  /// In ar, this message translates to:
  /// **'اطلب سباكاً، كهربائياً، تكييف أو تنظيف — وتابع التنفيذ لحظة بلحظة.'**
  String get onboardingWelcomeBody;

  /// No description provided for @onboardingHowItWorksTitle.
  ///
  /// In ar, this message translates to:
  /// **'كيف تعمل الخدمة؟'**
  String get onboardingHowItWorksTitle;

  /// No description provided for @onboardingStepChoose.
  ///
  /// In ar, this message translates to:
  /// **'اختر الخدمة'**
  String get onboardingStepChoose;

  /// No description provided for @onboardingStepDescribe.
  ///
  /// In ar, this message translates to:
  /// **'اشرح المشكلة وصفّرها'**
  String get onboardingStepDescribe;

  /// No description provided for @onboardingStepQuote.
  ///
  /// In ar, this message translates to:
  /// **'استلم عرض السعر'**
  String get onboardingStepQuote;

  /// No description provided for @onboardingStepTrack.
  ///
  /// In ar, this message translates to:
  /// **'تابع التنفيذ والتقييم'**
  String get onboardingStepTrack;

  /// No description provided for @onboardingGetStarted.
  ///
  /// In ar, this message translates to:
  /// **'ابدأ الآن'**
  String get onboardingGetStarted;

  /// No description provided for @authPhoneTitle.
  ///
  /// In ar, this message translates to:
  /// **'رقم الهاتف'**
  String get authPhoneTitle;

  /// No description provided for @authPhoneBody.
  ///
  /// In ar, this message translates to:
  /// **'أدخل رقم هاتفك للمتابعة'**
  String get authPhoneBody;

  /// No description provided for @authPhoneLabel.
  ///
  /// In ar, this message translates to:
  /// **'رقم الهاتف'**
  String get authPhoneLabel;

  /// No description provided for @authPhoneHint.
  ///
  /// In ar, this message translates to:
  /// **'01xxxxxxxxx'**
  String get authPhoneHint;

  /// No description provided for @authPhoneInvalid.
  ///
  /// In ar, this message translates to:
  /// **'رقم الهاتف غير صحيح'**
  String get authPhoneInvalid;

  /// No description provided for @authPhoneNewAccountHint.
  ///
  /// In ar, this message translates to:
  /// **'رقم جديد؟ سننشئ لك حساباً تلقائياً عند التحقق.'**
  String get authPhoneNewAccountHint;

  /// No description provided for @authPhoneRequired.
  ///
  /// In ar, this message translates to:
  /// **'رقم الهاتف غير معروف. أعد إدخاله.'**
  String get authPhoneRequired;

  /// No description provided for @authNameLabel.
  ///
  /// In ar, this message translates to:
  /// **'الاسم بالكامل'**
  String get authNameLabel;

  /// No description provided for @authNameHint.
  ///
  /// In ar, this message translates to:
  /// **'اكتب اسمك'**
  String get authNameHint;

  /// No description provided for @authOtpTitle.
  ///
  /// In ar, this message translates to:
  /// **'رمز التحقق'**
  String get authOtpTitle;

  /// No description provided for @authOtpBody.
  ///
  /// In ar, this message translates to:
  /// **'أرسلنا رمزاً مكوّناً من {count} أرقام إلى رقمك'**
  String authOtpBody(Object count);

  /// No description provided for @authOtpResendIn.
  ///
  /// In ar, this message translates to:
  /// **'إعادة الإرسال خلال {seconds} ثانية'**
  String authOtpResendIn(Object seconds);

  /// No description provided for @authOtpResendNow.
  ///
  /// In ar, this message translates to:
  /// **'إعادة إرسال الرمز'**
  String get authOtpResendNow;

  /// No description provided for @authOtpVerify.
  ///
  /// In ar, this message translates to:
  /// **'تحقق'**
  String get authOtpVerify;

  /// No description provided for @authOtpChangeNumber.
  ///
  /// In ar, this message translates to:
  /// **'تغيير رقم الهاتف'**
  String get authOtpChangeNumber;

  /// No description provided for @authOtpField.
  ///
  /// In ar, this message translates to:
  /// **'رمز التحقق'**
  String get authOtpField;

  /// No description provided for @authOtpSent.
  ///
  /// In ar, this message translates to:
  /// **'تم إرسال رمز التحقق'**
  String get authOtpSent;

  /// No description provided for @homeGreeting.
  ///
  /// In ar, this message translates to:
  /// **'أهلاً، {name}'**
  String homeGreeting(Object name);

  /// No description provided for @homeActiveRequestTitle.
  ///
  /// In ar, this message translates to:
  /// **'طلب نشط'**
  String get homeActiveRequestTitle;

  /// No description provided for @homeQuickActions.
  ///
  /// In ar, this message translates to:
  /// **'خدمات سريعة'**
  String get homeQuickActions;

  /// No description provided for @homeRecentRequests.
  ///
  /// In ar, this message translates to:
  /// **'طلباتك الأخيرة'**
  String get homeRecentRequests;

  /// No description provided for @homeSeeAllRequests.
  ///
  /// In ar, this message translates to:
  /// **'عرض كل الطلبات'**
  String get homeSeeAllRequests;

  /// No description provided for @homeNoActiveRequest.
  ///
  /// In ar, this message translates to:
  /// **'لا يوجد طلب نشط حالياً'**
  String get homeNoActiveRequest;

  /// No description provided for @homeStartRequest.
  ///
  /// In ar, this message translates to:
  /// **'ابدأ طلباً جديداً'**
  String get homeStartRequest;

  /// No description provided for @homeUpcomingVisit.
  ///
  /// In ar, this message translates to:
  /// **'موعدك القادم'**
  String get homeUpcomingVisit;

  /// No description provided for @requestsTitle.
  ///
  /// In ar, this message translates to:
  /// **'الطلبات'**
  String get requestsTitle;

  /// No description provided for @requestsNew.
  ///
  /// In ar, this message translates to:
  /// **'طلب جديد'**
  String get requestsNew;

  /// No description provided for @requestsActive.
  ///
  /// In ar, this message translates to:
  /// **'نشط'**
  String get requestsActive;

  /// No description provided for @requestsHistory.
  ///
  /// In ar, this message translates to:
  /// **'السجل'**
  String get requestsHistory;

  /// No description provided for @requestsEmptyTitle.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد طلبات بعد'**
  String get requestsEmptyTitle;

  /// No description provided for @requestsEmptyBody.
  ///
  /// In ar, this message translates to:
  /// **'ابدأ بطلب أول خدمة لك'**
  String get requestsEmptyBody;

  /// No description provided for @requestsCategoryTitle.
  ///
  /// In ar, this message translates to:
  /// **'اختر الخدمة'**
  String get requestsCategoryTitle;

  /// No description provided for @requestsProblemTitle.
  ///
  /// In ar, this message translates to:
  /// **'ما المشكلة؟'**
  String get requestsProblemTitle;

  /// No description provided for @requestsDescribeTitle.
  ///
  /// In ar, this message translates to:
  /// **'اشرح المشكلة'**
  String get requestsDescribeTitle;

  /// No description provided for @requestsDescribeHint.
  ///
  /// In ar, this message translates to:
  /// **'اكتب وصفاً واضحاً للمشكلة…'**
  String get requestsDescribeHint;

  /// No description provided for @requestsPhotosTitle.
  ///
  /// In ar, this message translates to:
  /// **'أضف صوراً'**
  String get requestsPhotosTitle;

  /// No description provided for @requestsPhotosHint.
  ///
  /// In ar, this message translates to:
  /// **'صور واضحة تساعد الفني على تقدير العمل بدقة'**
  String get requestsPhotosHint;

  /// No description provided for @requestsPhotosMax.
  ///
  /// In ar, this message translates to:
  /// **'حتى {count} صور'**
  String requestsPhotosMax(Object count);

  /// No description provided for @requestsAddressTitle.
  ///
  /// In ar, this message translates to:
  /// **'العنوان'**
  String get requestsAddressTitle;

  /// No description provided for @requestsPropertyTitle.
  ///
  /// In ar, this message translates to:
  /// **'اختر العقار'**
  String get requestsPropertyTitle;

  /// No description provided for @requestsScheduleTitle.
  ///
  /// In ar, this message translates to:
  /// **'موعد الزيارة'**
  String get requestsScheduleTitle;

  /// No description provided for @requestsScheduleUrgent.
  ///
  /// In ar, this message translates to:
  /// **'طارئ'**
  String get requestsScheduleUrgent;

  /// No description provided for @requestsScheduleUrgentHint.
  ///
  /// In ar, this message translates to:
  /// **'سنحاول خدمتك في أقرب وقت متاح'**
  String get requestsScheduleUrgentHint;

  /// No description provided for @requestsSubmit.
  ///
  /// In ar, this message translates to:
  /// **'إرسال الطلب'**
  String get requestsSubmit;

  /// No description provided for @requestsSubmitSuccess.
  ///
  /// In ar, this message translates to:
  /// **'تم إرسال طلبك بنجاح'**
  String get requestsSubmitSuccess;

  /// No description provided for @requestDetailTitle.
  ///
  /// In ar, this message translates to:
  /// **'تفاصيل الطلب'**
  String get requestDetailTitle;

  /// No description provided for @requestTimelineTitle.
  ///
  /// In ar, this message translates to:
  /// **'مراحل الطلب'**
  String get requestTimelineTitle;

  /// No description provided for @requestQuoteTitle.
  ///
  /// In ar, this message translates to:
  /// **'عرض السعر'**
  String get requestQuoteTitle;

  /// No description provided for @requestQuoteAccept.
  ///
  /// In ar, this message translates to:
  /// **'قبول عرض السعر'**
  String get requestQuoteAccept;

  /// No description provided for @requestQuoteReject.
  ///
  /// In ar, this message translates to:
  /// **'رفض'**
  String get requestQuoteReject;

  /// No description provided for @requestQuoteExpired.
  ///
  /// In ar, this message translates to:
  /// **'انتهت صلاحية عرض السعر'**
  String get requestQuoteExpired;

  /// No description provided for @requestQuoteNeedsInfo.
  ///
  /// In ar, this message translates to:
  /// **'مطلوب معلومات إضافية'**
  String get requestQuoteNeedsInfo;

  /// No description provided for @requestDepositTitle.
  ///
  /// In ar, this message translates to:
  /// **'العربون'**
  String get requestDepositTitle;

  /// No description provided for @requestDepositAmount.
  ///
  /// In ar, this message translates to:
  /// **'قيمة العربون'**
  String get requestDepositAmount;

  /// No description provided for @requestCancelTitle.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء الطلب'**
  String get requestCancelTitle;

  /// No description provided for @requestCancelWarning.
  ///
  /// In ar, this message translates to:
  /// **'قد يستغرق استرداع العربون وقتًا أطول حسب سياسة الإلغاء.'**
  String get requestCancelWarning;

  /// No description provided for @requestCancelConfirm.
  ///
  /// In ar, this message translates to:
  /// **'تأكيد الإلغاء'**
  String get requestCancelConfirm;

  /// No description provided for @requestAddInfo.
  ///
  /// In ar, this message translates to:
  /// **'إرسال معلومات إضافية'**
  String get requestAddInfo;

  /// No description provided for @ordersTitle.
  ///
  /// In ar, this message translates to:
  /// **'طلباتي'**
  String get ordersTitle;

  /// No description provided for @orderTrackTitle.
  ///
  /// In ar, this message translates to:
  /// **'تتبع الطلب'**
  String get orderTrackTitle;

  /// No description provided for @orderTechnicianOnWay.
  ///
  /// In ar, this message translates to:
  /// **'الفني في الطريق إليك'**
  String get orderTechnicianOnWay;

  /// No description provided for @orderTechnicianArrived.
  ///
  /// In ar, this message translates to:
  /// **'الفني وصل'**
  String get orderTechnicianArrived;

  /// No description provided for @orderTimelineTitle.
  ///
  /// In ar, this message translates to:
  /// **'خطوات التنفيذ'**
  String get orderTimelineTitle;

  /// No description provided for @orderEta.
  ///
  /// In ar, this message translates to:
  /// **'الوصول المتوقع'**
  String get orderEta;

  /// No description provided for @orderCancel.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء'**
  String get orderCancel;

  /// No description provided for @paymentsTitle.
  ///
  /// In ar, this message translates to:
  /// **'الدفع'**
  String get paymentsTitle;

  /// No description provided for @paymentsMethods.
  ///
  /// In ar, this message translates to:
  /// **'طرق الدفع المتاحة'**
  String get paymentsMethods;

  /// No description provided for @paymentsUploadProof.
  ///
  /// In ar, this message translates to:
  /// **'رفع إثبات الدفع'**
  String get paymentsUploadProof;

  /// No description provided for @paymentsProofHint.
  ///
  /// In ar, this message translates to:
  /// **'صورة واضحة للإيصال أو التحويل'**
  String get paymentsProofHint;

  /// No description provided for @paymentsPendingVerification.
  ///
  /// In ar, this message translates to:
  /// **'بانتظار التحقق'**
  String get paymentsPendingVerification;

  /// No description provided for @paymentsVerified.
  ///
  /// In ar, this message translates to:
  /// **'تم التحقق'**
  String get paymentsVerified;

  /// No description provided for @paymentsRejected.
  ///
  /// In ar, this message translates to:
  /// **'مرفوض'**
  String get paymentsRejected;

  /// No description provided for @paymentsRefundPending.
  ///
  /// In ar, this message translates to:
  /// **'الاسترجاع قيد المعالجة'**
  String get paymentsRefundPending;

  /// No description provided for @propertiesTitle.
  ///
  /// In ar, this message translates to:
  /// **'عقاراتي'**
  String get propertiesTitle;

  /// No description provided for @propertiesAdd.
  ///
  /// In ar, this message translates to:
  /// **'إضافة عقار'**
  String get propertiesAdd;

  /// No description provided for @propertiesEmptyTitle.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد عقارات'**
  String get propertiesEmptyTitle;

  /// No description provided for @propertiesEmptyBody.
  ///
  /// In ar, this message translates to:
  /// **'أضف عقاراتك لتسريع إنشاء الطلبات'**
  String get propertiesEmptyBody;

  /// No description provided for @propertiesLabel.
  ///
  /// In ar, this message translates to:
  /// **'اسم العقار'**
  String get propertiesLabel;

  /// No description provided for @propertiesSetDefault.
  ///
  /// In ar, this message translates to:
  /// **'تعيين كافتراضي'**
  String get propertiesSetDefault;

  /// No description provided for @propertiesHistory.
  ///
  /// In ar, this message translates to:
  /// **'سجل الصيانة'**
  String get propertiesHistory;

  /// No description provided for @supportTitle.
  ///
  /// In ar, this message translates to:
  /// **'الدعم'**
  String get supportTitle;

  /// No description provided for @supportChatTitle.
  ///
  /// In ar, this message translates to:
  /// **'الدردشة'**
  String get supportChatTitle;

  /// No description provided for @supportMessageHint.
  ///
  /// In ar, this message translates to:
  /// **'اكتب رسالتك…'**
  String get supportMessageHint;

  /// No description provided for @supportSend.
  ///
  /// In ar, this message translates to:
  /// **'إرسال'**
  String get supportSend;

  /// No description provided for @supportComplaintTitle.
  ///
  /// In ar, this message translates to:
  /// **'تقديم شكوى'**
  String get supportComplaintTitle;

  /// No description provided for @supportComplaintReasons.
  ///
  /// In ar, this message translates to:
  /// **'نوع الشكوى'**
  String get supportComplaintReasons;

  /// No description provided for @supportComplaintDetails.
  ///
  /// In ar, this message translates to:
  /// **'تفاصيل الشكوى'**
  String get supportComplaintDetails;

  /// No description provided for @supportComplaintSubmit.
  ///
  /// In ar, this message translates to:
  /// **'إرسال الشكوى'**
  String get supportComplaintSubmit;

  /// No description provided for @reviewsTitle.
  ///
  /// In ar, this message translates to:
  /// **'تقييماتك'**
  String get reviewsTitle;

  /// No description provided for @reviewsWrite.
  ///
  /// In ar, this message translates to:
  /// **'اكتب تقييماً'**
  String get reviewsWrite;

  /// No description provided for @reviewsRatingLabel.
  ///
  /// In ar, this message translates to:
  /// **'تقييمك للخدمة'**
  String get reviewsRatingLabel;

  /// No description provided for @reviewsCommentHint.
  ///
  /// In ar, this message translates to:
  /// **'اكتب تعليقك (اختياري)'**
  String get reviewsCommentHint;

  /// No description provided for @reviewsSubmit.
  ///
  /// In ar, this message translates to:
  /// **'إرسال التقييم'**
  String get reviewsSubmit;

  /// No description provided for @profileTitle.
  ///
  /// In ar, this message translates to:
  /// **'حسابي'**
  String get profileTitle;

  /// No description provided for @profileEdit.
  ///
  /// In ar, this message translates to:
  /// **'تعديل الملف الشخصي'**
  String get profileEdit;

  /// No description provided for @profileSettings.
  ///
  /// In ar, this message translates to:
  /// **'الإعدادات'**
  String get profileSettings;

  /// No description provided for @profileLanguage.
  ///
  /// In ar, this message translates to:
  /// **'اللغة'**
  String get profileLanguage;

  /// No description provided for @profileTheme.
  ///
  /// In ar, this message translates to:
  /// **'المظهر'**
  String get profileTheme;

  /// No description provided for @profileNotifications.
  ///
  /// In ar, this message translates to:
  /// **'الإشعارات'**
  String get profileNotifications;

  /// No description provided for @profileLogout.
  ///
  /// In ar, this message translates to:
  /// **'تسجيل الخروج'**
  String get profileLogout;

  /// No description provided for @profileSupport.
  ///
  /// In ar, this message translates to:
  /// **'تواصل معنا'**
  String get profileSupport;

  /// No description provided for @themeLight.
  ///
  /// In ar, this message translates to:
  /// **'فاتح'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In ar, this message translates to:
  /// **'داكن'**
  String get themeDark;

  /// No description provided for @themeSystem.
  ///
  /// In ar, this message translates to:
  /// **'النظام'**
  String get themeSystem;

  /// No description provided for @errorNetwork.
  ///
  /// In ar, this message translates to:
  /// **'تعذر الاتصال بالخادم. تحقق من اتصالك وحاول مرة أخرى.'**
  String get errorNetwork;

  /// No description provided for @errorTimeout.
  ///
  /// In ar, this message translates to:
  /// **'استغرق الطلب وقتًا طويلًا. حاول مرة أخرى.'**
  String get errorTimeout;

  /// No description provided for @errorUnauthorized.
  ///
  /// In ar, this message translates to:
  /// **'انتهت الجلسة. يرجى تسجيل الدخول مرة أخرى.'**
  String get errorUnauthorized;

  /// No description provided for @errorForbidden.
  ///
  /// In ar, this message translates to:
  /// **'ليس لديك صلاحية للقيام بهذا الإجراء.'**
  String get errorForbidden;

  /// No description provided for @errorNotFound.
  ///
  /// In ar, this message translates to:
  /// **'العنصر المطلوب غير موجود.'**
  String get errorNotFound;

  /// No description provided for @errorConflict.
  ///
  /// In ar, this message translates to:
  /// **'تم تعديل البيانات بالفعل. حدّث الصفحة وحاول مجددًا.'**
  String get errorConflict;

  /// No description provided for @errorRateLimited.
  ///
  /// In ar, this message translates to:
  /// **'طلبات كثيرة جدًا. حاول مرة أخرى بعد قليل.'**
  String get errorRateLimited;

  /// No description provided for @errorServer.
  ///
  /// In ar, this message translates to:
  /// **'خدمة غير متاحة مؤقتًا. حاول مرة أخرى.'**
  String get errorServer;

  /// No description provided for @errorGeneric.
  ///
  /// In ar, this message translates to:
  /// **'حدث خطأ غير متوقع. حاول مرة أخرى.'**
  String get errorGeneric;

  /// No description provided for @propertiesSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'إدارة منازل وعناوينك لطلبات الخدمة.'**
  String get propertiesSubtitle;

  /// No description provided for @propertiesDefault.
  ///
  /// In ar, this message translates to:
  /// **'افتراضي'**
  String get propertiesDefault;

  /// No description provided for @propertyHistoryTitle.
  ///
  /// In ar, this message translates to:
  /// **'سجل الصيانة'**
  String get propertyHistoryTitle;

  /// No description provided for @propertyHistorySubtitle.
  ///
  /// In ar, this message translates to:
  /// **'كل الزيارات السابقة لهذا العنوان'**
  String get propertyHistorySubtitle;

  /// No description provided for @propertyHistoryEmptyTitle.
  ///
  /// In ar, this message translates to:
  /// **'لا يوجد سجل بعد'**
  String get propertyHistoryEmptyTitle;

  /// No description provided for @propertyHistoryEmptyBody.
  ///
  /// In ar, this message translates to:
  /// **'ستظهر الزيارات المكتملة هنا بعد أول طلب خدمة.'**
  String get propertyHistoryEmptyBody;

  /// No description provided for @propertyRecurringChip.
  ///
  /// In ar, this message translates to:
  /// **'مشكلة متكررة'**
  String get propertyRecurringChip;

  /// No description provided for @propertyRecurringBanner.
  ///
  /// In ar, this message translates to:
  /// **'{count} زيارة مرتبطة بنفس المشكلة على هذا العنوان.'**
  String propertyRecurringBanner(Object count);

  /// No description provided for @complaintFiledChip.
  ///
  /// In ar, this message translates to:
  /// **'تم تقديم شكوى'**
  String get complaintFiledChip;

  /// No description provided for @requestReworkChip.
  ///
  /// In ar, this message translates to:
  /// **'زيارة إصلاح'**
  String get requestReworkChip;

  /// No description provided for @requestInspectionOnly.
  ///
  /// In ar, this message translates to:
  /// **'زيارة معاينة فقط'**
  String get requestInspectionOnly;

  /// No description provided for @requestUrgencyUrgent.
  ///
  /// In ar, this message translates to:
  /// **'عاجل'**
  String get requestUrgencyUrgent;

  /// No description provided for @requestTitleFallback.
  ///
  /// In ar, this message translates to:
  /// **'طلب خدمة'**
  String get requestTitleFallback;

  /// No description provided for @requestDiagnosisLabel.
  ///
  /// In ar, this message translates to:
  /// **'التشخيص'**
  String get requestDiagnosisLabel;

  /// No description provided for @requestResolutionLabel.
  ///
  /// In ar, this message translates to:
  /// **'الحل المنفذ'**
  String get requestResolutionLabel;

  /// No description provided for @requestMaterialsLabel.
  ///
  /// In ar, this message translates to:
  /// **'الخامات المستخدمة'**
  String get requestMaterialsLabel;

  /// No description provided for @requestFinalPriceLabel.
  ///
  /// In ar, this message translates to:
  /// **'السعر النهائي'**
  String get requestFinalPriceLabel;

  /// No description provided for @requestStatusUnknown.
  ///
  /// In ar, this message translates to:
  /// **'حالة غير معروفة'**
  String get requestStatusUnknown;

  /// No description provided for @requestStatusDraft.
  ///
  /// In ar, this message translates to:
  /// **'مسودة'**
  String get requestStatusDraft;

  /// No description provided for @requestStatusSubmitted.
  ///
  /// In ar, this message translates to:
  /// **'تم الإرسال'**
  String get requestStatusSubmitted;

  /// No description provided for @requestStatusUnderReview.
  ///
  /// In ar, this message translates to:
  /// **'قيد المراجعة'**
  String get requestStatusUnderReview;

  /// No description provided for @requestStatusNeedMoreInfo.
  ///
  /// In ar, this message translates to:
  /// **'مطلوب معلومات إضافية'**
  String get requestStatusNeedMoreInfo;

  /// No description provided for @requestStatusInspectionRequired.
  ///
  /// In ar, this message translates to:
  /// **'مطلوب معاينة'**
  String get requestStatusInspectionRequired;

  /// No description provided for @requestStatusInspectionScheduled.
  ///
  /// In ar, this message translates to:
  /// **'معاينة مجدولة'**
  String get requestStatusInspectionScheduled;

  /// No description provided for @requestStatusInspectionInProgress.
  ///
  /// In ar, this message translates to:
  /// **'المعاينة جارية'**
  String get requestStatusInspectionInProgress;

  /// No description provided for @requestStatusInspectionCompleted.
  ///
  /// In ar, this message translates to:
  /// **'انتهت المعاينة'**
  String get requestStatusInspectionCompleted;

  /// No description provided for @requestStatusQuotePreparation.
  ///
  /// In ar, this message translates to:
  /// **'تجهيز عرض السعر'**
  String get requestStatusQuotePreparation;

  /// No description provided for @requestStatusQuoteSent.
  ///
  /// In ar, this message translates to:
  /// **'تم إرسال عرض السعر'**
  String get requestStatusQuoteSent;

  /// No description provided for @requestStatusAwaitingApproval.
  ///
  /// In ar, this message translates to:
  /// **'بانتظار موافقتك'**
  String get requestStatusAwaitingApproval;

  /// No description provided for @requestStatusQuoteRejected.
  ///
  /// In ar, this message translates to:
  /// **'تم رفض عرض السعر'**
  String get requestStatusQuoteRejected;

  /// No description provided for @requestStatusDepositPending.
  ///
  /// In ar, this message translates to:
  /// **'بانتظار دفع التأمين'**
  String get requestStatusDepositPending;

  /// No description provided for @requestStatusDepositVerification.
  ///
  /// In ar, this message translates to:
  /// **'جاري التحقق من الدفع'**
  String get requestStatusDepositVerification;

  /// No description provided for @requestStatusConfirmed.
  ///
  /// In ar, this message translates to:
  /// **'تم التأكيد'**
  String get requestStatusConfirmed;

  /// No description provided for @requestStatusAssignmentPending.
  ///
  /// In ar, this message translates to:
  /// **'بانتظار تعيين فني'**
  String get requestStatusAssignmentPending;

  /// No description provided for @requestStatusTechnicianAssigned.
  ///
  /// In ar, this message translates to:
  /// **'تم تعيين فني'**
  String get requestStatusTechnicianAssigned;

  /// No description provided for @requestStatusOnTheWay.
  ///
  /// In ar, this message translates to:
  /// **'الفني في الطريق'**
  String get requestStatusOnTheWay;

  /// No description provided for @requestStatusArrived.
  ///
  /// In ar, this message translates to:
  /// **'وصل الفني'**
  String get requestStatusArrived;

  /// No description provided for @requestStatusWorkInProgress.
  ///
  /// In ar, this message translates to:
  /// **'جاري العمل'**
  String get requestStatusWorkInProgress;

  /// No description provided for @requestStatusServiceCompleted.
  ///
  /// In ar, this message translates to:
  /// **'اكتمل العمل'**
  String get requestStatusServiceCompleted;

  /// No description provided for @requestStatusPaymentPending.
  ///
  /// In ar, this message translates to:
  /// **'بانتظار الدفع'**
  String get requestStatusPaymentPending;

  /// No description provided for @requestStatusPaymentVerification.
  ///
  /// In ar, this message translates to:
  /// **'جاري التحقق من الدفعة'**
  String get requestStatusPaymentVerification;

  /// No description provided for @requestStatusPaid.
  ///
  /// In ar, this message translates to:
  /// **'تم الدفع'**
  String get requestStatusPaid;

  /// No description provided for @requestStatusAwaitingRating.
  ///
  /// In ar, this message translates to:
  /// **'بانتظار تقييمك'**
  String get requestStatusAwaitingRating;

  /// No description provided for @requestStatusComplaintOpen.
  ///
  /// In ar, this message translates to:
  /// **'شكوى مفتوحة'**
  String get requestStatusComplaintOpen;

  /// No description provided for @requestStatusComplaintUnderReview.
  ///
  /// In ar, this message translates to:
  /// **'شكوى قيد المراجعة'**
  String get requestStatusComplaintUnderReview;

  /// No description provided for @requestStatusRevisitScheduled.
  ///
  /// In ar, this message translates to:
  /// **'زيارة إصلاح مجدولة'**
  String get requestStatusRevisitScheduled;

  /// No description provided for @requestStatusResolved.
  ///
  /// In ar, this message translates to:
  /// **'تم الحل'**
  String get requestStatusResolved;

  /// No description provided for @requestStatusClosed.
  ///
  /// In ar, this message translates to:
  /// **'مغلق'**
  String get requestStatusClosed;

  /// No description provided for @requestStatusCancelled.
  ///
  /// In ar, this message translates to:
  /// **'ملغي'**
  String get requestStatusCancelled;

  /// Relative time: just now
  ///
  /// In ar, this message translates to:
  /// **'الآن'**
  String get timeNow;

  /// Relative time in minutes. {count} is a number.
  ///
  /// In ar, this message translates to:
  /// **'منذ {count} دقيقة'**
  String timeMinutes(int count);

  /// Relative time in hours. {count} is a number.
  ///
  /// In ar, this message translates to:
  /// **'منذ {count} ساعة'**
  String timeHours(int count);

  /// Relative time in days. {count} is a number.
  ///
  /// In ar, this message translates to:
  /// **'منذ {count} يوم'**
  String timeDays(int count);

  /// Relative time in months. {count} is a number.
  ///
  /// In ar, this message translates to:
  /// **'منذ {count} شهر'**
  String timeMonths(int count);

  /// Relative time in years. {count} is a number.
  ///
  /// In ar, this message translates to:
  /// **'منذ {count} سنة'**
  String timeYears(int count);

  /// 12-hour clock meridiem, before noon
  ///
  /// In ar, this message translates to:
  /// **'ص'**
  String get meridiemAm;

  /// Relative time: yesterday
  ///
  /// In ar, this message translates to:
  /// **'أمس'**
  String get timeYesterday;

  /// 12-hour clock meridiem, after noon
  ///
  /// In ar, this message translates to:
  /// **'م'**
  String get meridiemPm;

  /// Requests list filter: every request
  ///
  /// In ar, this message translates to:
  /// **'الكل'**
  String get requestsFilterAll;

  /// Requests list filter: in-flight requests
  ///
  /// In ar, this message translates to:
  /// **'نشطة'**
  String get requestsFilterActive;

  /// Requests list filter: waiting on the customer
  ///
  /// In ar, this message translates to:
  /// **'تحتاج إجراء'**
  String get requestsFilterAction;

  /// Requests list filter: finished requests
  ///
  /// In ar, this message translates to:
  /// **'مكتملة'**
  String get requestsFilterDone;

  /// Wizard step 1 of 5
  ///
  /// In ar, this message translates to:
  /// **'الخدمة'**
  String get requestsStepService;

  /// Wizard step 2 of 5
  ///
  /// In ar, this message translates to:
  /// **'التفاصيل'**
  String get requestsStepDetails;

  /// Wizard step 3 of 5
  ///
  /// In ar, this message translates to:
  /// **'الصور'**
  String get requestsStepPhotos;

  /// Wizard step 4 of 5
  ///
  /// In ar, this message translates to:
  /// **'الموقع'**
  String get requestsStepLocation;

  /// Wizard step 5 of 5
  ///
  /// In ar, this message translates to:
  /// **'المراجعة'**
  String get requestsStepReview;

  /// Wizard progress. {current} and {total} are numbers.
  ///
  /// In ar, this message translates to:
  /// **'الخطوة {current} من {total}'**
  String requestsStepCounter(int total, int current);

  /// Service picker prompt
  ///
  /// In ar, this message translates to:
  /// **'اختر الخدمة'**
  String get requestsServiceChoose;

  /// Catalogue came back empty
  ///
  /// In ar, this message translates to:
  /// **'لا توجد خدمات متاحة'**
  String get requestsServiceEmpty;

  /// Catalogue load failure body
  ///
  /// In ar, this message translates to:
  /// **'تعذر تحميل قائمة الخدمات، حاول مرة أخرى'**
  String get requestsServiceEmptyBody;

  /// Problem type is optional on create
  ///
  /// In ar, this message translates to:
  /// **'نوع المشكلة (اختياري)'**
  String get requestsProblemOptional;

  /// Skip choosing a problem type
  ///
  /// In ar, this message translates to:
  /// **'تخطي'**
  String get requestsProblemSkip;

  /// problem_description minimum length hint
  ///
  /// In ar, this message translates to:
  /// **'اكتب 10 أحرف على الأقل'**
  String get requestsDescTooShort;

  /// problem_description maximum length hint
  ///
  /// In ar, this message translates to:
  /// **'الحد الأقصى 4000 حرف'**
  String get requestsDescTooLong;

  /// Photo picker button
  ///
  /// In ar, this message translates to:
  /// **'إضافة صورة'**
  String get requestsPhotosAdd;

  /// Submit needs media_count > 0
  ///
  /// In ar, this message translates to:
  /// **'يلزم صورة واحدة على الأقل للمتابعة'**
  String get requestsPhotosRequired;

  /// Photo cap. {max} is a number.
  ///
  /// In ar, this message translates to:
  /// **'وصلت للحد الأقصى {max} صور'**
  String requestsPhotosLimit(int max);

  /// Accepted formats and size
  ///
  /// In ar, this message translates to:
  /// **'JPG أو PNG أو WebP، بحد أقصى 12 ميجابايت للصورة'**
  String get requestsPhotosHintSize;

  /// While photos upload
  ///
  /// In ar, this message translates to:
  /// **'جارٍ رفع الصور...'**
  String get requestsPhotosUploading;

  /// Photo counter. Both numbers.
  ///
  /// In ar, this message translates to:
  /// **'{count} من {max} صور'**
  String requestsPhotosCount(int count, int max);

  /// Property picker prompt
  ///
  /// In ar, this message translates to:
  /// **'اختر العقار'**
  String get requestsLocationPick;

  /// No properties exist yet
  ///
  /// In ar, this message translates to:
  /// **'أضف عقاراً أولاً من صفحة العقارات'**
  String get requestsLocationNoProperty;

  /// Address field, required
  ///
  /// In ar, this message translates to:
  /// **'المحافظة'**
  String get requestsAddressGovernorate;

  /// Address field, required
  ///
  /// In ar, this message translates to:
  /// **'المدينة'**
  String get requestsAddressCity;

  /// Address field
  ///
  /// In ar, this message translates to:
  /// **'المنطقة'**
  String get requestsAddressZone;

  /// Address field
  ///
  /// In ar, this message translates to:
  /// **'الحي'**
  String get requestsAddressDistrict;

  /// Address field
  ///
  /// In ar, this message translates to:
  /// **'الشارع'**
  String get requestsAddressStreet;

  /// Address field
  ///
  /// In ar, this message translates to:
  /// **'المبنى'**
  String get requestsAddressBuilding;

  /// Address field
  ///
  /// In ar, this message translates to:
  /// **'الدور'**
  String get requestsAddressFloor;

  /// Address field
  ///
  /// In ar, this message translates to:
  /// **'الشقة'**
  String get requestsAddressApartment;

  /// Address field
  ///
  /// In ar, this message translates to:
  /// **'علامة مميزة'**
  String get requestsAddressLandmark;

  /// Address field
  ///
  /// In ar, this message translates to:
  /// **'ملاحظات للوصول'**
  String get requestsAddressNotes;

  /// Address field; requires a phone
  ///
  /// In ar, this message translates to:
  /// **'اسم جهة الاتصال'**
  String get requestsAddressContactName;

  /// Address field; required with contact_name
  ///
  /// In ar, this message translates to:
  /// **'رقم جهة الاتصال'**
  String get requestsAddressContactPhone;

  /// latitude/longitude required
  ///
  /// In ar, this message translates to:
  /// **'حدد الموقع على الخريطة'**
  String get requestsAddressCoordsMissing;

  /// Review step heading
  ///
  /// In ar, this message translates to:
  /// **'راجع طلبك'**
  String get requestsReviewTitle;

  /// Jump back to a step from review
  ///
  /// In ar, this message translates to:
  /// **'تعديل'**
  String get requestsReviewEdit;

  /// Blockers list heading on review
  ///
  /// In ar, this message translates to:
  /// **'ينقصك التالي:'**
  String get requestsReviewMissing;

  /// Blocker
  ///
  /// In ar, this message translates to:
  /// **'اختر الخدمة'**
  String get requestsReviewMissingService;

  /// Blocker
  ///
  /// In ar, this message translates to:
  /// **'أكمل العنوان'**
  String get requestsReviewMissingLocation;

  /// Blocker
  ///
  /// In ar, this message translates to:
  /// **'اكتب وصف المشكلة'**
  String get requestsReviewMissingDetails;

  /// Blocker
  ///
  /// In ar, this message translates to:
  /// **'أضف صورة واحدة على الأقل'**
  String get requestsReviewMissingPhotos;

  /// While the request is created and uploaded
  ///
  /// In ar, this message translates to:
  /// **'جارٍ إرسال الطلب...'**
  String get requestsSubmitting;

  /// Retry after a partial submit failure
  ///
  /// In ar, this message translates to:
  /// **'حاول مرة أخرى'**
  String get requestsSubmitRetry;

  /// Progress note during submit
  ///
  /// In ar, this message translates to:
  /// **'تم إنشاء مسودة، سنكمل الرفع'**
  String get requestsCreatedDraft;

  /// Empty property list in the wizard
  ///
  /// In ar, this message translates to:
  /// **'لا يوجد عقار مسجل'**
  String get requestsNoProperty;

  /// Urgency option
  ///
  /// In ar, this message translates to:
  /// **'عادي'**
  String get requestsUrgencyNormal;

  /// Urgency option
  ///
  /// In ar, this message translates to:
  /// **'عاجل'**
  String get requestsUrgencyUrgentLabel;

  /// inspection_only explanation
  ///
  /// In ar, this message translates to:
  /// **'فحص فقط بدون تنفيذ'**
  String get requestsInspectionOnlyHint;

  /// customer_notes field
  ///
  /// In ar, this message translates to:
  /// **'ملاحظات إضافية'**
  String get requestsNoteLabel;

  /// request reference_code label
  ///
  /// In ar, this message translates to:
  /// **'رقم الطلب'**
  String get requestsReferenceCode;

  /// List count. {count} is a number.
  ///
  /// In ar, this message translates to:
  /// **'{count} طلب'**
  String requestsCountLabel(int count);

  /// Cross-field validation message
  ///
  /// In ar, this message translates to:
  /// **'أدخل رقم جهة الاتصال عند تحديد اسم جهة الاتصال'**
  String get requestsAddressContactPairError;

  /// No description provided for @requestsNewActivity.
  ///
  /// In ar, this message translates to:
  /// **'تحديث جديد'**
  String get requestsNewActivity;

  /// Requests tab list count. {count} is a number.
  ///
  /// In ar, this message translates to:
  /// **'{count} طلب'**
  String requestsListCount(int count);

  /// commonCurrency copy
  ///
  /// In ar, this message translates to:
  /// **'{amount} ج.م'**
  String commonCurrency(Object amount);

  /// requestDetailProblemTitle copy
  ///
  /// In ar, this message translates to:
  /// **'وصف المشكلة'**
  String get requestDetailProblemTitle;

  /// requestDetailPhotos copy
  ///
  /// In ar, this message translates to:
  /// **'الصور ({count})'**
  String requestDetailPhotos(Object count);

  /// requestDetailAddressTitle copy
  ///
  /// In ar, this message translates to:
  /// **'عنوان الزيارة'**
  String get requestDetailAddressTitle;

  /// requestDetailTechnicianTitle copy
  ///
  /// In ar, this message translates to:
  /// **'الفني'**
  String get requestDetailTechnicianTitle;

  /// requestDetailNoTimeline copy
  ///
  /// In ar, this message translates to:
  /// **'لا توجد تحديثات بعد'**
  String get requestDetailNoTimeline;

  /// requestDetailAddedByYou copy
  ///
  /// In ar, this message translates to:
  /// **'أضافته أنت'**
  String get requestDetailAddedByYou;

  /// requestDetailAddedByTeam copy
  ///
  /// In ar, this message translates to:
  /// **'أضافه فريق الخدمة'**
  String get requestDetailAddedByTeam;

  /// quoteServiceCost copy
  ///
  /// In ar, this message translates to:
  /// **'الخدمة'**
  String get quoteServiceCost;

  /// quoteMaterialsCost copy
  ///
  /// In ar, this message translates to:
  /// **'المواد'**
  String get quoteMaterialsCost;

  /// quoteUrgencyFee copy
  ///
  /// In ar, this message translates to:
  /// **'رسوم العاجل'**
  String get quoteUrgencyFee;

  /// quoteInspectionFee copy
  ///
  /// In ar, this message translates to:
  /// **'رسوم المعاينة'**
  String get quoteInspectionFee;

  /// quoteDiscount copy
  ///
  /// In ar, this message translates to:
  /// **'الخصم'**
  String get quoteDiscount;

  /// quoteSubtotal copy
  ///
  /// In ar, this message translates to:
  /// **'المجموع الفرعي'**
  String get quoteSubtotal;

  /// quoteTotal copy
  ///
  /// In ar, this message translates to:
  /// **'الإجمالي'**
  String get quoteTotal;

  /// quoteDuration copy
  ///
  /// In ar, this message translates to:
  /// **'المدة التقديرية'**
  String get quoteDuration;

  /// quoteDurationValue copy
  ///
  /// In ar, this message translates to:
  /// **'{count} دقيقة'**
  String quoteDurationValue(Object count);

  /// quoteRevision copy
  ///
  /// In ar, this message translates to:
  /// **'العرض رقم {count}'**
  String quoteRevision(Object count);

  /// quoteValidUntil copy
  ///
  /// In ar, this message translates to:
  /// **'صالح حتى {date}'**
  String quoteValidUntil(Object date);

  /// quoteNotes copy
  ///
  /// In ar, this message translates to:
  /// **'ملاحظات'**
  String get quoteNotes;

  /// quoteItemsTitle copy
  ///
  /// In ar, this message translates to:
  /// **'ما يشمله العرض'**
  String get quoteItemsTitle;

  /// quoteActionableEnded copy
  ///
  /// In ar, this message translates to:
  /// **'لم يعد هذا العرض قابلًا للقبول'**
  String get quoteActionableEnded;

  /// cancelRefundPreview copy
  ///
  /// In ar, this message translates to:
  /// **'معاينة الاسترداد'**
  String get cancelRefundPreview;

  /// cancelRefundAmount copy
  ///
  /// In ar, this message translates to:
  /// **'سيتم رد لك'**
  String get cancelRefundAmount;

  /// cancelDeductionAmount copy
  ///
  /// In ar, this message translates to:
  /// **'يُخصم من العربون'**
  String get cancelDeductionAmount;

  /// cancelNeedsApproval copy
  ///
  /// In ar, this message translates to:
  /// **'هذا الطلب يحتاج موافقة الفريق قبل الإلغاء'**
  String get cancelNeedsApproval;

  /// cancelReasonLabel copy
  ///
  /// In ar, this message translates to:
  /// **'سبب الإلغاء (اختياري)'**
  String get cancelReasonLabel;

  /// cancelReasonHint copy
  ///
  /// In ar, this message translates to:
  /// **'أخبرنا بما حدث حتى نتحسن'**
  String get cancelReasonHint;

  /// requestCancelAction copy
  ///
  /// In ar, this message translates to:
  /// **'إلغاء الطلب'**
  String get requestCancelAction;

  /// requestRateAction copy
  ///
  /// In ar, this message translates to:
  /// **'تقييم الخدمة'**
  String get requestRateAction;

  /// requestComplainAction copy
  ///
  /// In ar, this message translates to:
  /// **'الإبلاغ عن مشكلة'**
  String get requestComplainAction;

  /// ordersEmptyTitle copy
  ///
  /// In ar, this message translates to:
  /// **'لا توجد طلبات بعد'**
  String get ordersEmptyTitle;

  /// ordersEmptyBody copy
  ///
  /// In ar, this message translates to:
  /// **'عند حجز أي خدمة ستظهر هنا'**
  String get ordersEmptyBody;

  /// orderComplaintOpenChip copy
  ///
  /// In ar, this message translates to:
  /// **'شكوى'**
  String get orderComplaintOpenChip;

  /// orderNoTotalYet copy
  ///
  /// In ar, this message translates to:
  /// **'بانتظار التسعير'**
  String get orderNoTotalYet;

  /// orderArrivalNotScheduled copy
  ///
  /// In ar, this message translates to:
  /// **'لم يتم تحديد موعد الوصول بعد'**
  String get orderArrivalNotScheduled;

  /// orderArrivalNotScheduledBody copy
  ///
  /// In ar, this message translates to:
  /// **'سنعرض موعد الوصول فور تعيين الفني'**
  String get orderArrivalNotScheduledBody;

  /// orderWorkStarted copy
  ///
  /// In ar, this message translates to:
  /// **'بدء العمل'**
  String get orderWorkStarted;

  /// orderWorkCompleted copy
  ///
  /// In ar, this message translates to:
  /// **'انتهاء العمل'**
  String get orderWorkCompleted;

  /// orderServiceCompleted copy
  ///
  /// In ar, this message translates to:
  /// **'تم إنجاز الخدمة'**
  String get orderServiceCompleted;

  /// orderViewFullRequest copy
  ///
  /// In ar, this message translates to:
  /// **'عرض تفاصيل الطلب'**
  String get orderViewFullRequest;

  /// ordersEmptyCta copy
  ///
  /// In ar, this message translates to:
  /// **'احجز خدمة'**
  String get ordersEmptyCta;

  /// supportDefaultSubject copy
  ///
  /// In ar, this message translates to:
  /// **'طلب دعم'**
  String get supportDefaultSubject;

  /// supportThreadClosed copy
  ///
  /// In ar, this message translates to:
  /// **'مغلق'**
  String get supportThreadClosed;

  /// supportUnreadCount copy
  ///
  /// In ar, this message translates to:
  /// **'غير مقروء ({count})'**
  String supportUnreadCount(Object count);

  /// supportThreadsTitle copy
  ///
  /// In ar, this message translates to:
  /// **'محادثاتك'**
  String get supportThreadsTitle;

  /// supportThreadsEmptyTitle copy
  ///
  /// In ar, this message translates to:
  /// **'لا توجد محادثات بعد'**
  String get supportThreadsEmptyTitle;

  /// supportThreadsEmptyBody copy
  ///
  /// In ar, this message translates to:
  /// **'راسل الفريق وستظهر الردود هنا'**
  String get supportThreadsEmptyBody;

  /// supportNewConversation copy
  ///
  /// In ar, this message translates to:
  /// **'رسالة جديدة'**
  String get supportNewConversation;

  /// supportComplaintsTitle copy
  ///
  /// In ar, this message translates to:
  /// **'شكاواي'**
  String get supportComplaintsTitle;

  /// supportComplaintsEmptyTitle copy
  ///
  /// In ar, this message translates to:
  /// **'لا توجد شكاوى'**
  String get supportComplaintsEmptyTitle;

  /// supportComplaintsEmptyBody copy
  ///
  /// In ar, this message translates to:
  /// **'أبلغ عن مشكلة في خدمة منجزة من هنا'**
  String get supportComplaintsEmptyBody;

  /// complaintStatusOpen copy
  ///
  /// In ar, this message translates to:
  /// **'مفتوحة'**
  String get complaintStatusOpen;

  /// complaintStatusUnderReview copy
  ///
  /// In ar, this message translates to:
  /// **'قيد المراجعة'**
  String get complaintStatusUnderReview;

  /// complaintStatusQcRequired copy
  ///
  /// In ar, this message translates to:
  /// **'فحص جودة'**
  String get complaintStatusQcRequired;

  /// complaintStatusRevisitRequired copy
  ///
  /// In ar, this message translates to:
  /// **'زيارة أخرى مطلوبة'**
  String get complaintStatusRevisitRequired;

  /// complaintStatusRevisitScheduled copy
  ///
  /// In ar, this message translates to:
  /// **'تمت جدولة زيارة أخرى'**
  String get complaintStatusRevisitScheduled;

  /// complaintStatusResolved copy
  ///
  /// In ar, this message translates to:
  /// **'تم الحل'**
  String get complaintStatusResolved;

  /// complaintStatusClosed copy
  ///
  /// In ar, this message translates to:
  /// **'مغلقة'**
  String get complaintStatusClosed;

  /// complaintReworkScheduled copy
  ///
  /// In ar, this message translates to:
  /// **'تمت جدولة زيارة إصلاح'**
  String get complaintReworkScheduled;

  /// complaintSubjectHint copy
  ///
  /// In ar, this message translates to:
  /// **'ما موضوع الرسالة؟'**
  String get complaintSubjectHint;

  /// complaintMessageHint copy
  ///
  /// In ar, this message translates to:
  /// **'اشرح المشكلة بالتفصيل'**
  String get complaintMessageHint;

  /// complaintSubmitHint copy
  ///
  /// In ar, this message translates to:
  /// **'10 أحرف على الأقل'**
  String get complaintSubmitHint;

  /// complaintFiledSuccess copy
  ///
  /// In ar, this message translates to:
  /// **'تم إرسال الشكوى'**
  String get complaintFiledSuccess;

  /// complaintPickReason copy
  ///
  /// In ar, this message translates to:
  /// **'اختر نوع الشكوى'**
  String get complaintPickReason;

  /// supportMessagesEmpty copy
  ///
  /// In ar, this message translates to:
  /// **'لا توجد رسائل بعد'**
  String get supportMessagesEmpty;

  /// complaintReasonWorkNotDone copy
  ///
  /// In ar, this message translates to:
  /// **'لم يتم إنجاز العمل'**
  String get complaintReasonWorkNotDone;

  /// complaintReasonPoorQuality copy
  ///
  /// In ar, this message translates to:
  /// **'جودة عمل غير مقبولة'**
  String get complaintReasonPoorQuality;

  /// complaintReasonOvercharge copy
  ///
  /// In ar, this message translates to:
  /// **'سعر أعلى من المتفق'**
  String get complaintReasonOvercharge;

  /// complaintReasonTechnicianLate copy
  ///
  /// In ar, this message translates to:
  /// **'تأخر الفني عن موعده'**
  String get complaintReasonTechnicianLate;

  /// complaintReasonDamage copy
  ///
  /// In ar, this message translates to:
  /// **'تسبب في ضرر'**
  String get complaintReasonDamage;

  /// complaintReasonRecurringFault copy
  ///
  /// In ar, this message translates to:
  /// **'المشكلة تكررت'**
  String get complaintReasonRecurringFault;

  /// complaintReasonOther copy
  ///
  /// In ar, this message translates to:
  /// **'سبب آخر'**
  String get complaintReasonOther;

  /// paymentViewTitle copy
  ///
  /// In ar, this message translates to:
  /// **'الدفع'**
  String get paymentViewTitle;

  /// paymentAmountDue copy
  ///
  /// In ar, this message translates to:
  /// **'المبلغ المستحق'**
  String get paymentAmountDue;

  /// paymentFullyPaid copy
  ///
  /// In ar, this message translates to:
  /// **'لا يوجد مستحق'**
  String get paymentFullyPaid;

  /// paymentQuoteTotal copy
  ///
  /// In ar, this message translates to:
  /// **'الإجمالي المتفق عليه'**
  String get paymentQuoteTotal;

  /// paymentSubmitEvidence copy
  ///
  /// In ar, this message translates to:
  /// **'إرسال إثبات الدفع'**
  String get paymentSubmitEvidence;

  /// paymentChooseMethod copy
  ///
  /// In ar, this message translates to:
  /// **'كيف دفعت؟'**
  String get paymentChooseMethod;

  /// paymentAmount copy
  ///
  /// In ar, this message translates to:
  /// **'المبلغ'**
  String get paymentAmount;

  /// paymentReferenceNumber copy
  ///
  /// In ar, this message translates to:
  /// **'رقم عملية التحويل'**
  String get paymentReferenceNumber;

  /// paymentReferenceHint copy
  ///
  /// In ar, this message translates to:
  /// **'أدخل الرقم من إيصال التحويل'**
  String get paymentReferenceHint;

  /// paymentReferenceRequired copy
  ///
  /// In ar, this message translates to:
  /// **'تحويلات المحافظ تحتاج رقم عملية'**
  String get paymentReferenceRequired;

  /// paymentEvidenceSubmitted copy
  ///
  /// In ar, this message translates to:
  /// **'تم إرسال إثبات الدفع للمراجعة'**
  String get paymentEvidenceSubmitted;

  /// paymentHistory copy
  ///
  /// In ar, this message translates to:
  /// **'سجل الدفعات'**
  String get paymentHistory;

  /// paymentRefunds copy
  ///
  /// In ar, this message translates to:
  /// **'المبالغ المستردة'**
  String get paymentRefunds;

  /// paymentRefundReason copy
  ///
  /// In ar, this message translates to:
  /// **'السبب'**
  String get paymentRefundReason;

  /// paymentNoHistory copy
  ///
  /// In ar, this message translates to:
  /// **'لم ترسل أي دفعات بعد'**
  String get paymentNoHistory;

  /// paymentDepositPaid copy
  ///
  /// In ar, this message translates to:
  /// **'تم دفع العربون'**
  String get paymentDepositPaid;

  /// paymentDepositOutstanding copy
  ///
  /// In ar, this message translates to:
  /// **'متبقٍ من العربون'**
  String get paymentDepositOutstanding;

  /// paymentDepositNotRequired copy
  ///
  /// In ar, this message translates to:
  /// **'لا يوجد عربون مطلوب'**
  String get paymentDepositNotRequired;

  /// paymentAttachReceipt copy
  ///
  /// In ar, this message translates to:
  /// **'إرفاق الإيصال'**
  String get paymentAttachReceipt;

  /// paymentReceiptAttached copy
  ///
  /// In ar, this message translates to:
  /// **'تم إرفاق الإيصال'**
  String get paymentReceiptAttached;

  /// paymentReceiptFailed copy
  ///
  /// In ar, this message translates to:
  /// **'تعذر إرفاق الإيصال'**
  String get paymentReceiptFailed;

  /// paymentVerifiedOn copy
  ///
  /// In ar, this message translates to:
  /// **'تم التحقق في'**
  String get paymentVerifiedOn;

  /// paymentRejectedReason copy
  ///
  /// In ar, this message translates to:
  /// **'سبب الرفض'**
  String get paymentRejectedReason;

  /// paymentIsDeposit copy
  ///
  /// In ar, this message translates to:
  /// **'هذا المبلغ هو دفع العربون'**
  String get paymentIsDeposit;

  /// paymentStatusPending copy
  ///
  /// In ar, this message translates to:
  /// **'معلق'**
  String get paymentStatusPending;

  /// paymentStatusVerificationPending copy
  ///
  /// In ar, this message translates to:
  /// **'بانتظار التحقق'**
  String get paymentStatusVerificationPending;

  /// paymentStatusVerified copy
  ///
  /// In ar, this message translates to:
  /// **'تم التحقق'**
  String get paymentStatusVerified;

  /// paymentStatusRejected copy
  ///
  /// In ar, this message translates to:
  /// **'مرفوض'**
  String get paymentStatusRejected;

  /// paymentStatusRefunded copy
  ///
  /// In ar, this message translates to:
  /// **'تم الاسترداد'**
  String get paymentStatusRefunded;

  /// paymentStatusPartiallyRefunded copy
  ///
  /// In ar, this message translates to:
  /// **'تم استرداد جزئي'**
  String get paymentStatusPartiallyRefunded;

  /// paymentMethodCash copy
  ///
  /// In ar, this message translates to:
  /// **'نقدًا عند الإنجاز'**
  String get paymentMethodCash;

  /// paymentMethodVodafoneCash copy
  ///
  /// In ar, this message translates to:
  /// **'فودافون كاش'**
  String get paymentMethodVodafoneCash;

  /// paymentMethodInstaPay copy
  ///
  /// In ar, this message translates to:
  /// **'إنستا باي'**
  String get paymentMethodInstaPay;

  /// paymentSupportPhone copy
  ///
  /// In ar, this message translates to:
  /// **'دعم العملاء المالي'**
  String get paymentSupportPhone;

  /// paymentInstructionsTitle copy
  ///
  /// In ar, this message translates to:
  /// **'طريقة الدفع'**
  String get paymentInstructionsTitle;

  /// paymentRefundProcessed copy
  ///
  /// In ar, this message translates to:
  /// **'تمت المعالجة'**
  String get paymentRefundProcessed;

  /// paymentRefundApproved copy
  ///
  /// In ar, this message translates to:
  /// **'معتمد'**
  String get paymentRefundApproved;

  /// paymentRefundRejected copy
  ///
  /// In ar, this message translates to:
  /// **'مرفوض'**
  String get paymentRefundRejected;

  /// paymentAmountPaid copy
  ///
  /// In ar, this message translates to:
  /// **'المدفوع'**
  String get paymentAmountPaid;

  /// paymentRefundedAmount copy
  ///
  /// In ar, this message translates to:
  /// **'المسترد'**
  String get paymentRefundedAmount;

  /// paymentDueDate copy
  ///
  /// In ar, this message translates to:
  /// **'الاستحقاق'**
  String get paymentDueDate;

  /// paymentRefundPending copy
  ///
  /// In ar, this message translates to:
  /// **'جارٍ الاسترداد'**
  String get paymentRefundPending;

  /// reviewModerationPending copy
  ///
  /// In ar, this message translates to:
  /// **'بانتظار المراجعة'**
  String get reviewModerationPending;

  /// reviewModerationApproved copy
  ///
  /// In ar, this message translates to:
  /// **'منشور'**
  String get reviewModerationApproved;

  /// reviewModerationHidden copy
  ///
  /// In ar, this message translates to:
  /// **'مخفي'**
  String get reviewModerationHidden;

  /// reviewModerationRejected copy
  ///
  /// In ar, this message translates to:
  /// **'مرفوض'**
  String get reviewModerationRejected;

  /// reviewNoneTitle copy
  ///
  /// In ar, this message translates to:
  /// **'لا توجد تقييمات بعد'**
  String get reviewNoneTitle;

  /// reviewNoneBody copy
  ///
  /// In ar, this message translates to:
  /// **'قيّم خدمة منجزة لمساعدة العملاء الآخرين'**
  String get reviewNoneBody;

  /// reviewSubmitted copy
  ///
  /// In ar, this message translates to:
  /// **'شكرًا لتقييمك'**
  String get reviewSubmitted;

  /// reviewAwaitingModerationNote copy
  ///
  /// In ar, this message translates to:
  /// **'سيظهر تقييمك للعامة بعد مراجعته'**
  String get reviewAwaitingModerationNote;

  /// reviewStarsLabel copy
  ///
  /// In ar, this message translates to:
  /// **'{count} من 5'**
  String reviewStarsLabel(Object count);

  /// reviewCommentLabel copy
  ///
  /// In ar, this message translates to:
  /// **'التعليق'**
  String get reviewCommentLabel;

  /// reviewCommentOptional copy
  ///
  /// In ar, this message translates to:
  /// **'اختياري'**
  String get reviewCommentOptional;

  /// reviewRatingRequired copy
  ///
  /// In ar, this message translates to:
  /// **'اختر التقييم أولًا'**
  String get reviewRatingRequired;

  /// notificationsMarkAllRead copy
  ///
  /// In ar, this message translates to:
  /// **'تحديد الكل كمقروء'**
  String get notificationsMarkAllRead;

  /// notificationsEmptyTitle copy
  ///
  /// In ar, this message translates to:
  /// **'لا توجد إشعارات'**
  String get notificationsEmptyTitle;

  /// notificationsEmptyBody copy
  ///
  /// In ar, this message translates to:
  /// **'ستظهر هنا تحديثات طلباتك ورسائل الدعم.'**
  String get notificationsEmptyBody;

  /// notificationsUnknownType copy
  ///
  /// In ar, this message translates to:
  /// **'نوع جديد'**
  String get notificationsUnknownType;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
