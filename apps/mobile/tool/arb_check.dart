// Verifies that an ARB pair is valid JSON and that Arabic values are intact.
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  const Map<String, String> files = <String, String>{
    'en': 'lib/app/localization/arb/app_en.arb',
    'ar': 'lib/app/localization/arb/app_ar.arb',
  };

  for (final MapEntry<String, String> entry in files.entries) {
    final Map<String, dynamic> map =
        jsonDecode(File(entry.value).readAsStringSync(encoding: utf8))
            as Map<String, dynamic>;
    final int plain = map.keys.where((String k) => !k.startsWith('@')).length;
    stdout.writeln('${entry.key}: $plain keys, json valid');
    if (args.isEmpty) continue;
    for (final String key in args) {
      final Object? value = map[key];
      if (value is! String || value.isEmpty) {
        stdout.writeln('  MISSING OR EMPTY: $key');
        continue;
      }
      if (entry.key == 'ar') {
        // Arabic letters live in U+0600..U+06FF, plus the presentation forms in
        // U+FE70..U+FEFF. Anything outside those blocks means the value was
        // corrupted in transit, not merely untranslated.
        final List<int> bad = value.runes
            .where(
              (int r) =>
                  r != 0x20 &&
                  !(r >= 0x0600 && r <= 0x06FF) &&
                  !(r >= 0xFE70 && r <= 0xFEFF),
            )
            .toList();
        if (bad.isNotEmpty) {
          stdout.writeln('  NON-ARABIC CODEPOINTS in $key: $bad');
        }
      }
      stdout.writeln('  $key = $value');
    }
  }
}
