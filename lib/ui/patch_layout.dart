/// Раскладка страницы патча в стиле постов Darkside:
///
///   ОБ ОБНОВЕ → ГАДЖЕТЫ И ГЕЙМПЛЕЙ → ИСПРАВЛЕНИЯ
///
/// Патчноут приходит одной секцией, где подразделы («STORE | …»,
/// «GAME UPDATE | BALANCE CHANGES», «…CONTENT & BUG FIXES») — это
/// обычные абзацы-заголовки. Компоновщик режет статью по ним и
/// собирает «вёдра»:
///
/// * news — весь анонс: вступление, магазин, модерация, новые режимы,
///   «GYRO UPDATE» и прочие новости (по ходу статьи).
/// * balance — всё после «… | BALANCE CHANGES». Внутри порядок задан
///   вручную: классы (Heavy → Medium → Light), затем оружие, затем
///   окружение (бочки, геймплей-мир, карты), остальное — как в статье.
/// * bugfix — всё после «…BUG FIXES»: остаются только пункты про
///   исправления («Fixed…», «no longer…»), пустые категории прячем.
///
/// Карточки характеристик прикрепляются к названиям предметов
/// (itemStats), поэтому SectionView показывает «заголовок + карточки»,
/// а текстовые пункты, продублированные карточками, не рисуются.
library;

import '../models/models.dart';

const String kNewsTitle = 'ОБ ОБНОВЕ';
const String kBalanceTitle = 'ГАДЖЕТЫ И ГЕЙМПЛЕЙ';
const String kBugfixTitle = 'ИСПРАВЛЕНИЯ';

/// Готовый раздел страницы патча.
class PatchGroup {
  const PatchGroup(
    this.title,
    this.blocks, {
    this.stats = const [],
    this.itemStats = const {},
  });

  final String title;
  final List<DocBlock> blocks;

  /// Все числовые изменения группы — для подсветки чисел в тексте.
  final List<StatChange> stats;

  /// Карточки, прикреплённые к блокам-предметам («b»): индекс блока → изменения.
  final Map<int, List<StatChange>> itemStats;
}

final RegExp _fixPattern = RegExp(
  r'\bfixed\b|\bno longer\b|исправл|починил',
  caseSensitive: false,
);

final RegExp _letterPattern = RegExp(r'[A-Za-zЁёА-я]');

/// Заголовок-«намёк» на подраздел статьи: абзац капслоком с чертой,
/// например «GAME UPDATE | BALANCE CHANGES».
bool _isPipeHeading(DocBlock block) {
  if (block.kind != 'p') return false;
  final text = block.text.trim();
  if (text.isEmpty || !text.contains('|')) return false;
  final matches = _letterPattern.allMatches(text).toList();
  if (matches.length < 4) return false;
  final upper = matches.where((m) {
    final c = m.group(0)!;
    return c.toUpperCase() == c;
  }).length;
  return upper / matches.length >= 0.8;
}

enum _Bucket { news, balance, bugfix }

_Bucket _bucketOf(String title) {
  final upper = title.toUpperCase();
  if (upper.contains('BUG') || upper.contains('FIX')) return _Bucket.bugfix;
  if (upper.contains('BALANCE')) return _Bucket.balance;
  return _Bucket.news;
}

/// Вес категории внутри «Гаджеты и геймплей»: классы → оружие →
/// окружение → остальное (в порядке статьи).
int _categoryWeight(String heading) {
  final t = heading.trim().toLowerCase();
  if (t == 'archetypes' || t == 'classes') return 0;
  if (t.contains('weapon')) return 1;
  if (t.contains('arena') ||
      t.contains('world') ||
      t.contains('maps') ||
      t.contains('gameplay')) {
    return 2;
  }
  if (t.contains('gadget')) return 3;
  return 5;
}

/// Порядок пунктов внутри категории классов: General вначале,
/// затем Heavy → Medium → Light, остальное не трогаем.
int _archetypeItemWeight(String item) {
  final t = item.trim().toLowerCase();
  if (t == 'general') return 0;
  if (t == 'heavy') return 1;
  if (t == 'medium') return 2;
  if (t == 'light') return 3;
  return 4;
}

