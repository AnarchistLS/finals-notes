/// Подготовка перевода целого патча: сбор строк, перевод и подстановка.
///
/// Один и тот же код используют и бот-постер, и пайплайн Mini App: так
/// канал и приложение показывают одинаковый текст, а кеш переводов
/// (файл `tool/.translation-cache.json`) общий - DeepL не тратит квоту
/// дважды на один и тот же патч.
library;

import '../l10n/glossary.dart';
import '../models/models.dart';
import 'translator.dart';

/// Строки патча, которые надо перевести машинно.
///
/// Словарные термины (`translateHeading`), числа и пустые строки сюда не
/// попадают: их переводит глоссарий прямо при отрисовке.
///
/// [full] = false - только то, что нужно для дайджеста канала (названия
/// характеристик и изменения). [full] = true - весь текст патча, как в
/// приложении и Mini App.
Set<String> collectDocTexts(PatchDoc patch, {bool full = true}) {
  final texts = <String>{};

  void add(String value) {
    final text = value.trim();
    if (text.isEmpty) return;
    if (!RegExp(r'[A-Za-z]').hasMatch(text)) return;
    if (translateHeading(text) != text) return;
    texts.add(text);
  }

  add(patch.excerpt);
  for (final stat in patch.stats) {
    add(stat.category);
    add(stat.stat);
  }

  // Дайджест без числовых изменений показывает текст, поэтому переводим
  // блоки и в этом случае. Для патча с балансом хватает названий
  // характеристик.
  if (full || patch.stats.isEmpty) {
    for (final section in patch.sections) {
      // Названия разделов переводит глоссарий при отрисовке, в машинный
      // перевод их не отправляем - это лишние символы в квоте DeepL.
      for (final block in section.blocks) {
        if (block.kind == 'p' ||
            block.kind == 'li' ||
            block.kind == 'b' ||
            block.kind == 'h3') {
          add(block.text);
        }
      }
    }
  }

  return texts;
}

/// Переводит все строки патча и возвращает карту «оригинал -> перевод».
///
/// Ключи карты - ровно те строки, что лежат в [PatchDoc]: при отрисовке
/// `SectionView` и `StatTile` ищут перевод по исходному тексту.
Future<Map<String, String>> translateDoc(
  PatchDoc patch,
  PatchTranslator translator, {
  bool full = true,
  void Function(int done, int total)? onProgress,
}) async {
  final texts = collectDocTexts(patch, full: full);
  if (texts.isEmpty) return <String, String>{};
  return translator.translateAll(texts, onProgress: onProgress);
}
