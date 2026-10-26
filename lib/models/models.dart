/// Модели данных приложения: патч, секции, блоки и изменения характеристик.
library;

/// Что произошло с показателем с точки зрения игрока.
enum Impact { buff, nerf, neutral }

Impact impactFromName(String? name) {
  switch (name) {
    case 'buff':
      return Impact.buff;
    case 'nerf':
      return Impact.nerf;
    default:
      return Impact.neutral;
  }
}

String impactName(Impact impact) {
  switch (impact) {
    case Impact.buff:
      return 'buff';
    case Impact.nerf:
      return 'nerf';
    case Impact.neutral:
      return 'neutral';
  }
}

/// Одно числовое изменение: «Патроны в обойме: 30 -> 28».
class StatChange {
  final String category;
  final String item;
  final String stat;
  final double before;
  final double after;
  final String unit;
  final Impact impact;
  final String raw;

  /// Позиция подсвечиваемого фрагмента внутри исходной строки (-1, если неизвестна).
  final int highlightStart;
  final int highlightEnd;

  const StatChange({
    required this.category,
    required this.item,
    required this.stat,
    required this.before,
    required this.after,
    required this.unit,
    required this.impact,
    required this.raw,
    this.highlightStart = -1,
    this.highlightEnd = -1,
  });

  double get delta => after - before;

  String get beforeText => formatNumber(before) + unit;

  String get afterText => formatNumber(after) + unit;

  String get deltaText {
    final sign = delta > 0 ? '+' : (delta < 0 ? '−' : '');
    return '$sign${formatNumber(delta.abs())}$unit';
  }

  Map<String, dynamic> toJson() => {
        'category': category,
        'item': item,
        'stat': stat,
        'before': before,
        'after': after,
        'unit': unit,
        'impact': impactName(impact),
        'raw': raw,
        'hs': highlightStart,
        'he': highlightEnd,
      };

  factory StatChange.fromJson(Map<String, dynamic> json) => StatChange(
        category: (json['category'] ?? '') as String,
        item: (json['item'] ?? '') as String,
        stat: (json['stat'] ?? '') as String,
        before: ((json['before'] ?? 0) as num).toDouble(),
        after: ((json['after'] ?? 0) as num).toDouble(),
        unit: (json['unit'] ?? '') as String,
        impact: impactFromName(json['impact'] as String?),
        raw: (json['raw'] ?? '') as String,
        highlightStart: (json['hs'] ?? -1) as int,
        highlightEnd: (json['he'] ?? -1) as int,
      );

  /// Ключ для группировки в интерфейсе.
  String get groupKey => '$category\u0000$item';
}

/// Блок статьи: заголовок, абзац, пункт списка или картинка.
class DocBlock {
  final String kind; // 'h2' | 'h3' | 'p' | 'li' | 'img'
  final String text;
  final String? url;

  const DocBlock({required this.kind, this.text = '', this.url});

  bool get isHeading => kind == 'h2' || kind == 'h3';

  bool get isList => kind == 'li';

  bool get isImage => kind == 'img';

  Map<String, dynamic> toJson() => {'k': kind, 't': text, if (url != null) 'u': url};

  factory DocBlock.fromJson(Map<String, dynamic> json) => DocBlock(
        kind: (json['k'] ?? 'p') as String,
        text: (json['t'] ?? '') as String,
        url: json['u'] as String?,
      );
}

/// Секция патчноута (например, «GAME UPDATE | BALANCE CHANGES»).
class PatchSection {
  final String title;
  final List<DocBlock> blocks;

  const PatchSection({required this.title, required this.blocks});

  Map<String, dynamic> toJson() => {
        'title': title,
        'blocks': blocks.map((b) => b.toJson()).toList(),
      };

  factory PatchSection.fromJson(Map<String, dynamic> json) => PatchSection(
        title: (json['title'] ?? '') as String,
        blocks: ((json['blocks'] ?? []) as List)
            .map((e) => DocBlock.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Полный патч: версия, дата, скриншоты, текст и числовые изменения.
class PatchDoc {
  final String id;
  final String slug;
  final String title;
  final String version;
  final DateTime date;
  final String url;
  final String excerpt;
  final String? cover;
  final List<String> images;
  final List<PatchSection> sections;
  final List<StatChange> stats;

  const PatchDoc({
    required this.id,
    required this.slug,
    required this.title,
    required this.version,
    required this.date,
    required this.url,
    required this.excerpt,
    required this.cover,
    required this.images,
    required this.sections,
    required this.stats,
  });

  int get buffCount => stats.where((s) => s.impact == Impact.buff).length;

  int get nerfCount => stats.where((s) => s.impact == Impact.nerf).length;

  /// «Update 11.12.0» -> «11.12.0», «Store Update 11.14.0» -> «11.14.0».
  bool get isStore => title.toLowerCase().contains('store');

  String get dateText {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$d.$m.${date.year}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'slug': slug,
        'title': title,
        'version': version,
        'date': date.toIso8601String(),
        'url': url,
        'excerpt': excerpt,
        'cover': cover,
        'images': images,
        'sections': sections.map((s) => s.toJson()).toList(),
        'stats': stats.map((s) => s.toJson()).toList(),
      };

  factory PatchDoc.fromJson(Map<String, dynamic> json) => PatchDoc(
        id: (json['id'] ?? '') as String,
        slug: (json['slug'] ?? '') as String,
        title: (json['title'] ?? '') as String,
        version: (json['version'] ?? '') as String,
        date: DateTime.tryParse((json['date'] ?? '') as String) ?? DateTime.now(),
        url: (json['url'] ?? '') as String,
        excerpt: (json['excerpt'] ?? '') as String,
        cover: json['cover'] as String?,
        images: ((json['images'] ?? []) as List).cast<String>(),
        sections: ((json['sections'] ?? []) as List)
            .map((e) => PatchSection.fromJson(e as Map<String, dynamic>))
            .toList(),
        stats: ((json['stats'] ?? []) as List)
            .map((e) => StatChange.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 30.0 -> "30", 1.75 -> "1.75", -2.5 -> "-2.5"
String formatNumber(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  var text = value.toStringAsFixed(2);
  if (text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}