class _Part {
  _Part(this.title);
  final String title;
  final List<DocBlock> blocks = [];
}

/// Категория балансовой части: заголовок-«h3» и все блоки до следующего.
class _Run {
  _Run(this.headingBlock) : seq = _counter++;
  static int _counter = 0;
  final int seq;
  final DocBlock headingBlock;
  final List<DocBlock> blocks = [];

  String get headingText => headingBlock.text;
}

/// Собирает группы страницы патча.
List<PatchGroup> layoutPatchDoc(PatchDoc patch) {
  // 1. Режем статью по абзацам-заголовкам на последовательные части.
  final parts = <_Part>[];
  _Part? current;
  for (final section in patch.sections) {
    for (final block in section.blocks) {
      if (_isPipeHeading(block)) {
        current = _Part(block.text.trim());
        parts.add(current);
      } else {
        final part = current;
        if (part == null) {
          current = _Part('');
          parts.add(current);
          current.blocks.add(block);
        } else {
          part.blocks.add(block);
        }
      }
    }
  }

  // 2. Раскладываем части по «вёдрам».
  final newsParts = <_Part>[];
  final balanceParts = <_Part>[];
  final bugfixParts = <_Part>[];
  for (final part in parts) {
    switch (_bucketOf(part.title)) {
      case _Bucket.balance:
        balanceParts.add(part);
      case _Bucket.bugfix:
        bugfixParts.add(part);
      case _Bucket.news:
        newsParts.add(part);
    }
  }

  // 3. Готовые разделы: новости (анонс), баланс, исправления.
  return [
    _newsGroup(newsParts, patch.stats),
    if (balanceParts.isNotEmpty) _balanceGroup(balanceParts, patch.stats),
    _bugfixGroup(bugfixParts, patch.stats),
  ];
}

PatchGroup _newsGroup(List<_Part> parts, List<StatChange> allStats) {
  final blocks = <DocBlock>[];
  for (final part in parts) {
    // Заголовок-часть становится подзаголовком «❙»; у вступительного куска
    // названия нет — он идёт сразу под лентой.
    if (part.title.isNotEmpty) {
      blocks.add(DocBlock(kind: 'h3', text: part.title));
    }
    blocks.addAll(part.blocks);
  }
  return _attachStats(PatchGroup(kNewsTitle, blocks), allStats);
}

PatchGroup _balanceGroup(List<_Part> parts, List<StatChange> allStats) {
  final flat = <DocBlock>[for (final part in parts) ...part.blocks];

  // Разбиваем на «категории» по h3-заголовкам (блоки до первого h3 —
  // категория без названия).
  final runs = <_Run>[];
  for (final block in flat) {
    if (block.kind == 'h3') {
      runs.add(_Run(block));
    } else {
      if (runs.isEmpty) runs.add(_Run(const DocBlock(kind: 'h3', text: '')));
      runs.last.blocks.add(block);
    }
  }

  // Стабильная сортировка категорий: вес раздела + номер следования,
  // чтобы равные веса не путались местами.
  final ordered = runs.toList()
    ..sort((a, b) {
      final byWeight = _categoryWeight(a.headingText)
          .compareTo(_categoryWeight(b.headingText));
      if (byWeight != 0) return byWeight;
      return a.seq.compareTo(b.seq);
    });

  // Категория классов: внутри сортируем пункты General → Heavy → Medium →
  // → Light → остальное.
  final blocks = <DocBlock>[];
  for (final run in ordered) {
    if (run.headingText.trim().isNotEmpty) blocks.add(run.headingBlock);
    final isArchetypes = run.headingText.trim().toLowerCase() == 'archetypes' ||
        run.headingText.trim().toLowerCase() == 'classes';
    blocks.addAll(isArchetypes ? _orderArchetypeItems(run.blocks) : run.blocks);
  }
  return _attachStats(PatchGroup(kBalanceTitle, blocks), allStats);
}

