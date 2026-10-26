/// Перевод текста патчноутов на русский.
///
/// Названия предметов, карт, классов и специализаций перед переводом
/// заменяются маркерами, а после — возвращаются на место, чтобы переводчик
/// не превращал «Grappling Hook» в «крюк-кошку».
///
/// Крупный патчноут содержит сотни строк, поэтому строки переводятся
/// пакетами: до [PatchTranslator._batchChars] символов и
/// [PatchTranslator._maxBatchItems] строк за один запрос.
/// Это в разы меньше обращений к сервису и не упирается в лимит запросов.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../l10n/glossary.dart';
import 'deepl.dart';
import 'translation_cache.dart';

/// Каким сервисом переводим.
enum TranslationBackend {
  deepl,
  google;

  static TranslationBackend fromName(String? name) =>
      name == 'deepl' ? TranslationBackend.deepl : TranslationBackend.google;
}

class PatchTranslator {
  PatchTranslator({
    http.Client? client,
    http.Client? deeplClient,
    TranslationCache? cache,
    this.concurrency = 3,
    this.backend = TranslationBackend.google,
    this.deeplKey = '',
    this.deeplEndpoint = '',
    this.context,
  })  : _client = client ?? http.Client(),
        _deeplHttp = deeplClient,
        cache = cache ?? MemoryTranslationCache();

  final http.Client _client;

  /// Где хранить переводы между запусками.
  final TranslationCache cache;

  /// Отдельный клиент для DeepL — в тестах сюда подставляется заглушка.
  final http.Client? _deeplHttp;

  /// Сколько пакетов переводим одновременно.
  final int concurrency;

  /// Основной движок. Если DeepL недоступен — молча уходим на Google.
  final TranslationBackend backend;

  final String deeplKey;

  /// Необязательный прокси перед DeepL.
  final String deeplEndpoint;

  /// Контекст для DeepL: название патча. На перевод влияет, но не тарифицируется.
  final String? context;

  DeepLClient? _deepl;

  static const String _prefix = 'tr_ru_';

  /// Сколько символов отправляем в Google за один запрос.
  static const int _googleChunk = 1500;

  /// Бюджет одного пакетного запроса (URL не должен разрастаться).
  static const int _batchChars = 3000;

  /// Лимит MyMemory на один запрос.
  static const int _myMemoryChunk = 450;

  /// Сколько строк кладём в один пакет.
  static const int _maxBatchItems = 40;

  final Map<String, String> _memory = {};
  final Map<String, Future<String>> _pending = {};

  String _key(String text) =>
      '$_prefix${backend == TranslationBackend.deepl ? 'deepl_' : ''}${_hash(text)}';

  /// Клиент DeepL создаём только когда он реально нужен.
  DeepLClient? get _deepLClient {
    if (backend != TranslationBackend.deepl) return null;
    if (deeplKey.trim().isEmpty) return null;
    return _deepl ??= DeepLClient(
      apiKey: deeplKey,
      endpoint: deeplEndpoint,
      client: _deeplHttp,
    );
  }

  Future<String> translate(String input) {
    final text = input.trim();
    if (text.isEmpty) return Future.value(input);

    final cached = _memory[text];
    if (cached != null) return Future.value(cached);

    // Одинаковые строки не должны уходить в сеть дважды.
    return _pending[text] ??= _translate(text).whenComplete(() {
      _pending.remove(text);
    });
  }

  Future<String> _translate(String text) async {
    final key = _key(text);
    final stored = await cache.read(key);
    if (stored != null && stored.isNotEmpty) {
      _memory[text] = stored;
      return stored;
    }

    final terms = detectProperNames(text);
    final protectedText = protectTerms(text, terms);

    var translated = await _deepLText(protectedText);
    translated ??= await _google(protectedText);
    translated ??= await _myMemory(protectedText);
    if (translated == null) return text;

    final restored = restoreTerms(translated, terms).trim();
    if (restored.isEmpty) return text;

    _memory[text] = restored;
    await cache.write(key, restored);
    return restored;
  }

