/// Бот-постер для Telegram-канала: следит за патчноутами THE FINALS,
/// переводит их и публикует в канал.
///
/// Запуск из корня проекта:
///
///   dart run tool/bot.dart --dry-run          # показать пост, никуда не отправляя
///   dart run tool/bot.dart --once             # проверить и опубликовать новый патч
///   dart run tool/bot.dart --watch            # проверять каждые 10 минут
///   dart run tool/bot.dart --full --dry-run   # весь текст, а не анонс
///   dart run tool/bot.dart --digest --dry-run # полный список изменений текстом
///
/// Настройки берутся из `tool/bot.env` (см. `tool/bot.env.example`) или из
/// переменных окружения. Без токена бот работает в режиме `--dry-run`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:finals_notes/models/models.dart';
import 'package:finals_notes/parser/patch_parser.dart';
import 'package:finals_notes/services/bundled_key.dart';
import 'package:finals_notes/services/deepl.dart';
import 'package:finals_notes/services/doc_translator.dart';
import 'package:finals_notes/services/translator.dart';
import 'package:finals_notes/telegram/clip.dart';
import 'package:finals_notes/telegram/render.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

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
  final config = _Config.load(toolDir, options);

  if (!config.dryRun && (config.token.isEmpty || config.channel.isEmpty)) {
    stderr.writeln(
      'Нет токена или канала. Скопируйте tool/bot.env.example в tool/bot.env '
      'и заполните TELEGRAM_BOT_TOKEN и TELEGRAM_CHANNEL.\n'
      'Либо запустите с --dry-run — бот покажет пост, но не отправит его.',
    );
    exitCode = 2;
    return;
  }

  final client = http.Client();
  final cache = FileTranslationCache(
    File('${toolDir.path}${Platform.pathSeparator}.translation-cache.json'),
    log: _log,
  );
  final state = await _BotState.load(
    File('${toolDir.path}${Platform.pathSeparator}.bot-state.json'),
  );

  try {
    await cache.load();
    do {
      try {
        await _runOnce(
          client: client,
          config: config,
          cache: cache,
          state: state,
          stateFile: File('${toolDir.path}${Platform.pathSeparator}.bot-state.json'),
        );
      } catch (error) {
        _log('ошибка: $error');
        if (!config.watch) {
          exitCode = 1;
          break;
        }
      }
      if (!config.watch) break;
      _log('следующая проверка через ${config.intervalSeconds} с');
      await Future<void>.delayed(Duration(seconds: config.intervalSeconds));
    } while (true);
  } finally {
    await cache.save();
    client.close();
  }
}

