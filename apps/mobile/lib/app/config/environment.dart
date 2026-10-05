/// Build-time environment selection.
enum Environment {
  development('development', 'Development'),
  staging('staging', 'Staging'),
  production('production', 'Production');

  const Environment(this.value, this.label);

  /// Value used by the `--dart-define=ENVIRONMENT=` flag.
  final String value;

  final String label;

  static Environment fromDartDefine(String? raw) {
    if (raw == null || raw.isEmpty) return Environment.production;
    for (final environment in Environment.values) {
      if (environment.value == raw) return environment;
    }
    return Environment.production;
  }
}
