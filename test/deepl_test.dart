import 'dart:convert';

import 'package:finals_notes/services/deepl.dart';
import 'package:finals_notes/services/translator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Заглушка DeepL: отвечает как настоящий API, но без сети.
class _FakeDeepL extends http.BaseClient {
  _FakeDeepL({this.status = 200, this.count = 0, this.limit = 1000000});

  final int status;
  final int count;
  final int limit;
  final List<http.Request> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request as http.Request);

    if (status != 200) {
      // 451 приходит HTML-страницей, остальные коды — JSON.
      final body = status == 451
          ? '<html><body>Unavailable in your region</body></html>'
          : jsonEncode({'message': 'error', 'code': 'test'});
      return http.StreamedResponse(Stream.value(utf8.encode(body)), status);
    }

    if (request.url.path.endsWith('/usage')) {
      return _json({'character_count': count, 'character_limit': limit});
    }

    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final texts = (body['text'] as List).cast<String>();
    return _json({
      'translations': [
        for (final text in texts) {'detected_source_language': 'EN', 'text': 'DE:$text'},
      ],
    });
  }

  http.StreamedResponse _json(Map<String, dynamic> data) => http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(data))),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
}

/// Заглушка Google Translate — запасной движок.
class _FakeGoogle extends http.BaseClient {
  int calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    final queries = request.url.queryParametersAll['q'] ?? const <String>[];
    final payload = jsonEncode(queries.map((query) => 'RU:$query').toList());
    return http.StreamedResponse(
      Stream.value(utf8.encode(payload)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

String? _header(http.Request request, String name) {
  for (final entry in request.headers.entries) {
    if (entry.key.toLowerCase() == name) return entry.value;
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DeepLStatus.reset();
  });

  test('запрос уходит на бесплатный хост с ключом, контекстом и порядком строк', () async {
    final fake = _FakeDeepL();
    final client = DeepLClient(apiKey: 'abc:fx', client: fake);

    final result = await client.translate(['one', 'two'], context: 'Patch 5.4.0');

    expect(result, ['DE:one', 'DE:two']);
    final request = fake.requests.single;
    expect(request.method, 'POST');
    expect(request.url.host, 'api-free.deepl.com');
    expect(request.url.path, '/v2/translate');
    expect(_header(request, 'authorization'), 'DeepL-Auth-Key abc:fx');

    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body['text'], ['one', 'two']);
    expect(body['source_lang'], 'EN');
    expect(body['target_lang'], 'RU');
    expect(body['preserve_formatting'], isTrue);
    expect(body['context'], 'Patch 5.4.0');
  });

  test('платный ключ идёт на api.deepl.com, прокси подменяет адрес', () async {
    final paid = _FakeDeepL();
    await DeepLClient(apiKey: 'paid-key', client: paid).translate(['x']);
    expect(paid.requests.single.url.host, 'api.deepl.com');

    final proxy = _FakeDeepL();
    await DeepLClient(
      apiKey: 'abc:fx',
      endpoint: 'https://proxy.example.com/',
      client: proxy,
    ).translate(['x']);
    expect(proxy.requests.single.url.toString(), 'https://proxy.example.com/v2/translate');
  });

  test('/usage отдаёт расход и остаток', () async {
    final usage = await DeepLClient(
      apiKey: 'abc:fx',
      client: _FakeDeepL(count: 1234, limit: 1000000),
    ).usage();

    expect(usage.count, 1234);
    expect(usage.limit, 1000000);
    expect(usage.left, 998766);
  });

  test('451 в регионе — молча уходим на Google и больше DeepL не дёргаем', () async {
    final google = _FakeGoogle();
    final deepl = _FakeDeepL(status: 451);
    final translator = PatchTranslator(
      client: google,
      deeplClient: deepl,
      backend: TranslationBackend.deepl,
      deeplKey: 'abc:fx',
    );

    final result = await translator.translateAll(['one', 'two']);

    expect(result['one'], 'RU:one');
    expect(result['two'], 'RU:two');
    expect(DeepLStatus.blocked, isTrue);
    expect(deepl.requests, hasLength(1), reason: 'после 451 повторных попыток быть не должно');

    await translator.translateAll(['three']);
    expect(deepl.requests, hasLength(1), reason: 'DeepL отключён до перезапуска');
    translator.dispose();
  });

  test('исчерпанная квота (456) тоже переключает на Google', () async {
    final google = _FakeGoogle();
    final deepl = _FakeDeepL(status: 456);
    final translator = PatchTranslator(
      client: google,
      deeplClient: deepl,
      backend: TranslationBackend.deepl,
      deeplKey: 'abc:fx',
    );

    final result = await translator.translateAll(['one', 'two']);

    expect(result['one'], 'RU:one');
    expect(DeepLStatus.blocked, isTrue);
    translator.dispose();
  });

  test('кеш раздельный: гугловый перевод не подставляется вместо DeepL', () async {
    final first = PatchTranslator(client: _FakeGoogle());
    expect(await first.translate('cooldown'), 'RU:cooldown');
    first.dispose();

    final translator = PatchTranslator(
      client: _FakeGoogle(),
      deeplClient: _FakeDeepL(),
      backend: TranslationBackend.deepl,
      deeplKey: 'abc:fx',
    );

    expect(await translator.translate('cooldown'), 'DE:cooldown');
    translator.dispose();
  });

  test('без ключа DeepL не используется', () async {
    final deepl = _FakeDeepL();
    final translator = PatchTranslator(
      client: _FakeGoogle(),
      deeplClient: deepl,
      backend: TranslationBackend.deepl,
      deeplKey: '',
    );

    expect(await translator.translate('cooldown'), 'RU:cooldown');
    expect(deepl.requests, isEmpty);
    translator.dispose();
  });
}
