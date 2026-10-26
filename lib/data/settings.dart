import 'package:shared_preferences/shared_preferences.dart';

import '../services/bundled_key.dart';

/// Настройки приложения.
class Settings {
  static const String _translateKey = 'translate_enabled';
  static const String _fpsKey = 'show_fps';
  static const String _backendKey = 'translate_backend';
  static const String _deeplKeyKey = 'deepl_api_key';
  static const String _deeplEndpointKey = 'deepl_endpoint';

  /// Ключ DeepL, вшитый в сборку.
  ///
  /// Личная сборка для одного устройства, поэтому ключ лежит в коде — менять
  /// его в настройках не обязательно. Если сборка когда-нибудь пойдёт в люди,
  /// ключ нужно убрать отсюда и унести на сервер: из APK его достанут.
  static const String bundledDeepLKey = defaultDeepLKey;

  static Future<bool> translateEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_translateKey) ?? true;
  }

  static Future<void> setTranslateEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_translateKey, value);
  }

  static Future<bool> showFps() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_fpsKey) ?? false;
  }

  static Future<void> setShowFps(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_fpsKey, value);
  }

  /// Движок перевода: `deepl` или `google`.
  static Future<String> translationBackend() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_backendKey) ?? (bundledDeepLKey.isEmpty ? 'google' : 'deepl');
  }

  static Future<void> setTranslationBackend(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_backendKey, value);
  }

  static Future<String> deepLKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_deeplKeyKey) ?? bundledDeepLKey;
  }

  static Future<void> setDeepLKey(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deeplKeyKey, value.trim());
  }

  /// Прокси перед DeepL (пусто — официальный сервер).
  static Future<String> deepLEndpoint() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_deeplEndpointKey) ?? '';
  }

  static Future<void> setDeepLEndpoint(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deeplEndpointKey, value.trim());
  }
}
