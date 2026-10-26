/// Кеш переводов в JSON-файле, общий для бота и пайплайна Mini App.
///
/// Повторный запуск не тратит квоту DeepL: файл лежит в `tool/` и
/// коммитится в репозиторий, поэтому кеш переживает перезапуски CI.
library;

import 'dart:convert';
import 'dart:io';

import 'package:finals_notes/services/translation_cache.dart';

class FileTranslationCache implements TranslationCache {
  FileTranslationCache(this.file, {void Function(String message)? log})
      : _log = log ?? ((_) {});

  final File file;
  final void Function(String message) _log;

  final Map<String, String> _values = {};
  bool _loaded = false;
  bool _dirty = false;

  int get length => _values.length;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    if (!file.existsSync()) return;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        decoded.forEach((key, value) {
          if (key is String && value is String) _values[key] = value;
        });
      }
      _log('кеш переводов: ${_values.length} строк');
    } catch (error) {
      _log('кеш переводов повреждён, начинаю заново: $error');
    }
  }

  Future<void> save() async {
    if (!_dirty) return;
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(_values));
    _dirty = false;
  }

  @override
  Future<String?> read(String key) async {
    await load();
    return _values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    await load();
    _values[key] = value;
    _dirty = true;
  }
}
