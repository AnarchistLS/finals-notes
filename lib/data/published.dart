/// Готовые данные для Mini App.
///
/// Файл `data/patches_ru.json` собирает `tool/publish.dart` в CI: он тянет
/// патчноуты с сайта и переводит их один раз. Приложению остаётся только
/// прочитать JSON - без ключей, прокси и перевода на телефоне.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';

/// Патч вместе с картой «оригинал -> перевод» для его строк.
class PublishedPatch {
  const PublishedPatch({required this.doc, required this.translations});

  final PatchDoc doc;

  /// Переводы блоков и названий характеристик, ключ - исходный текст.
  final Map<String, String> translations;
}

/// Снимок файла: когда собран и каким движком переведён.
class PublishedSnapshot {
  const PublishedSnapshot({
    required this.generatedAt,
    required this.engine,
    required this.patches,
  });

  final DateTime generatedAt;
  final String engine;
  final List<PublishedPatch> patches;
}

class PublishedRepository {
  PublishedRepository({http.Client? client, this.url = publishedDataUrl})
      : _client = client ?? http.Client();

  /// Путь относительно сайта; переопределяется `--dart-define=PUBLISHED_DATA_URL=...`.
  static const String publishedDataUrl = String.fromEnvironment(
    'PUBLISHED_DATA_URL',
    defaultValue: 'data/patches_ru.json',
  );

  final http.Client _client;
  final String url;

  /// Читает снимок. Возвращает `null`, если файла нет или он битый -
  /// тогда вызывающий код работает как раньше, напрямую с сайтом.
  Future<PublishedSnapshot?> load({bool fresh = false}) async {
    try {
      var uri = Uri.base.resolve(url);
      if (fresh) {
        uri = uri.replace(queryParameters: {
          ...uri.queryParameters,
          'v': '${DateTime.now().millisecondsSinceEpoch}',
        });
      }

      final response = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) return null;
      final items = decoded['items'];
      if (items is! List) return null;

      final patches = <PublishedPatch>[];
      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        final doc = item['doc'];
        if (doc is! Map<String, dynamic>) continue;
        final rawTranslations = item['translations'];
        patches.add(PublishedPatch(
          doc: PatchDoc.fromJson(doc),
          translations: rawTranslations is Map
              ? {
                  for (final entry in rawTranslations.entries)
                    '${entry.key}': '${entry.value}',
                }
              : const {},
        ));
      }
      if (patches.isEmpty) return null;

      final generatedAt = DateTime.tryParse('${decoded['generatedAt'] ?? ''}');

      return PublishedSnapshot(
        generatedAt: (generatedAt ?? DateTime.now()).toLocal(),
        engine: '${decoded['engine'] ?? ''}',
        patches: patches,
      );
    } catch (_) {
      return null;
    }
  }

  void dispose() => _client.close();
}