/// В категории классов упорядочиваем предметы: General, Heavy, Medium,
/// Light, остальное. Контент без «b»-заголовка остаётся в начале.
List<DocBlock> _orderArchetypeItems(List<DocBlock> blocks) {
  final pre = <DocBlock>[];
  final items = <_Item>[]; // «карточки» пар: b-заголовок + его пункты
  for (final block in blocks) {
    if (block.kind == 'b') {
      items.add(_Item(block));
    } else if (items.isEmpty) {
      pre.add(block);
    } else {
      items.last.tail.add(block);
    }
  }
  items.sort((a, b) {
    final byWeight = _archetypeItemWeight(a.head.text)
        .compareTo(_archetypeItemWeight(b.head.text));
    if (byWeight != 0) return byWeight;
    return items.indexOf(a).compareTo(items.indexOf(b));
  });
  return [
    ...pre,
    for (final item in items) ...[item.head, ...item.tail],
  ];
}

class _Item {
  _Item(this.head);
  final DocBlock head;
  final List<DocBlock> tail = [];
}

PatchGroup _bugfixGroup(List<_Part> parts, List<StatChange> allStats) {
  final flat = <DocBlock>[for (final part in parts) ...part.blocks];

  // Оставляем только пункты про исправления.
  final filtered = <DocBlock>[];
  for (final block in flat) {
    final isItem =
        block.kind == 'li' || (block.kind == 'p' && !_isPipeHeading(block));
    if (isItem && !_fixPattern.hasMatch(block.text)) continue;
    filtered.add(block);
  }

  // Прячем заголовки категорий, под которыми ничего не осталось.
  final kept = <DocBlock>[];
  for (var i = 0; i < filtered.length; i++) {
    final block = filtered[i];
    if (block.kind != 'h3' && block.kind != 'b') {
      kept.add(block);
      continue;
    }
    var hasContent = false;
    for (var j = i + 1; j < filtered.length; j++) {
      final next = filtered[j];
      if (next.kind == 'h3' || next.kind == 'b') break;
      if (next.kind != 'img' && next.kind != 'video') {
        hasContent = true;
        break;
      }
    }
    if (hasContent) kept.add(block);
  }
  return _attachStats(PatchGroup(kBugfixTitle, kept), allStats);
}

/// Прикрепляет карточки изменений к блокам-предметам.
///
/// «General» встречается в разных категориях, поэтому совпадают и имя
/// предмета, и категория (текущий h3-заголовок).
PatchGroup _attachStats(PatchGroup group, List<StatChange>? allStats) {
  if (allStats == null || allStats.isEmpty || group.blocks.isEmpty) {
    return group;
  }
  final itemStats = <int, List<StatChange>>{};
  var currentCategory = '';
  for (var i = 0; i < group.blocks.length; i++) {
    final block = group.blocks[i];
    if (block.kind == 'h3') {
      final text = block.text.trim();
      if (text.isNotEmpty) currentCategory = text;
      continue;
    }
    if (block.kind != 'b') continue;
    final matches = allStats
        .where(
          (s) =>
              s.item == block.text &&
              (currentCategory.isEmpty ||
                  s.category.toLowerCase() == currentCategory.toLowerCase()),
        )
        .toList(growable: false);
    if (matches.isNotEmpty) itemStats[i] = matches;
  }
  return PatchGroup(
    group.title,
    group.blocks,
    stats: allStats,
    itemStats: itemStats,
  );
}

/// Статы, которые не прикрепились ни к одному разделу.
List<StatChange> looseStats(PatchDoc patch, List<PatchGroup> groups) {
  final items = <String>{
    for (final group in groups)
      for (final block in group.blocks)
        if (block.kind == 'b') block.text,
  };
  final raws = <String>{
    for (final group in groups)
      for (final block in group.blocks)
        if (block.kind == 'li') block.text,
  };
  final attached = <String>{
    for (final group in groups)
      for (final list in group.itemStats.values)
        for (final s in list) s.raw,
  };
  return patch.stats
      .where(
        (s) =>
            !items.contains(s.item) &&
            !raws.contains(s.raw) &&
            !attached.contains(s.raw),
      )
      .toList();
}
