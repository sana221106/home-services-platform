import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/secure_storage_service.dart';

/// Non-persistent settings such as the chosen theme mode and locale.
///
/// This provider intentionally throws: the real instance is supplied in
/// `main()` after `SharedPreferences.getInstance()` resolves. Forcing every
/// consumer to receive an already-loaded instance means no feature can read
/// preferences before they are ready.
final Provider<SharedPreferences> sharedPreferencesProvider =
    Provider<SharedPreferences>(
      (Ref ref) => throw UnimplementedError(
        'sharedPreferencesProvider must be overridden in main() with the '
        'instance returned by SharedPreferences.getInstance().',
      ),
      name: 'sharedPreferences',
    );

/// Keystore-backed token storage.
///
/// Tests override this with `InMemoryTokenStore` so no widget test needs the
/// platform channel.
final Provider<TokenStore> tokenStoreProvider = Provider<TokenStore>(
  (Ref ref) => SecureTokenStore(),
  name: 'tokenStore',
);

/// The single HTTP client, built once and shared by every repository.
final Provider<ApiClient> apiClientProvider = Provider<ApiClient>(
  (Ref ref) => ApiClient(tokenStore: ref.watch(tokenStoreProvider)),
  name: 'apiClient',
);
