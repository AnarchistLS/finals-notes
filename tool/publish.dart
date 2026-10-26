/// Пайплайн Mini App: собирает патчи, переводит их и кладёт готовый JSON
/// в `web/data/patches_ru.json`.
///
/// Mini App не переводит ничего на телефоне: он просто читает этот файл.
/// Поэтому приложению не нужны ни ключи, ни CORS-прокси, ни VPN, а канал и
/// приложение показывают один и тот же текст.
///
/// Запуск из корня проекта:
///
///   dart run tool/publish.dart                 # 1 страница, 12 патчей
///   dart run tool/publish.dart --pages=2 --limit=20
///   dart run tool/publish.dart --dry-run       # только показать, что выйдет
///
/// Настройки берутся из `tool/bot.env` (TRANSLATE_BACKEND, DEEPL_KEY,
/// DEEPL_ENDPOINT) или из переменных окружения. Кеш переводов общий с ботом:
/// `tool/.translation-cache.json`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:finals_notes/parser/patch_parser.dart';
import 'package:finals_notes/services/bundled_key.dart';
import 'package:finals_notes/services/deepl.dart';
import 'package:finals_notes/services/doc_translator.dart';
import 'package:finals_notes/services/translator.dart';
import 'package:http/http.dart' as http;

import 'env.dart';
import 'file_cache.dart';

Future<void> main(List<String> arguments) async {
  stdout.encoding = utf8;

  final options = _Options.parse(arguments);
  if (options.help) {
    _printHelp();
    return;
  }

  final root = findProjectRoot();
  final toolDir = Directory('${root.path}${Platform.pathSeparator}tool');
  final env = readEnv(toolDir, const [
    'TRANSLATE_BACKEND',
    'DEEPL_KEY',
    'DEEPL_ENDPOINT',
  ]);

  final backend = env['TRANSLATE_BACKEND']?.toLowerCase() == 'google'
      ? TranslationBackend.google
      : TranslationBackend.deepl;
  final deeplKey = env['DEEPL_KEY'] ?? defaultDeepLKey;
  final deeplEndpoint = env['DEEPL_ENDPOINT'] ?? '';

  final client = http.Client();
  final cache = FileTranslationCache(
    File('${toolDir.path}${Platform.pathSeparator}.translation-cache.json'),
    log: _log,
  );

  DeepLStatus.reset();

  try {
    await cache.load();

    _log('читаю ${options.pages} стр. списка патчей');
    final patches = await fetchPatches(
      client: client,
      pages: options.pages,
      limit: options.limit,
    );
    if (patches.isEmpty) {
      _log('сайт не вернул ни одного патча — файл не трогаю');
      exitCode = 1;
      return;
    }
    _log('патчей: ${patches.length} (свежий: ${patches.first.title})');

    final items = <Map<String, dynamic>>[];
    var translatedChars = 0;

    for (var i = 0; i < patches.length; i++) {
      final patch = patches[i];
      final translator = PatchTranslator(
        cache: cache,
        backend: backend,
        deeplKey: deeplKey,
        deeplEndpoint: deeplEndpoint,
        context: patch.title,
      );

      Map<String, String> translations;
      try {
        translations = await translateDoc(patch, translator);
      } finally {
        translator.dispose();
      }

      translatedChars += translations.values.fold<int>(0, (sum, value) => sum + value.length);
      items.add({
        'doc': patch.toJson(),
        'translations': translations,
      });

      _log(
        '${i + 1}/${patches.length}: ${patch.version} · '
        'строк ${translations.length} · секций ${patch.sections.length}',
      );
    }

    final file = options.output(root);

    // Если патчи и переводы не изменились, оставляем старую дату сборки:
    // иначе файл менялся бы каждый час, а каждый коммит запускает деплой
    // и жжёт минуты GitHub Actions.
    var generatedAt = DateTime.now().toUtc().toIso8601String();
    var engine = _engineName(backend);
    final previous = _readPrevious(file);
    if (previous != null &&
        jsonEncode(previous['items']) == jsonEncode(items)) {
      generatedAt = '${previous['generatedAt'] ?? generatedAt}';
      engine = '${previous['engine'] ?? engine}';
      _log('данные не изменились — файл останется прежним');
    }

    final payload = {
      'generatedAt': generatedAt,
      'engine': engine,
      'count': items.length,
      'items': items,
    };
    final json = jsonEncode(payload);

    _log('движок: $engine, символов перевода: $translatedChars');
    _log('размер файла: ${(json.length / 1024).toStringAsFixed(1)} КБ');

    if (options.dryRun) {
      _log('--dry-run: ${file.path} не записан');
      return;
    }

    await file.parent.create(recursive: true);
    await file.writeAsString(json);
    _log('готово: ${file.path}');
  } finally {
    await cache.save();
    client.close();
  }
}