  /// Переводит набор строк, сохраняя порядок и не дублируя запросы.
  ///
  /// [onResult] вызывается сразу после перевода каждой строки — благодаря
  /// этому крупный патч наполняется русским текстом постепенно, а не целиком
  /// в конце.
  Future<Map<String, String>> translateAll(
    Iterable<String> texts, {
    void Function(int done, int total)? onProgress,
    void Function(String source, String translated)? onResult,
  }) async {
    final unique = texts
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    final result = <String, String>{};
    if (unique.isEmpty) return result;

    final pending = <String>[];

    for (final text in unique) {
      final stored = _memory[text] ?? (await cache.read(_key(text)));
      if (stored != null && stored.isNotEmpty) {
        _memory[text] = stored;
        result[text] = stored;
        onResult?.call(text, stored);
      } else {
        pending.add(text);
      }
    }
    if (result.isNotEmpty) onProgress?.call(result.length, unique.length);

    final batches = _makeBatches(pending);
    var done = result.length;
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= batches.length) return;

        final batch = batches[index];
        final translated = await _translateBatch(batch);

        for (final text in batch) {
          final value = translated[text] ?? text;
          result[text] = value;
          // Неудачный перевод (остался оригинал) не кешируем: при следующем
          // открытии попробуем перевести снова.
          if (value != text) _memory[text] = value;
          done++;
          onResult?.call(text, value);
          onProgress?.call(done, unique.length);
        }

