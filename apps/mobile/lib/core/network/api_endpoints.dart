/// Backend endpoint paths, transcribed from the generated OpenAPI document.
///
/// Customer-facing routes only (§9: the customer never sees technician identity
/// or staff endpoints). Staff paths are intentionally absent from this app.
abstract final class ApiEndpoints {
  static const String prefix = '/api/v1';

  // ------------------------------------------------------------------ auth
  static const String authRequestOtp = '$prefix/auth/request-otp';
  static const String authVerifyOtp = '$prefix/auth/verify-otp';
  static const String authGoogle = '$prefix/auth/google';
  static const String authRefresh = '$prefix/auth/refresh';
  static const String authLogout = '$prefix/auth/logout';
  static const String authMe = '$prefix/auth/me';

  // ------------------------------------------------------------------ home
  static const String home = '$prefix/home';

  // -------------------------------------------------------------- catalogue
  static const String catalogue = '$prefix/catalogue';
  static const String services = '$prefix/services';
  static String serviceProblems(String serviceId) =>
      '$prefix/services/$serviceId/problems';
  static String problemDetail(String problemId) =>
      '$prefix/problems/$problemId';

  // ------------------------------------------------- coverage and geocoding
  /// Areas currently served. The address form picks from these so coverage is
  /// decided by the server rather than by how the customer spelled a city.
  static const String coverageZones = '$prefix/coverage-zones';

  /// Address search, so a typed Arabic address resolves to a point.
  static const String addressSearch = '$prefix/address-search';

  // -------------------------------------------------------------- requests
  static const String requests = '$prefix/requests';
  static const String activeRequests = '$prefix/requests/active';
  static String request(String id) => '$prefix/requests/$id';
  static String requestSubmit(String id) => '$prefix/requests/$id/submit';
  static String requestCancel(String id) => '$prefix/requests/$id/cancel';
  static String requestCancellationPreview(String id) =>
      '$prefix/requests/$id/cancellation-preview';
  static String requestTimeline(String id) => '$prefix/requests/$id/timeline';
  static String requestDeposit(String id) => '$prefix/requests/$id/deposit';
  static String requestQuote(String id) => '$prefix/requests/$id/quote';
  static String requestQuoteAccept(String id) =>
      '$prefix/requests/$id/quote/accept';
  static String requestQuoteReject(String id) =>
      '$prefix/requests/$id/quote/reject';
  static String requestPayments(String id) => '$prefix/requests/$id/payments';
  static String requestRefunds(String id) => '$prefix/requests/$id/refunds';
  static String requestPayment(String id) => '$prefix/requests/$id/payment';

  // ---------------------------------------------------------------- media
  static String requestMediaUpload(String requestId) =>
      '$prefix/requests/$requestId/media';
  static String requestMediaItem(String requestId, String mediaId) =>
      '$prefix/requests/$requestId/media/$mediaId';
  static String requestMediaAnnotations(String requestId, String mediaId) =>
      '$prefix/requests/$requestId/media/$mediaId/annotations';
  static String paymentProof(String requestId, String paymentId) =>
      '$prefix/requests/$requestId/payments/$paymentId/proof';

  /// Content streams are served with an Authorization header, so they are
  /// fetched by the API client rather than by an <img> tag.
  static String mediaContent(String mediaId) =>
      '$prefix/media/$mediaId/content';

  // ---------------------------------------------------------------- orders
  static const String orders = '$prefix/orders';
  static String order(String requestId) => '$prefix/orders/$requestId';

  // -------------------------------------------------------------- payments
  static const String paymentMethods = '$prefix/payment-methods';

  // ------------------------------------------------------------ properties
  static const String properties = '$prefix/properties';
  static String property(String id) => '$prefix/properties/$id';
  static String propertyContacts(String id) =>
      '$prefix/properties/$id/contacts';
  static String propertyHistory(String id) => '$prefix/properties/$id/history';

  // --------------------------------------------------------------- support
  static const String support = '$prefix/support';
  static const String conversations = '$prefix/conversations';
  static String conversationMessages(String id) =>
      '$prefix/conversations/$id/messages';
  static String conversationRead(String id) => '$prefix/conversations/$id/read';
  static const String complaints = '$prefix/complaints';
  static const String complaintReasons = '$prefix/complaints/reasons';
  static String complaint(String id) => '$prefix/complaints/$id';
  static String complaintAttachments(String id) =>
      '$prefix/complaints/$id/attachments';

  // ---------------------------------------------------------- notifications
  static const String notifications = '$prefix/notifications';
  static const String notificationsUnreadCount =
      '$prefix/notifications/unread-count';
  static const String notificationsRead = '$prefix/notifications/read';

  // --------------------------------------------------------------- profile
  static const String profile = '$prefix/profile';
  static const String devices = '$prefix/devices';
  static const String analyticsEvents = '$prefix/analytics/events';
  static const String reviews = '$prefix/reviews';
}