Future<void> _runOnce({
  required http.Client client,
  required _Config config,
  required FileTranslationCache cache,
  required _BotState state,
  required File stateFile,
}) async {
  _log('читаю $defaultApiBase/patchnotes');
  final patches = await fetchPatches(client: client, pages: config.pages);
  if (patches.isEmpty) {
    _log('сайт не вернул ни одного патча');
    return;
  }

  if (config.list) {
    for (final patch in patches) {
      stdout.writeln(
        '${patch.dateText}  ${patch.version.padRight(8)}  '
        '${patch.id}  ${patch.title}',
      );
    }
    return;
  }

  final patch = config.patchId == null
      ? patches.first
      : patches.firstWhere(
          (item) => item.id == config.patchId || item.slug.endsWith(config.patchId!),
          orElse: () => throw StateError('патч «${config.patchId}» не найден в первой странице'),
        );

  if (config.init) {
    state.lastPatchId = patch.id;
    state.lastPostedAt = DateTime.now().toIso8601String();
    await state.save(stateFile);
    _log('запомнил текущий патч без публикации: ${patch.title}');
    return;
  }

  if (!config.force && !config.dryRun && state.lastPatchId == patch.id) {
    _log('новых патчей нет. Последний опубликованный: ${patch.title}');
    return;
  }

  _log('патч: ${patch.title} (${patch.version}, ${patch.dateText})');
  _log(
    'секций: ${patch.sections.length}, изменений: ${patch.stats.length}, '
    'режим: ${config.full ? 'полный текст' : config.digest ? 'дайджест' : 'анонс'}',
  );

  DeepLStatus.reset();
  final translator = PatchTranslator(
    cache: cache,
    backend: config.backend,
    deeplKey: config.deeplKey,
    deeplEndpoint: config.deeplEndpoint,
    context: patch.title,
  );

  final texts = collectDocTexts(patch, full: config.full);
  _log('строк на перевод: ${texts.length}');

  var lastReport = DateTime.now();
  Map<String, String> translations;
  try {
    translations = await translateDoc(
      patch,
      translator,
      full: config.full,
      onProgress: (done, total) {
        final now = DateTime.now();
        if (now.difference(lastReport).inSeconds < 3 && done != total) return;
        lastReport = now;
        _log('переведено $done из $total');
      },
    );
  } finally {
    translator.dispose();
  }

  final engine = switch (config.backend) {
    TranslationBackend.google => 'Google',
    TranslationBackend.deepl when DeepLStatus.blocked => 'Google (DeepL недоступен)',
    TranslationBackend.deepl when DeepLStatus.used => 'DeepL',
    TranslationBackend.deepl => 'не требовался',
  };
  _log('движок: $engine');

  var messages = config.full
      ? renderFull(patch, translations: translations)
      : config.digest
          ? renderDigest(patch, translations: translations)
          : renderTeaser(
              patch,
              translations: translations,
              appUrl: config.miniAppUrl,
            );

  _log('сообщений: ${messages.length}');

  // «Гифка»: зацикленный mp4 из видео-блока патча. Ошибка сборки не
  // отменяет публикацию — пост всё равно уходит, просто без ролика.
  File? clip;
  final playlistUrl = _firstPlaylistUrl(patch);
  if (playlistUrl != null) {
    if (config.videoEnabled) {
      _log('ищу гифку: $playlistUrl');
      try {
        final temp = await Directory.systemTemp.createTemp('finals_clip_');
        clip = await buildClip(
          client: client,
          playlistUrl: playlistUrl,
          outputDir: temp,
        );
        final sizeMb = (clip.lengthSync() / (1024 * 1024)).toStringAsFixed(1);
        _log('гифка готова: ${clip.path} ($sizeMb МБ)');
      } catch (error) {
        _log('гифка не собралась, публикую без неё: $error');
        clip = null;
      }
    } else {
      _log('гифка отключена (BOT_VIDEO=0), публикую без неё');
    }
  } else if (config.videoEnabled) {
    _log('видео-блоков в патче нет — пост без гифки');
  }

  if (config.dryRun) {
    if (clip != null) {
      stdout.writeln(
        '\n===== гифка =====\n${clip.path} '
        '(${(clip.lengthSync() / (1024 * 1024)).toStringAsFixed(1)} МБ)\n'
        'в dry-run не отправляется — удалить вручную при необходимости',
      );
    }
    for (var i = 0; i < messages.length; i++) {
      stdout.writeln(
        '\n===== сообщение ${i + 1}/${messages.length} · '
        '${messages[i].length} симв. =====\n${messages[i]}',
      );
    }
    if (clip != null) {
      try {
        clip.deleteSync();
      } catch (_) {}
    }
    return;
  }

  // Анимация уходит ТРЕТЬИМ «сообщением» до текста: она первее привлекает
  // внимание; подпись не ставим почти никогда — текст давно уложен в пост.
  if (clip != null) {
    final renderableMessages = [...messages];
    String? caption = renderableMessages.firstOrNull;
    // Подпись к анимации ограничена 1024 символами; HTML-разметку
    // считать нельзя, поэтому сверяемся по «сырому» тексту (без тегов).
    final plain = _stripTags(caption ?? '');
    if (plain.length > 1024) caption = null;
    try {
      await _sendAnimation(
        client: client,
        token: config.token,
        channel: config.channel,
        file: clip,
        caption: caption,
        replyMarkup: renderableMessages.length <= 1
            ? miniAppKeyboard(config.miniAppUrl)
            : null,
      );
      _log('гифка отправлена');
      renderableMessages.removeAt(0);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      messages = renderableMessages;
    } catch (error) {
      _log('гифка не ушла в Telegram, публикую текст как обычно: $error');
    } finally {
      try {
        clip.deleteSync();
      } catch (_) {}
    }
  }

  for (var i = 0; i < messages.length; i++) {
    final isLast = i + 1 == messages.length;
    await _sendMessage(
      client: client,
      token: config.token,
      channel: config.channel,
      text: messages[i],
      // Кнопку вешаем только на последнее сообщение длинного поста.
      replyMarkup: isLast ? miniAppKeyboard(config.miniAppUrl) : null,
    );
    _log('отправлено ${i + 1}/${messages.length}');
    if (i + 1 < messages.length) {
      // Telegram любит ~1 сообщение в секунду на чат.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    }
  }

  state.lastPatchId = patch.id;
  state.lastPostedAt = DateTime.now().toIso8601String();
  await state.save(stateFile);
  _log('готово: ${patch.title}');
}

/// Первый видео-блок патча: HLS-плейлист для сборки «гифки».
String? _firstPlaylistUrl(PatchDoc patch) {
  for (final section in patch.sections) {
    for (final block in section.blocks) {
      if (block.isVideo) return block.url;
    }
  }
  return null;
}

/// Без тегов Telegram-разметки: для проверки лимита подписи (1024 символа)
/// Telegram считает «голый» текст, а не исходный HTML.
String _stripTags(String html) =>
    html.replaceAll(RegExp(r'<[^>]+>'), '');

/// Отправляет зацикленную «гифку» (mp4 без звука) в канал.
///
/// `animation` в Telegram — это mp4 без звука: клиенты гоняют его по кругу
/// без кнопки громкости и не показывают как видео. Наш патч-ролик — ровно
/// такой формат: CDN-видео сайта делается `loop+muted` сам по себе.
Future<void> _sendAnimation({
  required http.Client client,
  required String token,
  required String channel,
  required File file,
  String? caption,
  Map<String, dynamic>? replyMarkup,
  Map<String, dynamic>? replyParameters,
}) async {
  final uri = Uri.parse('https://api.telegram.org/bot$token/sendAnimation');

  for (var attempt = 0; attempt < 3; attempt++) {
    final request = http.MultipartRequest('POST', uri)
      ..fields.addAll({
        'chat_id': channel,
        if (caption != null && caption.isNotEmpty) 'caption': caption,
        if (caption != null && caption.isNotEmpty) 'parse_mode': 'HTML',
        if (replyMarkup != null) 'reply_markup': jsonEncode(replyMarkup),
      })
      ..files.add(await http.MultipartFile.fromPath(
        'animation',
        file.path,
        contentType: MediaType('video', 'mp4'),
      ));

    final response = await http.Response.fromStream(
      await client
          .send(request)
          .timeout(const Duration(seconds: 120)),
    );

    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {
      // Telegram может вернуть HTML-страницу прокси при сбое.
    }

    if (data?['ok'] == true) return;

    final code = data?['error_code'];
    if (code == 429) {
      final parameters = data?['parameters'];
      final retry = parameters is Map && parameters['retry_after'] is num
          ? (parameters['retry_after'] as num?)?.toInt()
          : null;
      final seconds = retry ?? 5;
      _log('Telegram просит подождать $seconds с');
      await Future<void>.delayed(Duration(seconds: seconds));
      continue;
    }

    final description = data?['description'] ?? 'HTTP ${response.statusCode}';
    throw StateError('Telegram sendAnimation: $description');
  }

  throw StateError(
      'Telegram: не удалось отправить гифку после 3 попыток');
}

Future<void> _sendMessage({  required http.Client client,
  required String token,
  required String channel,
  required String text,
  Map<String, dynamic>? replyMarkup,
}) async {
  final uri = Uri.parse('https://api.telegram.org/bot$token/sendMessage');
  final body = jsonEncode({
    'chat_id': channel,
    'text': text,
    'parse_mode': 'HTML',
    'link_preview_options': {'is_disabled': true},
    if (replyMarkup != null) 'reply_markup': replyMarkup,
  });

  for (var attempt = 0; attempt < 3; attempt++) {
    final response = await client
        .post(
          uri,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: body,
        )
        .timeout(const Duration(seconds: 30));

    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {
      // Telegram иногда отвечает HTML при ошибке на уровне прокси.
    }

    if (data?['ok'] == true) return;

    final code = data?['error_code'];
    if (code == 429) {
      final parameters = data?['parameters'];
      final retry = parameters is Map ? (parameters['retry_after'] as num?) : null;
      final seconds = retry?.toInt() ?? 5;
      _log('Telegram просит подождать $seconds с');
      await Future<void>.delayed(Duration(seconds: seconds));
      continue;
    }

    final description = data?['description'] ?? 'HTTP ${response.statusCode}';
    throw StateError('Telegram ответил: $description');
  }

  throw StateError('Telegram: не удалось отправить сообщение после 3 попыток');
}

class _BotState {
  _BotState({this.lastPatchId, this.lastPostedAt});

  String? lastPatchId;
  String? lastPostedAt;

  static Future<_BotState> load(File file) async {
    if (!file.existsSync()) return _BotState();
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) {
        return _BotState(
          lastPatchId: decoded['lastPatchId'] as String?,
          lastPostedAt: decoded['lastPostedAt'] as String?,
        );
      }
    } catch (_) {
      // Битая история не повод падать: просто опубликуем свежий патч.
    }
    return _BotState();
  }

  Future<void> save(File file) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode({
      'lastPatchId': lastPatchId,
      'lastPostedAt': lastPostedAt,
    }));
  }
}

