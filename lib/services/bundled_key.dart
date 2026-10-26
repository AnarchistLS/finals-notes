/// Ключ DeepL, вшитый в сборку.
///
/// Значение приходит только при сборке: `--dart-define=DEEPL_KEY=...`.
/// В репозитории ключа нет, и в веб-сборке он тоже не появляется - Mini App
/// ничего не переводит, а ключ в опубликованном `main.dart.js` смог бы
/// достать кто угодно.
///
/// Если ключа нет, приложение просто работает через Google: см.
/// `Settings.translationBackend()`.
library;

const String defaultDeepLKey = String.fromEnvironment('DEEPL_KEY');
