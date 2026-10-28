/// Превращает HTML-тело статьи Squarespace в структурированный патч.
library;

import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'stat_parser.dart';

const String defaultApiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'https://www.reachthefinals.com',
);

/// Загружает страницу списка патчноутов с сайта.
///
/// Squarespace отдаёт машиночитаемый JSON по адресу `?format=json`,
/// поэтому парсить HTML списка не нужно. Постраничная навигация — по
/// параметру `offset`, равному времени публикации самого старого элемента.
Future<List<Map<String, dynamic>>> fetchItemsPage({
  required http.Client client,
  required String apiBase,
  int? offset,
}) async {
  final uri = Uri.parse(
    '$apiBase/patchnotes?format=json${offset == null ? '' : '&offset=$offset'}',
  );
  final response = await _getWithRetry(client, uri);

  if (response.statusCode != 200) {
    throw HttpException(
      'Сайт ответил ${response.statusCode}. Проверьте подключение или локальный прокси.',
    );
  }

  final decoded = jsonDecode(utf8.decode(response.bodyBytes));
  if (decoded is! Map<String, dynamic>) {
    throw const HttpException('Неожиданный ответ сайта: ожидался JSON.');
  }
  final items = decoded['items'];
  if (items is! List) return const [];
  return items.cast<Map<String, dynamic>>();
}

/// Запрос с повторами: сайт изредка отвечает 5xx или не укладывается в
/// таймаут, и из-за одного такого сбоя пропадал целый запуск.
Future<http.Response> _getWithRetry(
  http.Client client,
  Uri uri, {
  int attempts = 3,
}) async {
  Object? lastError;
  for (var attempt = 1; attempt <= attempts; attempt++) {
    try {
      final response = await client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 25));
      if (response.statusCode < 500 && response.statusCode != 429) {
        return response;
      }
      lastError = HttpException('Сайт ответил ${response.statusCode}.');
    } on Exception catch (error) {
      lastError = error;
    }
    if (attempt < attempts) {
      await Future<void>.delayed(Duration(seconds: attempt * 3));
    }
  }
  throw lastError is Exception
      ? lastError
      : const HttpException('Не удалось получить ответ сайта.');
}

/// Загружает несколько страниц списка и разбирает их в [PatchDoc].
///
/// Общая точка для приложения, бота и пайплайна Mini App: Squarespace отдаёт
/// постранично, следующая страница запрашивается по `offset` самого старого
/// элемента предыдущей.
Future<List<PatchDoc>> fetchPatches({
  required http.Client client,
  String apiBase = defaultApiBase,
  int pages = 1,
  int limit = 60,
}) async {
  final patches = <PatchDoc>[];
  int? offset;

  for (var page = 0; page < pages; page++) {
    final items = await fetchItemsPage(
      client: client,
      apiBase: apiBase,
      offset: offset,
    );
    if (items.isEmpty) break;

    for (final item in items) {
      patches.add(parsePatchItem(item, apiBase: apiBase));
    }

    final timestamps = items
        .map((item) => (item['publishOn'] ?? 0) as num)
        .where((value) => value > 0)
        .toList();
    if (timestamps.isEmpty) break;
    offset = timestamps.reduce((a, b) => a < b ? a : b).toInt();

    if (patches.length >= limit) break;
  }

  patches.sort((a, b) => b.date.compareTo(a.date));
  return patches.length > limit ? patches.sublist(0, limit) : patches;
}