class _Options {
  _Options({
    this.dryRun = false,
    this.full = false,
    this.digest = false,
    this.force = false,
    this.watch = false,
    this.list = false,
    this.help = false,
    this.init = false,
    this.pages = 1,
    this.intervalSeconds,
    this.patchId,
  });

  final bool dryRun;
  final bool full;
  final bool digest;
  final bool force;
  final bool watch;
  final bool list;
  final bool help;
  final bool init;
  final int pages;
  final int? intervalSeconds;
  final String? patchId;

  static _Options parse(List<String> args) {
    var dryRun = false;
    var full = false;
    var digest = false;
    var force = false;
    var watch = false;
    var list = false;
    var help = false;
    var init = false;
    var pages = 1;
    int? interval;
    String? patchId;

    for (final arg in args) {
      if (arg == '--dry-run') {
        dryRun = true;
      } else if (arg == '--full') {
        full = true;
      } else if (arg == '--digest') {
        digest = true;
      } else if (arg == '--force') {
        force = true;
      } else if (arg == '--watch') {
        watch = true;
      } else if (arg == '--once') {
        watch = false;
      } else if (arg == '--list') {
        list = true;
      } else if (arg == '--init') {
        init = true;
      } else if (arg == '--help' || arg == '-h') {
        help = true;
      } else if (arg.startsWith('--pages=')) {
        pages = int.tryParse(arg.substring('--pages='.length)) ?? 1;
      } else if (arg.startsWith('--interval=')) {
        interval = int.tryParse(arg.substring('--interval='.length));
      } else if (arg.startsWith('--patch=')) {
        patchId = arg.substring('--patch='.length);
      } else {
        stderr.writeln('Неизвестный параметр: $arg');
        help = true;
      }
    }

    return _Options(
      dryRun: dryRun,
      full: full,
      digest: digest,
      force: force,
      watch: watch,
      list: list,
      help: help,
      init: init,
      pages: pages < 1 ? 1 : pages,
      intervalSeconds: interval,
      patchId: patchId,
    );
  }
}

