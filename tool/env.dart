/// Общие мелочи для консольных инструментов: поиск корня проекта и чтение
/// настроек из `tool/bot.env` с приоритетом переменных окружения.
library;

import 'dart:io';

/// Корень проекта - папка с `pubspec.yaml` (поднимаемся не выше 6 уровней).
Directory findProjectRoot() {
  var directory = Directory.current;
  for (var depth = 0; depth < 6; depth++) {
    if (File('${directory.path}${Platform.pathSeparator}pubspec.yaml').existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  return Directory.current;
}

/// Читает `tool/bot.env`, затем перекрывает значениями из окружения.
///
/// Переменные окружения важнее файла: так настройки задаются в CI, а локально
/// достаточно `bot.env`. Пустые значения игнорируются.
Map<String, String> readEnv(Directory toolDir, List<String> keys) {
  final values = <String, String>{};

  final envFile = File('${toolDir.path}${Platform.pathSeparator}bot.env');
  if (envFile.existsSync()) {
    for (final line in envFile.readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final eq = trimmed.indexOf('=');
      if (eq <= 0) continue;
      final key = trimmed.substring(0, eq).trim();
      var value = trimmed.substring(eq + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      values[key] = value;
    }
  }

  for (final key in keys) {
    final value = Platform.environment[key];
    if (value != null && value.trim().isNotEmpty) values[key] = value.trim();
  }

  return values;
}
