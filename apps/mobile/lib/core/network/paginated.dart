import 'package:equatable/equatable.dart';

/// Backend pagination envelope: `{items, meta}`.
class Paginated<T> extends Equatable {
  const Paginated({required this.items, required this.meta});

  factory Paginated.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final rawItems = json['items'] as List<dynamic>? ?? const <dynamic>[];
    return Paginated<T>(
      items: rawItems
          .cast<Map<String, dynamic>>()
          .map(fromJson)
          .toList(growable: false),
      meta: PageMeta.fromJson(
        json['meta'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
    );
  }

  final List<T> items;
  final PageMeta meta;

  bool get isEmpty => items.isEmpty;
  bool get hasNext => meta.hasNext;

  @override
  List<Object?> get props => <Object?>[items, meta];
}

class PageMeta extends Equatable {
  const PageMeta({
    required this.page,
    required this.perPage,
    required this.total,
    required this.totalPages,
    required this.hasNext,
    required this.hasPrevious,
  });

  factory PageMeta.fromJson(Map<String, dynamic> json) {
    return PageMeta(
      page: _asInt(json['page']) ?? 1,
      perPage: _asInt(json['per_page']) ?? 20,
      total: _asInt(json['total']) ?? 0,
      totalPages: _asInt(json['total_pages']) ?? 0,
      hasNext: json['has_next'] as bool? ?? false,
      hasPrevious: json['has_previous'] as bool? ?? false,
    );
  }

  final int page;
  final int perPage;
  final int total;
  final int totalPages;
  final bool hasNext;
  final bool hasPrevious;

  @override
  List<Object?> get props => <Object?>[
    page,
    perPage,
    total,
    totalPages,
    hasNext,
    hasPrevious,
  ];
}

int? _asInt(Object? value) => switch (value) {
  final int v => v,
  final num v => v.toInt(),
  final String v => int.tryParse(v),
  _ => null,
};
