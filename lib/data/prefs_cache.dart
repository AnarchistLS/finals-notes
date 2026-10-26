import 'package:shared_preferences/shared_preferences.dart';

import '../services/translation_cache.dart';

/// Кеш переводов на устройстве.
class SharedPreferencesCache implements TranslationCache {
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<String?> read(String key) async => (await _prefs).getString(key);

  @override
  Future<void> write(String key, String value) async {
    await (await _prefs).setString(key, value);
  }
}