        for (final text in batch) {
          final value = result[text] ?? text;
          if (value != text) await cache.write(_key(text), value);
        }
      }
    }

    final workers = math.min(concurrency, batches.length);
    await Future.wait(List.generate(workers, (_) => worker()));
    return result;
  }

  /// Переводит пакет строк одним запросом к Google.
  Future<Map<String, String>> _translateBatch(List<String> batch) async {
    if (batch.length == 1) {
      return {batch.single: await translate(batch.single)};
    }

    final deepL = await _deepLBatch(batch);
    if (deepL != null) return deepL;

    final google = await _googleBatch(batch);
    if (google != null && google.length == batch.length) {
      return _zip(batch, google);
    }

    // Google не ответил — переводим небольшими группами через MyMemory.
    final result = <String, String>{};
    for (final group in _makeBatchesWithLimit(batch, _myMemoryChunk)) {
      if (group.length == 1) {
        result[group.single] = await _myMemory(group.single) ?? group.single;
        continue;
      }

      final groupJoined = _join(group);
      final myMemory = await _myMemoryRaw(groupJoined);
      final parts = myMemory == null
          ? null
          : _splitMarked(myMemory, group.length);
      if (parts != null) {
        result.addAll(_zip(group, parts));
      } else {
        for (final text in group) {
          result[text] = await _myMemory(text) ?? text;
        }
      }
    }
    return result;
  }

  Map<String, String> _zip(List<String> batch, List<String> parts) {
    return {
      for (var i = 0; i < batch.length; i++) batch[i]: parts[i],
    };
  }

  String _join(List<String> batch) {
    final buffer = StringBuffer();
    for (var i = 0; i < batch.length; i++) {
      if (i > 0) buffer.write('\n[[[$i]]]\n');
      buffer.write(batch[i]);
    }
    return buffer.toString();
  }

  List<String>? _splitMarked(String translated, int count) {
    final parts = translated
        .split(RegExp(r'\[\[\[\s*\d+\s*\]\]\]'))
        .map((part) => part.trim())
        .toList();
    if (parts.length != count) return null;
    if (parts.any((part) => part.isEmpty)) return null;
    return parts;
  }

  List<List<String>> _makeBatches(List<String> texts) {
    return _makeBatchesWithLimit(texts, _batchChars, maxItems: _maxBatchItems);
  }

  List<List<String>> _makeBatchesWithLimit(
    List<String> texts,
    int limit, {
    int maxItems = _maxBatchItems,
  }) {
    final batches = <List<String>>[];
    var current = <String>[];
    var size = 0;

    for (final text in texts) {
      if (current.isNotEmpty &&
          (size + text.length > limit || current.length >= maxItems)) {
        batches.add(current);
        current = <String>[];
        size = 0;
      }
      current.add(text);
      size += text.length + 16;
    }
    if (current.isNotEmpty) batches.add(current);
    return batches;
  }

  /// Один запрос к DeepL на весь пакет строк.
  Future<Map<String, String>?> _deepLBatch(List<String> batch) async {
    final client = _deepLClient;
    if (client == null || DeepLStatus.blocked) return null;

    try {
      final parts = await client.translate(batch, context: context);
      DeepLStatus.used = true;
      return _zip(batch, parts);
    } catch (_) {
      // Любая осечка DeepL (регион 451, квота 456, сеть) — до конца запуска
      // идём в Google, чтобы не ждать таймаут на каждой странице патча.
      // Кнопка «Проверить ключ» в настройках сбрасывает флаг.
      DeepLStatus.blocked = true;
      return null;
    }
  }

  /// Перевод одной строки через DeepL (имена собственные уже под маркерами).
  Future<String?> _deepLText(String text) async {
    final client = _deepLClient;
    if (client == null || DeepLStatus.blocked) return null;

    try {
      final parts = await client.translate([text], context: context);
      if (parts.isEmpty) return null;
      final value = parts.first.trim();
      if (value.isEmpty) return null;
      DeepLStatus.used = true;
      return value;
    } catch (_) {
      DeepLStatus.blocked = true;
      return null;
    }
  }

  /// Переводит длинный текст, деля его по границам предложений.
  Future<String?> _google(String text) async {
    final chunks = _split(text, _googleChunk);
    final buffer = StringBuffer();

    for (final chunk in chunks) {
      final translated = await _googleRaw(chunk);
      if (translated == null) return null;
      buffer.write('$translated ');
    }

    final result = buffer.toString().trim();
    return result.isEmpty ? null : result;
  }

  Future<String?> _googleRaw(String text) async {
    final batch = await _googleBatch([text]);
    if (batch == null || batch.isEmpty) return null;
    final result = batch.first.trim();
    return result.isEmpty ? null : result;
  }

  /// Один запрос переводит сразу несколько строк: сервис принимает
  /// повторяющийся параметр `q` и возвращает массив переводов в том же порядке.
  Future<List<String>?> _googleBatch(List<String> texts) async {
    if (texts.isEmpty) return null;

    final uri = Uri.https('clients5.google.com', '/translate_a/t', {
      'client': 'dict-chrome-ex',
      'sl': 'en',
      'tl': 'ru',
      'q': texts,
    });

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response =
            await _client.get(uri).timeout(const Duration(seconds: 15));
        if (response.statusCode == 429 || response.statusCode >= 500) {
          await Future<void>.delayed(Duration(milliseconds: 600 * (attempt + 1)));
          continue;
        }
        if (response.statusCode != 200) return null;

        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is! List) return null;

        final result = <String>[];
        for (final item in data) {
          if (item is String) {
            result.add(item);
          } else if (item is List && item.isNotEmpty && item.first is String) {
            result.add(item.first as String);
          } else {
            return null;
          }
        }

        if (result.length != texts.length) return null;
        if (result.any((value) => value.trim().isEmpty)) return null;
        return result;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<String?> _myMemory(String text) async {
    final chunks = _split(text, _myMemoryChunk);
    final buffer = StringBuffer();

    for (final chunk in chunks) {
      final translated = await _myMemoryRaw(chunk);
      if (translated == null) return null;
      buffer.write('$translated ');
    }

    final result = buffer.toString().trim();
    return result.isEmpty ? null : result;
  }

  Future<String?> _myMemoryRaw(String text) async {
    final uri = Uri.https('api.mymemory.translated.net', '/get', {
      'q': text,
      'langpair': 'en|ru',
    });
    try {
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final responseData = data is Map ? data['responseData'] : null;
      final translated = responseData is Map ? responseData['translatedText'] : null;
      if (translated is! String || translated.isEmpty) return null;
      return translated.trim();
    } catch (_) {
      return null;
    }
  }

  /// Делит длинный текст на куски по границам предложений.
  List<String> _split(String text, int limit) {
    if (text.length <= limit) return [text];
    final chunks = <String>[];
    final buffer = StringBuffer();

    final normalized = text.replaceAllMapped(
      RegExp(r'([.!?])\s+'),
      (match) => '${match.group(1)}\n',
    );
    for (final sentence in normalized.split('\n')) {
      if (buffer.length + sentence.length + 1 > limit && buffer.isNotEmpty) {
        chunks.add(buffer.toString().trim());
        buffer.clear();
      }
      buffer.write('$sentence ');
    }
    if (buffer.isNotEmpty) chunks.add(buffer.toString().trim());
    return chunks.isEmpty ? [text] : chunks;
  }

  /// Устойчивый 32-битный хеш (работает и в браузере, и на телефоне).
  String _hash(String value) {
    var hash = 2166136261;
    for (final code in value.codeUnits) {
      hash = ((hash * 31) + code) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  void dispose() {
    _deepl?.dispose();
    _client.close();
  }
}
