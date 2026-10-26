/// Сборка постов для Telegram из разобранного патча.
///
/// Модуль чистый: ни Flutter, ни сети. Его использует консольный бот
/// (`tool/bot.dart`), а тесты проверяют вёрстку без похода в Telegram.
///
/// Telegram принимает HTML только с тегами `<b>`, `<i>`, `<u>`, `<s>`,
/// `<a href>`, `<code>`, `<pre>` и `<blockquote>` — поэтому всё остальное
/// экранируется, а сообщения режутся по границам строк, чтобы не разорвать
/// тег пополам.
library;

import '../l10n/glossary.dart';
import '../models/models.dart';

/// Лимит Telegram на текст одного сообщения.
const int telegramMessageLimit = 4096;

/// Экранирует текст под `parse_mode: HTML`.
String escapeHtml(String input) => input
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// Делит готовый текст на сообщения не длиннее [limit].
///
/// Строки уже самодостаточны (каждая закрывает свои теги), поэтому режем
/// по переводу строки. Слишком длинную строку дробим по словам — это
/// аварийный путь, рендерер до него не доводит.
List<String> splitMessageText(String text, {int limit = telegramMessageLimit}) {
  final messages = <String>[];
  final buffer = StringBuffer();
  var length = 0;

  void flush() {
    final value = buffer.toString().trimRight();
    if (value.isNotEmpty) messages.add(value);
    buffer.clear();
    length = 0;
  }

  for (final rawLine in text.split('\n')) {
    final line = rawLine;
    if (line.length > limit) {
      flush();
      for (final piece in _splitLong(line, limit)) {
        messages.add(piece);
      }
      continue;
    }

    final extra = (length == 0 ? 0 : 1) + line.length;
    if (length > 0 && length + extra > limit) flush();

    if (length > 0) {
      buffer.write('\n');
      length += 1;
    }
    buffer.write(line);
    length += line.length;
  }
  flush();
  return messages;
}

/// Копилка строк, которая сама начинает новое сообщение на лимите.
class MessageBuilder {
  MessageBuilder({
    this.continuation,
    this.limit = telegramMessageLimit,
  });

  /// Строка, с которой начинается каждое следующее сообщение.
  final String? continuation;

  final int limit;

  final List<String> _messages = [];
  final StringBuffer _buffer = StringBuffer();
  int _length = 0;

  List<String> build() {
    _flush(startNext: false);
    return List<String>.unmodifiable(_messages);
  }

  void line([String html = '']) {
    if (html.length > limit) {
      _flush();
      for (final piece in _splitLong(html, limit)) {
        _append(piece);
      }
      return;
    }

    final extra = (_length == 0 ? 0 : 1) + html.length;
    if (_length > 0 && _length + extra > limit) _flush();
    _append(html);
  }

  void _append(String html) {
    if (_length > 0) {
      _buffer.write('\n');
      _length += 1;
    }
    _buffer.write(html);
    _length += html.length;
  }

  void _flush({bool startNext = true}) {
    final text = _buffer.toString().trimRight();
    if (text.isNotEmpty) _messages.add(text);
    _buffer.clear();
    _length = 0;

    final next = continuation;
    if (startNext && next != null && next.isNotEmpty && _messages.isNotEmpty) {
      _buffer.write(next);
      _buffer.write('\n');
      _length = next.length + 1;
    }
  }
}