/// Читает прошлый результат, чтобы понять, изменились ли данные.
///
/// Битый или отсутствующий файл - не ошибка: просто соберём заново.
Map<String, dynamic>? _readPrevious(File file) {
  if (!file.existsSync()) return null;
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

String _engineName(TranslationBackend backend) => switch (backend) {      TranslationBackend.google => 'Google',
      TranslationBackend.deepl when DeepLStatus.blocked => 'Google (DeepL недоступен)',
      TranslationBackend.deepl when DeepLStatus.used => 'DeepL',
      TranslationBackend.deepl => 'DeepL (кеш)',
    };

class _Options {
  _Options({
    required this.pages,
    required this.limit,
    required this.outputPath,
    required this.dryRun,
    required this.help,
  });

  final int pages;
  final int limit;
  final String outputPath;
  final bool dryRun;
  final bool help;

  File output(Directory root) => File(
        outputPath.startsWith(RegExp(r'[A-Za-z]:[\\/]')) ||
                outputPath.startsWith('/')
            ? outputPath
            : '${root.path}${Platform.pathSeparator}$outputPath',
      );

  static _Options parse(List<String> args) {
    var pages = 1;
    var limit = 12;
    var output = 'web/data/patches_ru.json';
    var dryRun = false;
    var help = false;

    for (final arg in args) {
      if (arg == '--dry-run') {
        dryRun = true;
      } else if (arg == '--help' || arg == '-h') {
        help = true;
      } else if (arg.startsWith('--pages=')) {
        pages = int.tryParse(arg.substring('--pages='.length)) ?? pages;
      } else if (arg.startsWith('--limit=')) {
        limit = int.tryParse(arg.substring('--limit='.length)) ?? limit;
      } else if (arg.startsWith('--out=')) {
        output = arg.substring('--out='.length);
      } else {
        stderr.writeln('Неизвестный параметр: $arg');
        help = true;
      }
    }

    return _Options(
      pages: pages < 1 ? 1 : pages,
      limit: limit < 1 ? 1 : limit,
      outputPath: output,
      dryRun: dryRun,
      help: help,
    );
  }
}

void _log(String message) {
  final now = DateTime.now();
  final time = [
    now.hour.toString().padLeft(2, '0'),
    now.minute.toString().padLeft(2, '0'),
    now.second.toString().padLeft(2, '0'),
  ].join(':');
  stdout.writeln('[$time] $message');
}

void _printHelp() {
  stdout.writeln('''
Пайплайн данных для Mini App THE FINALS.

  dart run tool/publish.dart [параметры]

Параметры:
  --pages=1          сколько страниц списка читать (по умолчанию 1)
  --limit=12         максимум патчей в файле (по умолчанию 12)
  --out=web/data/patches_ru.json
                     куда писать результат
  --dry-run          ничего не записывать, только показать статистику
  -h, --help         эта справка

Настройки: tool/bot.env (TRANSLATE_BACKEND=deepl|google, DEEPL_KEY,
DEEPL_ENDPOINT). Переменные окружения важнее файла.
''');
}
