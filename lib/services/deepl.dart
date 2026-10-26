/// Клиент DeepL API.
///
/// Что важно знать про этот API и почему сделано именно так:
/// * бесплатный ключ заканчивается на `:fx` и работает на `api-free.deepl.com`,
///   платный — на `api.deepl.com`;
/// * в одном запросе можно отправить до 128 КиБ текста, ответ приходит
///   в том же порядке, что и массив `text`;
/// * параметр `context` (название патча) влияет на перевод и не тарифицируется;
/// * коды ошибок: 451 — сервис недоступен в регионе, 456 — кончилась квота,
///   403 — неверный ключ, 429/5xx — имеет смысл повторить.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

class DeepLException implements Exception {
  const DeepLException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  bool get regionBlocked => statusCode == 451;
  bool get quotaExceeded => statusCode == 456;
  bool get authFailed => statusCode == 401 || statusCode == 403;

  @override
  String toString() => 'DeepL $statusCode: $message';
}

class DeepLUsage {
  const DeepLUsage({required this.count, required this.limit});

  final int count;
  final int limit;

  int get left => (limit - count).clamp(0, limit);
}

/// Помнит, что DeepL недоступен в этом запуске: иначе каждая страница патча
/// тратила бы запрос на 451, прежде чем уйти на Google.
class DeepLStatus {
  static bool blocked = false;

  /// Хотя бы одна строка реально ушла в DeepL и вернулась переводом.
  static bool used = false;

  static void reset() {
    blocked = false;
    used = false;
  }
}

class DeepLClient {
  DeepLClient({required this.apiKey, this.endpoint = '', http.Client? client})
      : _client = client ?? http.Client();

  final String apiKey;

  /// Необязательный прокси, совместимый с DeepL API (например, Cloudflare
  /// Worker). Пустая строка — официальный сервер DeepL.
  final String endpoint;

  final http.Client _client;

  bool get isFreeKey => apiKey.trim().endsWith(':fx');

  Uri _uri(String path) {
    final base = endpoint.trim();
    if (base.isEmpty) {
      final host = isFreeKey ? 'api-free.deepl.com' : 'api.deepl.com';
      return Uri.https(host, path);
    }
    final normalized = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return Uri.parse('$normalized$path');
  }

  Map<String, String> get _headers => {
        'Authorization': 'DeepL-Auth-Key ${apiKey.trim()}',
        'Content-Type': 'application/json; charset=utf-8',
      };

  /// Переводит строки одним запросом. Порядок ответа совпадает с порядком входа.
  Future<List<String>> translate(List<String> texts, {String? context}) async {
    if (texts.isEmpty) return const [];

    final body = <String, dynamic>{
      'text': texts,
      'source_lang': 'EN',
      'target_lang': 'RU',
      'preserve_formatting': true,
      if (context != null && context.trim().isNotEmpty) 'context': context.trim(),
    };

    final data = await _withRetry(
      () async => _decode(
        await _client
            .post(_uri('/v2/translate'), headers: _headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 25)),
      ),
    );

    final translations = data['translations'];
    if (translations is! List || translations.length != texts.length) {
      throw const DeepLException(500, 'неожиданный ответ /translate');
    }

    final result = <String>[];
    for (final item in translations) {
      final text = item is Map ? item['text'] : null;
      if (text is! String || text.trim().isEmpty) {
        throw const DeepLException(500, 'пустой перевод в ответе');
      }
      result.add(text);
    }
    return result;
  }

  /// Сколько символов израсходовано в текущем периоде.
  Future<DeepLUsage> usage() async {
    final data = await _withRetry(
      () async => _decode(
        await _client
            .get(_uri('/v2/usage'), headers: _headers)
            .timeout(const Duration(seconds: 20)),
      ),
    );

    final count = data['character_count'];
    final limit = data['character_limit'];
    if (count is! int || limit is! int) {
      throw const DeepLException(500, 'неожиданный ответ /usage');
    }
    return DeepLUsage(count: count, limit: limit);
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is Map<String, dynamic>) return data;
      throw const DeepLException(500, 'ответ не является JSON-объектом');
    }
    throw DeepLException(response.statusCode, _errorMessage(response));
  }

  String _errorMessage(http.Response response) {
    try {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is Map && data['message'] is String) return data['message'] as String;
    } catch (_) {
      // 451 приходит HTML-страницей «Unavailable in your region».
    }
    return 'HTTP ${response.statusCode}';
  }

  Future<Map<String, dynamic>> _withRetry(
    Future<Map<String, dynamic>> Function() call,
  ) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await call();
      } on DeepLException catch (error) {
        final retryable = error.statusCode == 429 || error.statusCode >= 500;
        if (!retryable || attempt >= 2) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
  }

  void dispose() => _client.close();
}
