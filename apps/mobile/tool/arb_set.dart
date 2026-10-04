// Adds or updates ARB keys without mangling non-ASCII text.
//
// PowerShell 5.1 corrupts Arabic when it round-trips a file, so key edits go
// through Dart instead. Run from apps/mobile:
//
//   dart run tool/arb_set.dart "en:key=Value with spaces" "ar:key=نص عربي"
//
// A caller batching both locales per line may pass them space separated in one
// argument; a pair ends where the next `locale:` marker starts. The file is
// edited as text so existing formatting and key order are preserved.
import 'dart:convert';
import 'dart:io';

const Map<String, String> locales = <String, String>{
  'en': 'lib/app/localization/arb/app_en.arb',
  'ar': 'lib/app/localization/arb/app_ar.arb',
};

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'usage: dart run tool/arb_set.dart en:key=value ar:key=value',
    );
    exit(64);
  }

  final Map<String, Map<String, String>> byLocale =
      <String, Map<String, String>>{
        for (final String locale in locales.keys) locale: <String, String>{},
      };

  final RegExp marker = RegExp('(?:en|ar):[A-Za-z0-9_]+=');
  for (final String arg in args) {
    final List<RegExpMatch> starts = marker
        .allMatches(arg)
        .toList(growable: false);
    for (int i = 0; i < starts.length; i++) {
      final int end = i + 1 < starts.length ? starts[i + 1].start : arg.length;
      addPair(arg.substring(starts[i].start, end).trim(), byLocale);
    }
  }

  for (final MapEntry<String, Map<String, String>> entry in byLocale.entries) {
    if (entry.value.isEmpty) continue;
    writeKeys(locales[entry.key]!, entry.value);
    stdout.writeln('${entry.key}: ${entry.value.length} key(s) written');
  }
}

void addPair(String pairText, Map<String, Map<String, String>> byLocale) {
  final int split = pairText.indexOf(':');
  final String locale = pairText.substring(0, split);
  final String rest = pairText.substring(split + 1);
  final int eq = rest.indexOf('=');
  if (split < 0 || eq < 0 || !byLocale.containsKey(locale)) {
    stderr.writeln('bad argument "$pairText"');
    exit(64);
  }
  byLocale[locale]![rest.substring(0, eq)] = rest.substring(eq + 1);
}

/// Replaces an existing key in place, or appends the key plus its metadata
/// before the closing brace. Matching the existing indentation keeps the diff
/// to the keys that actually changed.
void writeKeys(String path, Map<String, String> updates) {
  final File file = File(path);
  final List<String> lines = file.readAsLinesSync(encoding: utf8);

  // Inserted blocks are staged so the last appended key can omit its comma;
  // JSON forbids a trailing comma before the closing brace.
  final List<String> appended = <String>[];

  updates.forEach((String key, String value) {
    final String encoded = jsonEncode(value);
    int? valueIndex;
    int? metaIndex;
    for (int i = 0; i < lines.length; i++) {
      if (valueIndex == null && lines[i].trimLeft().startsWith('"$key":')) {
        valueIndex = i;
      }
      if (metaIndex == null && lines[i].trimLeft().startsWith('"@$key":')) {
        metaIndex = i;
      }
    }

    final String indent = _indentOf(lines, valueIndex ?? metaIndex);
    final String gap = _gapOf(lines, valueIndex ?? metaIndex);

    if (valueIndex != null) {
      lines[valueIndex] = '$indent"$key":$gap$encoded,';
    } else if (metaIndex != null) {
      lines.insert(metaIndex, '$indent"$key":$gap$encoded,');
    } else {
      appended
        ..add('$indent"@$key":$gap{')
        ..add('$indent  "description":$gap"$key copy"')
        ..add('$indent},')
        ..add('$indent"$key":$gap$encoded,');
    }
  });

  if (appended.isNotEmpty) {
    final int close = _closingBraceIndex(lines);
    // The entry currently last in the file carries no comma; new entries go
    // after it, so it needs one before the insert.
    final int previous = close - 1;
    if (previous >= 0 && !lines[previous].trimRight().endsWith(',')) {
      lines[previous] = '${lines[previous]},';
    }
    final String last = appended.last;
    appended[appended.length - 1] = last.substring(0, last.length - 1);
    lines.insertAll(close, appended);
  }

  file.writeAsStringSync(lines.join('\n'), encoding: utf8, flush: true);
}

/// Index of the brace that closes the root object, skipping trailing blanks.
int _closingBraceIndex(List<String> lines) {
  for (int i = lines.length - 1; i >= 0; i--) {
    if (lines[i].trim().isEmpty) {
      lines.removeAt(i);
      continue;
    }
    if (lines[i].trim() == '}') return i;
    stderr.writeln('unexpected content after the root object: ${lines[i]}');
    exit(65);
  }
  stderr.writeln('no closing brace found');
  exit(65);
}

String _indentOf(List<String> lines, int? index) {
  if (index == null || index >= lines.length) return '  ';
  final int firstNonSpace = lines[index].indexOf(RegExp(r'[^\s]'));
  return firstNonSpace <= 0 ? '  ' : lines[index].substring(0, firstNonSpace);
}

/// Whitespace used between the colon and the value on an existing line.
///
/// These ARB files are written with two spaces there; inserting a single space
/// would leave the file valid but inconsistent, so the style is read from the
/// file rather than hard-coded.
String _gapOf(List<String> lines, int? index) {
  if (index == null || index >= lines.length) return '  ';
  final RegExpMatch? match = RegExp(r':(\s*)').firstMatch(lines[index]);
  return match?.group(1) ?? '  ';
}
