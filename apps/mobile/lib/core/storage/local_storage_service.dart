import 'package:shared_preferences/shared_preferences.dart';

import 'storage_keys.dart';

/// Thin wrapper over `SharedPreferences` for non-secret settings.
///
/// Deliberately refuses keys listed in [StorageKeys.secret]: credentials belong
/// in the keystore only (§91). The guard turns a future mistake into a loud
/// failure instead of a silent leak.
class LocalStorageService {
  LocalStorageService(this._prefs);

  final SharedPreferences _prefs;

  Future<void> setString(String key, String value) async {
    _guard(key);
    await _prefs.setString(key, value);
  }

  Future<void> setBool(String key, bool value) async {
    _guard(key);
    await _prefs.setBool(key, value);
  }

  String? getString(String key) => _prefs.getString(key);

  bool? getBool(String key) => _prefs.getBool(key);

  Future<void> remove(String key) async {
    _guard(key);
    await _prefs.remove(key);
  }

  Future<void> clear() => _prefs.clear();

  void _guard(String key) {
    assert(
      !StorageKeys.secret.contains(key),
      'Refusing to write "$key" outside the keystore.',
    );
  }
}
