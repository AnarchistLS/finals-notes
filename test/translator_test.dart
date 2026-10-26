import 'dart:convert';

import 'package:finals_notes/services/translation_cache.dart';
import 'package:finals_notes/services/translator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Отвечает на запросы Google Translate, не выходя в сеть.
class _FakeClient extends http.BaseClient {
  int calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    final queries = request.url.queryParametersAll['q'] ?? const <String>[];
    // Пакетный эндпоинт возвращает массив переводов в том же порядке.
    final payload = jsonEncode(queries.map((query) => 'RU:$query').toList());
    return http.StreamedResponse(
      Stream.value(utf8.encode(payload)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('translateAll отдаёт строки по мере готовности и без дублей', () async {
    final client = _FakeClient();
    final translator = PatchTranslator(client: client, concurrency: 4);
    final results = <String, String>{};
    var done = 0;

    await translator.translateAll(
      ['one', 'two', 'one'],
      onResult: (source, translated) => results[source] = translated,
      onProgress: (value, total) => done = value,
    );

    expect(results.length, 2);
    expect(results['one'], 'RU:one');
    expect(results['two'], 'RU:two');
    expect(done, 2);
    expect(client.calls, 1, reason: 'две строки должны уйти одним пакетом');

    translator.dispose();
  });

  test('повторный перевод берётся из кеша на устройстве', () async {
    final cache = MemoryTranslationCache();
    final first = _FakeClient();
    final translator = PatchTranslator(client: first, cache: cache);
    await translator.translate('cooldown');
    expect(first.calls, 1);
    translator.dispose();

    final second = _FakeClient();
    final cached = PatchTranslator(client: second, cache: cache);
    expect(await cached.translate('cooldown'), 'RU:cooldown');
    expect(second.calls, 0);
    cached.dispose();
  });
}
