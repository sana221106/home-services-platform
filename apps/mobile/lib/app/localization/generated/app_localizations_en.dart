// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Home Services';

  @override
  String get appTagline => 'Everything your home needs, in one place';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonContinue => 'Continue';

  @override
  String get commonBack => 'Back';

  @override
  String get commonNext => 'Next';

  @override
  String get commonSkip => 'Skip';

  @override
  String get commonSave => 'Save';

  @override
  String get commonSubmit => 'Send';

  @override
  String get commonSearch => 'Search';

  @override
  String get commonClose => 'Close';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonSeeAll => 'See all';

  @override
  String get commonSeeDetails => 'See details';

  @override
  String get commonLoading => 'Loading…';

  @override
  String get commonSomethingWentWrong =>
      'Something went wrong. Please try again.';

  @override
  String get commonNoResults => 'No results';

  @override
  String get commonRequiredField => 'This field is required';

  @override
  String get commonOptional => 'Optional';

  @override
  String get comingSoon => 'This screen is still being built.';

  @override
  String get homeTabLabel => 'Home';

  @override
  String get requestsTabLabel => 'Requests';

  @override
  String get propertiesTabLabel => 'Properties';

  @override
  String get supportTabLabel => 'Support';

  @override
  String get profileTabLabel => 'Account';

  @override
  String get onboardingWelcomeTitle => 'Welcome';

  @override
  String get onboardingWelcomeBody =>
      'Book a plumber, electrician, AC service or cleaning — and follow every step in real time.';

  @override
  String get onboardingHowItWorksTitle => 'How it works';

  @override
  String get onboardingStepChoose => 'Choose a service';

  @override
  String get onboardingStepDescribe => 'Describe the problem and photograph it';

  @override
  String get onboardingStepQuote => 'Receive a price quote';

  @override
  String get onboardingStepTrack => 'Track progress and rate the job';

  @override
  String get onboardingGetStarted => 'Get started';

  @override
  String get authPhoneTitle => 'Phone number';

  @override
  String get authPhoneBody => 'Enter your phone number to continue';

  @override
  String get authPhoneLabel => 'Phone number';

  @override
  String get authPhoneHint => '01xxxxxxxxx';

  @override
  String get authPhoneInvalid => 'Invalid phone number';

  @override
  String get authPhoneNewAccountHint =>
      'New number? We will create your account automatically after verification.';

  @override
  String get authPhoneRequired =>
      'Phone number is unknown. Please enter it again.';

  @override
  String get authNameLabel => 'Full name';

  @override
  String get authNameHint => 'Enter your name';

  @override
  String get authOtpTitle => 'Verification code';

  @override
  String authOtpBody(Object count) {
    return 'We sent a $count-digit code to your phone';
  }

  @override
  String authOtpResendIn(Object seconds) {
    return 'Resend in ${seconds}s';
  }

  @override
  String get authOtpResendNow => 'Resend code';

  @override
  String get authOtpVerify => 'Verify';

  @override
  String get authOtpChangeNumber => 'Change phone number';

  @override
  String get authOtpField => 'Verification code';

  @override
  String get authOtpSent => 'Verification code sent';

  @override
  String homeGreeting(Object name) {
    return 'Hello, $name';
  }

  @override
  String get homeActiveRequestTitle => 'Active request';

  @override
  String get homeQuickActions => 'Quick services';

  @override
  String get homeRecentRequests => 'Your recent requests';

  @override
  String get homeSeeAllRequests => 'See all requests';

  @override
  String get homeNoActiveRequest => 'No active request right now';

  @override
  String get homeStartRequest => 'Start a new request';

  @override
  String get homeUpcomingVisit => 'Your next visit';

  @override
  String get requestsTitle => 'Requests';

  @override
  String get requestsNew => 'New request';

  @override
  String get requestsActive => 'Active';

  @override
  String get requestsHistory => 'History';

  @override
  String get requestsEmptyTitle => 'No requests yet';

  @override
  String get requestsEmptyBody => 'Start with your first service request';

  @override
  String get requestsCategoryTitle => 'Choose a service';

  @override
  String get requestsProblemTitle => 'What is the problem?';

  @override
  String get requestsDescribeTitle => 'Describe the problem';

  @override
  String get requestsDescribeHint =>
      'Write a clear description of the problem…';

  @override
  String get requestsPhotosTitle => 'Add photos';

  @override
  String get requestsPhotosHint =>
      'Clear photos help the technician quote accurately';

  @override
  String requestsPhotosMax(Object count) {
    return 'Up to $count photos';
  }

  @override
  String get requestsAddressTitle => 'Address';

  @override
  String get requestsPropertyTitle => 'Choose property';

  @override
  String get requestsScheduleTitle => 'Visit time';

  @override
  String get requestsScheduleUrgent => 'Urgent';

  @override
  String get requestsScheduleUrgentHint =>
      'We will serve you at the earliest available slot';

  @override
  String get requestsSubmit => 'Submit request';

  @override
  String get requestsSubmitSuccess => 'Your request was submitted successfully';

  @override
  String get requestDetailTitle => 'Request details';

  @override
  String get requestTimelineTitle => 'Request stages';

  @override
  String get requestQuoteTitle => 'Price quote';

  @override
  String get requestQuoteAccept => 'Accept quote';

  @override
  String get requestQuoteReject => 'Reject';

  @override
  String get requestQuoteExpired => 'This quote has expired';

  @override
  String get requestQuoteNeedsInfo => 'More information needed';

  @override
  String get requestDepositTitle => 'Deposit';

  @override
  String get requestDepositAmount => 'Deposit amount';

  @override
  String get requestCancelTitle => 'Cancel request';

  @override
  String get requestCancelWarning =>
      'Deposit refunds may take longer depending on the cancellation policy.';

  @override
  String get requestCancelConfirm => 'Confirm cancellation';

  @override
  String get requestAddInfo => 'Send additional information';

  @override
  String get ordersTitle => 'My requests';

  @override
  String get orderTrackTitle => 'Track request';

  @override
  String get orderTechnicianOnWay => 'Technician is on the way';

  @override
  String get orderTechnicianArrived => 'Technician has arrived';

  @override
  String get orderTimelineTitle => 'Progress';

  @override
  String get orderEta => 'Estimated arrival';

  @override
  String get orderCancel => 'Cancel';

  @override
  String get paymentsTitle => 'Payments';

  @override
  String get paymentsMethods => 'Available payment methods';

  @override
  String get paymentsUploadProof => 'Upload payment proof';

  @override
  String get paymentsProofHint => 'A clear photo of the receipt or transfer';

  @override
  String get paymentsPendingVerification => 'Pending verification';

  @override
  String get paymentsVerified => 'Verified';

  @override
  String get paymentsRejected => 'Rejected';

  @override
  String get paymentsRefundPending => 'Refund in progress';

  @override
  String get propertiesTitle => 'My properties';

  @override
  String get propertiesAdd => 'Add property';

  @override
  String get propertiesEmptyTitle => 'No properties';

  @override
  String get propertiesEmptyBody =>
      'Add your properties to create requests faster';

  @override
  String get propertiesLabel => 'Property name';

  @override
  String get propertiesSetDefault => 'Set as default';

  @override
  String get propertiesHistory => 'Maintenance history';

  @override
  String get supportTitle => 'Support';

  @override
  String get supportChatTitle => 'Chat';

  @override
  String get supportMessageHint => 'Type your message…';

  @override
  String get supportSend => 'Send';

  @override
  String get supportComplaintTitle => 'Submit a complaint';

  @override
  String get supportComplaintReasons => 'Complaint type';

  @override
  String get supportComplaintDetails => 'Complaint details';

  @override
  String get supportComplaintSubmit => 'Submit complaint';

  @override
  String get reviewsTitle => 'Your reviews';

  @override
  String get reviewsWrite => 'Write a review';

  @override
  String get reviewsRatingLabel => 'Rate this service';

  @override
  String get reviewsCommentHint => 'Add a comment (optional)';

  @override
  String get reviewsSubmit => 'Submit review';

  @override
  String get profileTitle => 'My account';

  @override
  String get profileEdit => 'Edit profile';

  @override
  String get profileSettings => 'Settings';

  @override
  String get profileLanguage => 'Language';

  @override
  String get profileTheme => 'Appearance';

  @override
  String get profileNotifications => 'Notifications';

  @override
  String get profileLogout => 'Log out';

  @override
  String get profileSupport => 'Contact us';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeSystem => 'System';

  @override
  String get errorNetwork =>
      'Could not reach the server. Check your connection and try again.';

  @override
  String get errorTimeout => 'The request took too long. Please try again.';

  @override
  String get errorUnauthorized => 'Your session expired. Please sign in again.';

  @override
  String get errorForbidden => 'You do not have permission to do this.';

  @override
  String get errorNotFound => 'The requested item was not found.';

  @override
  String get errorConflict =>
      'The data was already changed. Refresh and try again.';

  @override
  String get errorRateLimited => 'Too many requests. Please try again shortly.';

  @override
  String get errorServer =>
      'Service temporarily unavailable. Please try again.';

  @override
  String get errorGeneric => 'Something went wrong. Please try again.';

  @override
  String get propertiesSubtitle =>
      'Manage your homes and addresses for service requests.';

  @override
  String get propertiesDefault => 'Default';

  @override
  String get propertyHistoryTitle => 'Maintenance history';

  @override
  String get propertyHistorySubtitle => 'Every past visit for this address';

  @override
  String get propertyHistoryEmptyTitle => 'No history yet';

  @override
  String get propertyHistoryEmptyBody =>
      'Completed visits will appear here after your first service request.';

  @override
  String get propertyRecurringChip => 'Recurring issue';

  @override
  String propertyRecurringBanner(Object count) {
    return '$count visits linked to the same issue at this address.';
  }

  @override
  String get complaintFiledChip => 'Complaint filed';

  @override
  String get requestReworkChip => 'Rework visit';

  @override
  String get requestInspectionOnly => 'Inspection only';

  @override
  String get requestUrgencyUrgent => 'Urgent';

  @override
  String get requestTitleFallback => 'Service request';

  @override
  String get requestDiagnosisLabel => 'Diagnosis';

  @override
  String get requestResolutionLabel => 'Resolution';

  @override
  String get requestMaterialsLabel => 'Materials used';

  @override
  String get requestFinalPriceLabel => 'Final price';

  @override
  String get requestStatusUnknown => 'Unknown status';

  @override
  String get requestStatusDraft => 'Draft';

  @override
  String get requestStatusSubmitted => 'Submitted';

  @override
  String get requestStatusUnderReview => 'Under review';

  @override
  String get requestStatusNeedMoreInfo => 'More information needed';

  @override
  String get requestStatusInspectionRequired => 'Inspection required';

  @override
  String get requestStatusInspectionScheduled => 'Inspection scheduled';

  @override
  String get requestStatusInspectionInProgress => 'Inspection in progress';

  @override
  String get requestStatusInspectionCompleted => 'Inspection completed';

  @override
  String get requestStatusQuotePreparation => 'Preparing quote';

  @override
  String get requestStatusQuoteSent => 'Quote sent';

  @override
  String get requestStatusAwaitingApproval => 'Awaiting your approval';

  @override
  String get requestStatusQuoteRejected => 'Quote rejected';

  @override
  String get requestStatusDepositPending => 'Deposit pending';

  @override
  String get requestStatusDepositVerification => 'Verifying deposit';

  @override
  String get requestStatusConfirmed => 'Confirmed';

  @override
  String get requestStatusAssignmentPending => 'Assigning technician';

  @override
  String get requestStatusTechnicianAssigned => 'Technician assigned';

  @override
  String get requestStatusOnTheWay => 'Technician on the way';

  @override
  String get requestStatusArrived => 'Technician arrived';

  @override
  String get requestStatusWorkInProgress => 'Work in progress';

  @override
  String get requestStatusServiceCompleted => 'Service completed';

  @override
  String get requestStatusPaymentPending => 'Payment pending';

  @override
  String get requestStatusPaymentVerification => 'Verifying payment';

  @override
  String get requestStatusPaid => 'Paid';

  @override
  String get requestStatusAwaitingRating => 'Awaiting your rating';

  @override
  String get requestStatusComplaintOpen => 'Complaint open';

  @override
  String get requestStatusComplaintUnderReview => 'Complaint under review';

  @override
  String get requestStatusRevisitScheduled => 'Rework visit scheduled';

  @override
  String get requestStatusResolved => 'Resolved';

  @override
  String get requestStatusClosed => 'Closed';

  @override
  String get requestStatusCancelled => 'Cancelled';

  @override
  String get timeNow => 'now';

  @override
  String timeMinutes(int count) {
    return '$count min ago';
  }

  @override
  String timeHours(int count) {
    return '$count h ago';
  }

  @override
  String timeDays(int count) {
    return '$count d ago';
  }

  @override
  String timeMonths(int count) {
    return '$count mo ago';
  }

  @override
  String timeYears(int count) {
    return '$count y ago';
  }

  @override
  String get meridiemAm => 'AM';

  @override
  String get timeYesterday => 'yesterday';

  @override
  String get meridiemPm => 'PM';

  @override
  String get requestsFilterAll => 'All';

  @override
  String get requestsFilterActive => 'Active';

  @override
  String get requestsFilterAction => 'Needs action';

  @override
  String get requestsFilterDone => 'Completed';

  @override
  String get requestsStepService => 'Service';

  @override
  String get requestsStepDetails => 'Details';

  @override
  String get requestsStepPhotos => 'Photos';

  @override
  String get requestsStepLocation => 'Location';

  @override
  String get requestsStepReview => 'Review';

  @override
  String requestsStepCounter(int total, int current) {
    return 'Step $current of $total';
  }

  @override
  String get requestsServiceChoose => 'Choose a service';

  @override
  String get requestsServiceEmpty => 'No services available';

  @override
  String get requestsServiceEmptyBody =>
      'Could not load the service list. Try again.';

  @override
  String get requestsProblemOptional => 'Problem type (optional)';

  @override
  String get requestsProblemSkip => 'Skip';

  @override
  String get requestsDescTooShort => 'Write at least 10 characters';

  @override
  String get requestsDescTooLong => 'Maximum 4000 characters';

  @override
  String get requestsPhotosAdd => 'Add a photo';

  @override
  String get requestsPhotosRequired => 'At least one photo is required';

  @override
  String requestsPhotosLimit(int max) {
    return 'Maximum $max photos reached';
  }

  @override
  String get requestsPhotosHintSize => 'JPG, PNG or WebP, up to 12 MB each';

  @override
  String get requestsPhotosUploading => 'Uploading photos...';

  @override
  String requestsPhotosCount(int count, int max) {
    return '$count of $max photos';
  }

  @override
  String get requestsLocationPick => 'Choose a property';

  @override
  String get requestsLocationNoProperty =>
      'Add a property first from the Properties tab';

  @override
  String get requestsAddressGovernorate => 'Governorate';

  @override
  String get requestsAddressCity => 'City';

  @override
  String get requestsAddressZone => 'Zone';

  @override
  String get requestsAddressDistrict => 'District';

  @override
  String get requestsAddressStreet => 'Street';

  @override
  String get requestsAddressBuilding => 'Building';

  @override
  String get requestsAddressFloor => 'Floor';

  @override
  String get requestsAddressApartment => 'Apartment';

  @override
  String get requestsAddressLandmark => 'Landmark';

  @override
  String get requestsAddressNotes => 'Access notes';

  @override
  String get requestsAddressContactName => 'Contact name';

  @override
  String get requestsAddressContactPhone => 'Contact phone';

  @override
  String get requestsAddressCoordsMissing => 'Pick the location on the map';

  @override
  String get requestsReviewTitle => 'Review your request';

  @override
  String get requestsReviewEdit => 'Edit';

  @override
  String get requestsReviewMissing => 'Still needed:';

  @override
  String get requestsReviewMissingService => 'Choose a service';

  @override
  String get requestsReviewMissingLocation => 'Complete the address';

  @override
  String get requestsReviewMissingDetails => 'Describe the problem';

  @override
  String get requestsReviewMissingPhotos => 'Add at least one photo';

  @override
  String get requestsSubmitting => 'Submitting...';

  @override
  String get requestsSubmitRetry => 'Try again';

  @override
  String get requestsCreatedDraft => 'Draft created, continuing upload';

  @override
  String get requestsNoProperty => 'No property saved';

  @override
  String get requestsUrgencyNormal => 'Normal';

  @override
  String get requestsUrgencyUrgentLabel => 'Urgent';

  @override
  String get requestsInspectionOnlyHint => 'Inspection only, no repair';

  @override
  String get requestsNoteLabel => 'Additional notes';

  @override
  String get requestsReferenceCode => 'Reference';

  @override
  String requestsCountLabel(int count) {
    return '$count requests';
  }

  @override
  String get requestsAddressContactPairError =>
      'Enter a contact phone when you set a contact name';

  @override
  String get requestsNewActivity => 'New activity';

  @override
  String requestsListCount(int count) {
    return '$count total';
  }

  @override
  String commonCurrency(Object amount) {
    return '$amount EGP';
  }

  @override
  String get requestDetailProblemTitle => 'Problem description';

  @override
  String requestDetailPhotos(Object count) {
    return 'Photos ($count)';
  }

  @override
  String get requestDetailAddressTitle => 'Visit address';

  @override
  String get requestDetailTechnicianTitle => 'Technician';

  @override
  String get requestDetailNoTimeline => 'No updates yet';

  @override
  String get requestDetailAddedByYou => 'Added by you';

  @override
  String get requestDetailAddedByTeam => 'Added by the service team';

  @override
  String get quoteServiceCost => 'Service';

  @override
  String get quoteMaterialsCost => 'Materials';

  @override
  String get quoteUrgencyFee => 'Urgency fee';

  @override
  String get quoteInspectionFee => 'Inspection fee';

  @override
  String get quoteDiscount => 'Discount';

  @override
  String get quoteSubtotal => 'Subtotal';

  @override
  String get quoteTotal => 'Total';

  @override
  String get quoteDuration => 'Estimated duration';

  @override
  String quoteDurationValue(Object count) {
    return '$count minutes';
  }

  @override
  String quoteRevision(Object count) {
    return 'Quote #$count';
  }

  @override
  String quoteValidUntil(Object date) {
    return 'Valid until $date';
  }

  @override
  String get quoteNotes => 'Notes';

  @override
  String get quoteItemsTitle => 'What is included';

  @override
  String get quoteActionableEnded => 'This quote is no longer open';

  @override
  String get cancelRefundPreview => 'Refund preview';

  @override
  String get cancelRefundAmount => 'You will get back';

  @override
  String get cancelDeductionAmount => 'Deducted from the deposit';

  @override
  String get cancelNeedsApproval =>
      'This request needs staff approval before it is cancelled';

  @override
  String get cancelReasonLabel => 'Why are you cancelling? (optional)';

  @override
  String get cancelReasonHint => 'Tell us what went wrong so we can improve';

  @override
  String get requestCancelAction => 'Cancel request';

  @override
  String get requestRateAction => 'Rate service';

  @override
  String get requestComplainAction => 'Report a problem';

  @override
  String get ordersEmptyTitle => 'No orders yet';

  @override
  String get ordersEmptyBody => 'Once you book a service, it will appear here';

  @override
  String get orderComplaintOpenChip => 'Complaint';

  @override
  String get orderNoTotalYet => 'Pending pricing';

  @override
  String get orderArrivalNotScheduled => 'Arrival not scheduled yet';

  @override
  String get orderArrivalNotScheduledBody =>
      'We will show the arrival window as soon as a technician is assigned';

  @override
  String get orderWorkStarted => 'Work started';

  @override
  String get orderWorkCompleted => 'Work finished';

  @override
  String get orderServiceCompleted => 'Service completed';

  @override
  String get orderViewFullRequest => 'View request details';

  @override
  String get ordersEmptyCta => 'Book a service';
}