/// Короткий дайджест: версия, счётчик баффов/нерфов, изменения баланса.
///
/// Такой пост обычно влезает в одно сообщение. Если изменений очень много,
/// хвост уезжает во второе сообщение, а не теряется.
List<String> renderDigest(
  PatchDoc patch, {
  Map<String, String> translations = const {},
  int maxStats = 80,
}) {
  final builder = MessageBuilder(continuation: '<i>…продолжение</i>');
  final title = translateTitle(patch.title);

  builder.line('🔥 <b>${escapeHtml(title)}</b>');
  builder.line(
    '<i>${patch.dateText}</i> · '
    '<a href="${escapeHtml(patch.url)}">на сайте</a>',
  );

  final excerpt = _translated(translations, patch.excerpt);
  if (excerpt.isNotEmpty) {
    builder.line('');
    builder.line('<blockquote>${escapeHtml(_shorten(excerpt, 400))}</blockquote>');
  }

  final buffs = patch.buffCount;
  final nerfs = patch.nerfCount;
  final neutral = patch.stats.length - buffs - nerfs;
  if (patch.stats.isNotEmpty) {
    builder.line('');
    final parts = <String>[
      if (buffs > 0) '▲ $buffs ${_plural(buffs, 'улучшение', 'улучшения', 'улучшений')}',
      if (nerfs > 0) '▼ $nerfs ${_plural(nerfs, 'ослабление', 'ослабления', 'ослаблений')}',
      if (neutral > 0) '● $neutral ${_plural(neutral, 'изменение', 'изменения', 'изменений')}',
    ];
    builder.line(parts.join(' · '));
  }

  final shown = patch.stats.take(maxStats).toList();
  final grouped = <String, Map<String, List<StatChange>>>{};
  for (final change in shown) {
    final category = change.category.trim().isEmpty ? 'БАЛАНС' : change.category.trim();
    final item = change.item.trim();
    final byItem = grouped.putIfAbsent(category, () => {});
    byItem.putIfAbsent(item, () => []).add(change);
  }

  for (final category in grouped.keys) {
    builder.line('');
    final categoryText = translateHeading(_translated(translations, category));
    builder.line('<b>${escapeHtml(categoryText.toUpperCase())}</b>');
    for (final entry in grouped[category]!.entries) {
      if (entry.key.isNotEmpty) {
        builder.line('');
        builder.line('<b>${escapeHtml(entry.key)}</b>');
      }
      for (final change in entry.value) {
        // Словарь точнее машинного перевода на коротких названиях
        // («damage» — это «урон», а не «повреждать»).
        final dictionary = translateStatName(change.stat);
        final display = dictionary != change.stat
            ? dictionary
            : _translated(translations, change.stat);
        builder.line(
          '${_arrow(change.impact)} ${escapeHtml(display)}: '
          '${escapeHtml(change.beforeText)} → ${escapeHtml(change.afterText)}',
        );
      }
    }
  }

  if (patch.stats.length > shown.length) {
    builder.line('');
    builder.line(
      '<i>…и ещё ${patch.stats.length - shown.length} '
      '${_plural(patch.stats.length - shown.length, 'изменение', 'изменения', 'изменений')} — '
      'в полном патче.</i>',
    );
  }

  if (patch.stats.isEmpty) {
    _renderTextDigest(builder, patch, translations);
  }

  builder.line('');
  builder.line('<a href="${escapeHtml(patch.url)}">Читать полностью на reachthefinals.com</a>');

  return builder.build();
}

/// Текстовая версия дайджеста для патчей без числовых изменений.
///
/// Показываем заголовки и пункты, но пропускаем длинные вступления
/// (маркетинговый текст на пол-экрана) и служебные даты.
void _renderTextDigest(
  MessageBuilder builder,
  PatchDoc patch,
  Map<String, String> translations,
) {
  var blocks = 0;
  const maxBlocks = 40;

  for (final section in patch.sections) {
    final heading = translateHeading(section.title);
    if (heading.trim().isNotEmpty && heading != 'Обновление') {
      builder.line('');
      builder.line('<b>${escapeHtml(heading.toUpperCase())}</b>');
    }

    for (final block in section.blocks) {
      if (blocks >= maxBlocks) break;

      final text = _translated(translations, block.text);
      switch (block.kind) {
        case 'h3':
          builder.line('');
          builder.line('<b>${escapeHtml(translateHeading(text))}</b>');
          blocks++;
          break;
        case 'b':
          builder.line('');
          builder.line('<b>${escapeHtml(text)}</b>');
          blocks++;
          break;
        case 'li':
          builder.line('• ${escapeHtml(text)}');
          blocks++;
          break;
        case 'img':
          break;
        default:
          if (_isHeadingLike(block.text)) {
            builder.line('');
            builder.line('<b>${escapeHtml(translateHeading(text).toUpperCase())}</b>');
            blocks++;
          } else if (block.text.length >= 30 &&
              block.text.length <= 260 &&
              !_isDate(block.text)) {
            builder.line(escapeHtml(text));
            blocks++;
          }
      }
    }
  }

  if (blocks >= maxBlocks) {
    builder.line('');
    builder.line('<i>…дальше — по ссылке.</i>');
  }

  if (blocks == 0) {
    builder.line('Числовых изменений нет — полный текст по ссылке.');
  }
}

