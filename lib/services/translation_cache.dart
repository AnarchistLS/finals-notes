/// Хранилище переводов.
///
/// Движок перевода не должен знать, где лежит кеш: в приложении это
/// SharedPreferences, в консольном боте — файл рядом с ним. Благодаря
/// интерфейсу `translator.dart` остаётся чистым Dart и его можно запускать
/// без Flutter (`dart run tool/bot.dart`).
library;

abstract class TranslationCache {
  Future<String?> read(String key);

  Future<void> write(String key, String value);
}

/// Кеш в памяти: тесты и разовые запуски.
class MemoryTranslationCache implements TranslationCache {
  final Map<String, String> _values = {};

  int get length => _values.length;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}