class HttpException implements Exception {
  const HttpException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Собирает [PatchDoc] из элемента JSON-коллекции.
PatchDoc parsePatchItem(Map<String, dynamic> item, {String apiBase = defaultApiBase}) {
  final slug = (item['fullUrl'] ?? item['urlId'] ?? '') as String;
  final title = decodeEntities((item['title'] ?? '') as String);
  final rawBody = (item['body'] ?? '') as String;
  final publishOn = (item['publishOn'] ?? 0) as num;

  final fragment = html_parser.parseFragment(rawBody);
  _stripNoise(fragment);

  final images = <String>[];
  final sections = <PatchSection>[];
  final stats = <StatChange>[];

  var sectionTitle = '';
  var sectionBlocks = <DocBlock>[];
  var category = '';
  var currentItem = '';

  void flushSection() {
    if (sectionBlocks.isEmpty && sectionTitle.isEmpty) return;
    sections.add(PatchSection(
      title: sectionTitle.isEmpty ? 'Обновление' : sectionTitle,
      blocks: List<DocBlock>.unmodifiable(sectionBlocks),
    ));
  }

  final nodes = fragment.querySelectorAll('h1, h2, h3, h4, p, li, img');
  for (final element in nodes) {
    final tag = element.localName ?? '';

    if (tag == 'img') {
      final src = _imageUrl(element);
      if (src != null) {
        images.add(src);
        if (sectionBlocks.isNotEmpty) {
          sectionBlocks.add(DocBlock(kind: 'img', url: src));
        }
      }
      continue;
    }

    // Параграф внутри пункта списка дублирует текст — пропускаем.
    if (tag == 'p' && element.parent?.localName == 'li') continue;

    final text = _ownText(element);
    if (text.isEmpty) continue;

    switch (tag) {
      case 'h1':
      case 'h2':
        flushSection();
        sectionTitle = text;
        sectionBlocks = [];
        category = '';
        break;
      case 'h3':
      case 'h4':
        category = text;
        sectionBlocks.add(DocBlock(kind: 'h3', text: text));
        break;
      case 'p':
        if (_isBoldOnly(element) && text.length <= 60) {
          currentItem = text;
          sectionBlocks.add(DocBlock(kind: 'b', text: text));
          continue;
        }
        sectionBlocks.add(DocBlock(kind: 'p', text: text));
        _collectStats(
          stats,
          text,
          category: category.isEmpty ? sectionTitle : category,
          item: currentItem,
        );
        break;
      case 'li':
        sectionBlocks.add(DocBlock(kind: 'li', text: text));
        _collectStats(
          stats,
          text,
          category: category.isEmpty ? sectionTitle : category,
          item: currentItem,
        );
        break;
      default:
        break;
    }
  }
  flushSection();

  final dedupImages = <String>[];
  for (final url in images) {
    if (!dedupImages.contains(url)) dedupImages.add(url);
  }

  final cover = _absolute((item['assetUrl'] as String?) ?? '', apiBase) ??
      (dedupImages.isNotEmpty ? dedupImages.first : null);

  final bodyText = _normalize(fragment.text ?? '');

  return PatchDoc(
    id: (item['id'] ?? slug) as String,
    slug: slug,
    title: title.isEmpty ? 'Патчноут' : title,
    version: detectVersion(title: title, slug: slug, bodyText: bodyText),
    date: DateTime.fromMillisecondsSinceEpoch(publishOn.toInt(), isUtc: true).toLocal(),
    url: '$apiBase$slug',
    excerpt: _plainText((item['excerpt'] ?? '') as String),
    cover: cover,
    images: List.unmodifiable(dedupImages),
    sections: List.unmodifiable(sections),
    stats: List.unmodifiable(_dedupStats(stats)),
  );
}

void _collectStats(
  List<StatChange> sink,
  String text, {
  required String category,
  required String item,
}) {
  final inlineItem = itemFromInlinePrefix(text);
  final effectiveItem = item.isEmpty ? (inlineItem ?? '') : item;
  final changes = parseStatChanges(
    text,
    category: category,
    item: effectiveItem,
  );
  sink.addAll(changes);
}

List<StatChange> _dedupStats(List<StatChange> input) {
  final seen = <String>{};
  final out = <StatChange>[];
  for (final change in input) {
    final key = '${change.item}|${change.stat}|${change.before}|${change.after}';
    if (seen.add(key)) out.add(change);
  }
  return out;
}

void _stripNoise(DocumentFragment fragment) {
  fragment.querySelectorAll('style, script, noscript').forEach((e) => e.remove());
}

String _normalize(String input) =>
    input.replaceAll(RegExp(r'[\u00a0\s]+'), ' ').trim();

/// Текст самого элемента без вложенных списков и заголовков.
///
/// Squarespace вкладывает подсписки в `<li>`, а `element.text` склеивает
/// строки без пробела: «…tactical reloadDecrease reload intro animation…».
/// Вложенные `<li>` разбираются отдельными итерациями, поэтому здесь их
/// пропускаем.
String _ownText(Element element) {
  final buffer = StringBuffer();

  void walk(Node node) {
    for (final child in node.nodes) {
      if (child is Element) {
        final name = child.localName ?? '';
        if (const {
          'li', 'ul', 'ol', 'h1', 'h2', 'h3', 'h4', 'img', 'figure',
        }.contains(name)) {
          continue;
        }
        walk(child);
      } else if (child is Text) {
        buffer.write(child.text);
      }
    }
  }

  walk(element);
  return _normalize(buffer.toString());
}

/// Убирает HTML-сущности: «HOTFIX &amp; UPCOMING FIXES».
String decodeEntities(String input) {
  if (!input.contains('&')) return input;
  return html_parser.parseFragment(input).text ?? input;
}

/// Превращает HTML-фрагмент в обычный текст (для описания патча).
String _plainText(String input) {
  final withoutTags = input.replaceAll(RegExp(r'<[^>]+>'), ' ');
  return decodeEntities(withoutTags).replaceAll(RegExp(r'\s+'), ' ').trim();
}

bool _isBoldOnly(Element element) {
  final strong = element.querySelector('strong, b');
  if (strong == null) return false;
  final boldText = _normalize(strong.text);
  final allText = _normalize(element.text);
  if (boldText.isEmpty) return false;
  return boldText == allText;
}

String? _imageUrl(Element element) {
  var src = element.attributes['src'] ??
      element.attributes['data-src'] ??
      element.attributes['data-image'] ??
      '';
  if (src.isEmpty) {
    final srcset = element.attributes['srcset'] ?? '';
    if (srcset.isNotEmpty) {
      src = srcset.split(',').first.trim().split(' ').first;
    }
  }
  if (src.isEmpty) return null;
  if (src.startsWith('//')) src = 'https:$src';
  if (!src.startsWith('http')) return null;
  final lower = src.toLowerCase();
  if (lower.contains('.svg')) return null;
  if (lower.contains('site-icon')) return null;
  if (lower.contains('/universal/')) return null;
  return src;
}

String? _absolute(String maybeRelative, String apiBase) {
  if (maybeRelative.isEmpty) return null;
  if (maybeRelative.startsWith('http')) return maybeRelative;
  if (maybeRelative.startsWith('//')) return 'https:$maybeRelative';
  return '$apiBase$maybeRelative';
}

/// «Update 11.12.0» -> 11.12.0; «HOTFIX» со слагом 12-01 -> 12.0.1.
String detectVersion({
  required String title,
  required String slug,
  required String bodyText,
}) {
  final fromTitle = RegExp(r'(\d{1,2}\.\d{1,2}(?:\.\d{1,2})?)').firstMatch(title);
  if (fromTitle != null) return fromTitle.group(1)!;

  final lastSegment = slug.split('/').where((s) => s.isNotEmpty).last;
  final fromSlug = RegExp(r'^(\d{1,2})-(\d{2,3})$').firstMatch(lastSegment);
  if (fromSlug != null) {
    final major = fromSlug.group(1)!;
    final rest = fromSlug.group(2)!;
    if (rest.length == 3) {
      return '$major.${rest.substring(0, 2)}.${rest.substring(2)}';
    }
    return '$major.0.${int.parse(rest)}';
  }

  // В теле иногда указана дата версии: «2026.10.1» не подходит,
  // поэтому ищем шаблон вида «12.0.1» без века впереди.
  final fromBody = RegExp(r'\b(\d{1,2}\.\d{1,2}\.\d{1,2})\b').firstMatch(bodyText);
  if (fromBody != null) return fromBody.group(1)!;

  return '';
}
