import 'package:flutter/material.dart';

import '../../l10n/glossary.dart';
import '../../models/models.dart';
import '../theme.dart';

/// Рендерит один раздел статьи: заголовки, пункты, абзацы и картинки.
/// Числовые изменения внутри текста подсвечиваются зелёным/красным.
class SectionView extends StatelessWidget {
  const SectionView({
    super.key,
    required this.section,
    required this.stats,
    this.translations = const {},
  });

  final PatchSection section;
  final List<StatChange> stats;

  /// Переводы блоков: оригинальный текст -> русский.
  final Map<String, String> translations;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (section.title.isNotEmpty) ...[
            Text(
              translateHeading(section.title).toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: 10),
          ],
          for (final block in section.blocks) _block(context, block),
        ],
      ),
    );
  }

  Widget _block(BuildContext context, DocBlock block) {
    switch (block.kind) {
      case 'h3':
        return Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 6),
          child: Row(
            children: [
              Container(width: 3, height: 15, color: AppColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  translateHeading(block.text),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        );
      case 'b':
        return Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(
            translations[block.text] ?? block.text,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        );
      case 'li':
        return Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 8, right: 10),
                child: SizedBox(
                  width: 5,
                  height: 5,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: AppColors.textDim, shape: BoxShape.circle),
                  ),
                ),
              ),
              Expanded(
                child: HighlightedText(
                  text: translations[block.text] ?? block.text,
                  sourceText: block.text,
                  changes: stats,
                ),
              ),
            ],
          ),
        );
      case 'img':
        final url = block.url;
        if (url == null) return const SizedBox.shrink();
        // Картинки в патче бывают по 1500+ px. Декодируем под ширину экрана,
        // иначе каждая занимает десятки мегабайт памяти и скролл проседает.
        final decodeWidth =
            ((MediaQuery.sizeOf(context).width - 32) * MediaQuery.devicePixelRatioOf(context))
                .round();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(
              url,
              fit: BoxFit.cover,
              cacheWidth: decodeWidth,
              filterQuality: FilterQuality.low,
              errorBuilder: (_, __, ___) => const SizedBox(height: 0),
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return Container(
                  height: 160,
                  color: AppColors.surfaceAlt,
                  child: const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textDim),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      default:
        // Строки-заголовки вроде «GAME UPDATE | BUG FIXES» переводим словарём,
        // не отправляя в машинный перевод.
        final heading = translateHeading(block.text);
        final display = heading != block.text
            ? heading
            : (translations[block.text] ?? block.text);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: HighlightedText(
            text: display,
            sourceText: block.text,
            changes: stats,
          ),
        );
    }
  }
}

/// Текст с подсветкой числовых изменений.
///
/// Если текст переведён, точные позиции подсветки уже не совпадают,
/// поэтому числа «было» и «стало» ищутся по значению.
class HighlightedText extends StatelessWidget {
  const HighlightedText({
    super.key,
    required this.text,
    required this.changes,
    this.sourceText,
    this.style,
  });

  final String text;
  final String? sourceText;
  final List<StatChange> changes;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final source = sourceText ?? text;
    final base = style ??
        const TextStyle(fontSize: 14, height: 1.55, color: AppColors.textPrimary);

    final applicable = changes.where((c) {
      if (c.raw != source) return false;
      if (source == text) {
        return c.highlightStart >= 0 &&
            c.highlightEnd <= text.length &&
            c.highlightEnd > c.highlightStart;
      }
      return true;
    }).toList()
      ..sort((a, b) => a.highlightStart.compareTo(b.highlightStart));

    if (applicable.isEmpty) return Text(text, style: base);

    if (source == text) {
      return Text.rich(TextSpan(style: base, children: _rangedSpans(applicable)));
    }
    return Text.rich(TextSpan(style: base, children: _numericSpans(applicable)));
  }

  List<TextSpan> _rangedSpans(List<StatChange> applicable) {
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final change in applicable) {
      if (change.highlightStart < cursor) continue;
      if (change.highlightStart > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, change.highlightStart)));
      }
      spans.add(TextSpan(
        text: text.substring(change.highlightStart, change.highlightEnd),
        style: TextStyle(color: impactColor(change.impact), fontWeight: FontWeight.w700),
      ));
      cursor = change.highlightEnd;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return spans;
  }

  /// Подсветка по значениям: «37» и «30» в переводе остаются числами.
  List<TextSpan> _numericSpans(List<StatChange> applicable) {
    final targets = <String, Color>{};
    for (final change in applicable) {
      final color = impactColor(change.impact);
      targets[formatNumber(change.before)] = color;
      targets[formatNumber(change.after)] = color;
    }

    final pattern = RegExp(
      targets.keys.map(RegExp.escape).join('|'),
      caseSensitive: false,
    );

    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(0),
        style: TextStyle(
          color: targets[match.group(0)] ?? AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ));
      cursor = match.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return spans;
  }
}