class _Config {
  _Config({
    required this.token,
    required this.channel,
    required this.backend,
    required this.deeplKey,
    required this.deeplEndpoint,
    required this.miniAppUrl,
    required this.videoEnabled,
    required this.dryRun,
    required this.full,
    required this.digest,
    required this.force,
    required this.watch,
    required this.list,
    required this.init,
    required this.pages,
    required this.intervalSeconds,
    required this.patchId,
  });

  final String token;
  final String channel;
  final TranslationBackend backend;
  final String deeplKey;
  final String deeplEndpoint;
  final String miniAppUrl;

  /// Публиковать зацикленные видео-«гифки» из патча (BOT_VIDEO).
  final bool videoEnabled;

  final bool dryRun;
  final bool full;
  final bool digest;
  final bool force;
  final bool watch;
  final bool list;
  final bool init;
  final int pages;
  final int intervalSeconds;
  final String? patchId;

  static _Config load(Directory toolDir, _Options options) {
    final values = readEnv(toolDir, const [
      'TELEGRAM_BOT_TOKEN',
      'TELEGRAM_CHANNEL',
      'TRANSLATE_BACKEND',
      'DEEPL_KEY',
      'DEEPL_ENDPOINT',
      'MINIAPP_URL',
      'BOT_INTERVAL',
      'BOT_PAGES',
      'BOT_VIDEO',
    ]);

    final backendName = values['TRANSLATE_BACKEND']?.toLowerCase();
    final backend = backendName == 'google'
        ? TranslationBackend.google
        : TranslationBackend.deepl;
    final key = values['DEEPL_KEY'] ?? defaultDeepLKey;

    final interval = options.intervalSeconds ??
        int.tryParse(values['BOT_INTERVAL'] ?? '') ??
        600;
    final pages = options.pages > 1
        ? options.pages
        : (int.tryParse(values['BOT_PAGES'] ?? '') ?? options.pages);
    final videoRaw = (values['BOT_VIDEO'] ?? '').toLowerCase();
    final videoEnabled = videoRaw != '0' && videoRaw != 'false' && videoRaw != 'off';

    return _Config(
      token: values['TELEGRAM_BOT_TOKEN'] ?? '',
      channel: values['TELEGRAM_CHANNEL'] ?? '',
      backend: backend,
      deeplKey: key,
      deeplEndpoint: values['DEEPL_ENDPOINT'] ?? '',
      miniAppUrl: values['MINIAPP_URL'] ?? '',
      videoEnabled: videoEnabled,
      dryRun: options.dryRun,
      full: options.full,
      digest: options.digest,
      force: options.force,
      watch: options.watch,
      list: options.list,
      init: options.init,
      pages: pages < 1 ? 1 : pages,
      intervalSeconds: interval < 30 ? 30 : interval,
      patchId: options.patchId,
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
Бот-постер патчноутов THE FINALS в Telegram.

  dart run tool/bot.dart [параметры]

Параметры:
  --dry-run          показать готовые сообщения, ничего не отправляя
  --once             проверить сайт и опубликовать новый патч (по умолчанию)
  --watch            проверять сайт по кругу
  --interval=600     пауза между проверками в секундах (по умолчанию 600)
  --full             публиковать весь переведённый текст, а не анонс
  --digest           полный список изменений текстом (старый формат)
  --force            опубликовать патч, даже если он уже был опубликован
  --init             запомнить текущий патч и ничего не публиковать
  --patch=ID         взять конкретный патч по id или хвосту слага
  --pages=2          сколько страниц списка читать (по умолчанию 1)
  --list             показать найденные патчи и выйти
  -h, --help         эта справка

Настройки: tool/bot.env (TELEGRAM_BOT_TOKEN, TELEGRAM_CHANNEL,
TRANSLATE_BACKEND=deepl|google, DEEPL_KEY, DEEPL_ENDPOINT, MINIAPP_URL).
Переменные окружения важнее файла.

MINIAPP_URL — прямая ссылка на Mini App вида https://t.me/<бот>/<app>:
если задана, под последним сообщением появится кнопка «Открыть приложение».
''');
}