/// Полный перевод патча: все разделы, заголовки и пункты.
///
/// Крупный патч не влезает в 4096 символов, поэтому получается несколько
/// сообщений подряд — Telegram покажет их одним блоком в канале.
List<String> renderFull(
  PatchDoc patch, {
  Map<String, String> translations = const {},
}) {
  final builder = MessageBuilder(continuation: '<i>…продолжение</i>');
  final title = translateTitle(patch.title);

  builder.line('🔥 <b>${escapeHtml(title)}</b>');
  builder.line(
    '<i>${patch.dateText}</i> · '
    '<a href="${escapeHtml(patch.url)}">на сайте</a>',
  );

  for (final section in patch.sections) {
    final heading = translateHeading(section.title);
    if (heading.trim().isNotEmpty && heading != 'Обновление') {
      builder.line('');
      builder.line('<b>${escapeHtml(heading.toUpperCase())}</b>');
    }

    for (final block in section.blocks) {
      switch (block.kind) {
        case 'h3':
          builder.line('');
          builder.line('<b>${escapeHtml(translateHeading(block.text))}</b>');
          break;
        case 'b':
          builder.line('');
          builder.line('<b>${escapeHtml(_translated(translations, block.text))}</b>');
          break;
        case 'li':
          builder.line('• ${escapeHtml(_translated(translations, block.text))}');
          break;
        case 'img':
          break;
        default:
          if (_isDate(block.text)) break;
          if (_isHeadingLike(block.text)) {
            builder.line('');
            builder.line(
              '<b>${escapeHtml(translateHeading(_translated(translations, block.text)).toUpperCase())}</b>',
            );
          } else {
            builder.line(escapeHtml(_translated(translations, block.text)));
          }
      }
    }
  }

  builder.line('');
  builder.line('<a href="${escapeHtml(patch.url)}">Источник: reachthefinals.com</a>');
  return builder.build();
}

String _translated(Map<String, String> translations, String source) {
  final value = translations[source];
  if (value == null || value.trim().isEmpty) return source;
  // Google иногда вставляет zero-width пробелы внутри слов.
  return value.replaceAll(RegExp(r'[\u200b-\u200d\ufeff]'), '');
}

/// Заголовок в тексте патча часто оформлен обычным абзацем капсом:
/// «ARENA UPDATES | REWORK & VISUAL UPGRADES». Такой абзац выделяем жирным.
bool _isHeadingLike(String text) {
  final value = text.trim();
  if (value.length < 3 || value.length > 90) return false;
  final letters = value.replaceAll(RegExp(r'[^A-Za-z]'), '');
  if (letters.isEmpty) return false;
  return letters == letters.toUpperCase();
}

/// Служебная дата в начале тела статьи: «2026.10.21».
bool _isDate(String text) =>
    RegExp(r'^\d{4}\.\d{2}\.\d{2}$').hasMatch(text.trim());

String _arrow(Impact impact) => switch (impact) {
      Impact.buff => '▲',
      Impact.nerf => '▼',
      Impact.neutral => '●',
    };

String _plural(int count, String one, String few, String many) {
  final mod100 = count % 100;
  final mod10 = count % 10;
  if (mod100 >= 11 && mod100 <= 14) return many;
  if (mod10 == 1) return one;
  if (mod10 >= 2 && mod10 <= 4) return few;
  return many;
}

/// Обрезает текст по границе слова, чтобы не рвать слово пополам.
String _shorten(String text, int limit) {
  final value = text.trim();
  if (value.length <= limit) return value;
  final cut = value.substring(0, limit);
  final space = cut.lastIndexOf(' ');
  return '${(space > limit * 0.6 ? cut.substring(0, space) : cut).trimRight()}…';
}

List<String> _splitLong(String text, int limit) {
  final pieces = <String>[];
  final buffer = StringBuffer();
  var length = 0;

  for (final word in text.split(' ')) {
    final extra = (length == 0 ? 0 : 1) + word.length;
    if (length > 0 && length + extra > limit) {
      pieces.add(buffer.toString());
      buffer.clear();
      length = 0;
    }
    if (length > 0) {
      buffer.write(' ');
      length += 1;
    }
    buffer.write(word);
    length += word.length;
  }
  if (buffer.isNotEmpty) pieces.add(buffer.toString());

  // Слово длиннее лимита (ссылка, base64) — режем как есть.
  final result = <String>[];
  for (final piece in pieces) {
    if (piece.length <= limit) {
      result.add(piece);
      continue;
    }
    for (var start = 0; start < piece.length; start += limit) {
      result.add(piece.substring(
        start,
        start + limit > piece.length ? piece.length : start + limit,
      ));
    }
  }
  return result;
}
