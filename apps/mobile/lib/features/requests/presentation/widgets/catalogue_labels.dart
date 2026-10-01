import '../../data/models/request_models.dart';

/// Catalogue names are admin-editable content served by the backend, so only
/// the language choice belongs to the app. These helpers keep that decision in
/// one place instead of duplicating it on every catalogue-driven screen.
String localisedCategoryName(ServiceCategory category, String language) =>
    language.startsWith('ar') ? category.nameAr : category.nameEn;

String localisedProblemName(ProblemType problem, String language) =>
    language.startsWith('ar') ? problem.nameAr : problem.nameEn;

/// A one-line version of a snapshot address for lists and review rows.
///
/// Ordered broadest first, and only the parts that were actually filled in are
/// joined, so an address that is just governorate and city does not render a
/// trail of separators. Long addresses are truncated to the three most
/// identifying parts because the row is usually two lines tall at most.
String addressSummary(AddressSnapshot address) {
  final List<String> parts = <String?>[
    address.governorate,
    address.city,
    address.district,
    address.zone,
    address.street,
    address.building,
  ].whereType<String>().where((String part) => part.trim().isNotEmpty).toList();

  if (parts.isEmpty) return '';
  if (parts.length <= 3) return parts.join('، ');
  return '${parts.take(3).join('، ')}، +${parts.length - 3}';
}
