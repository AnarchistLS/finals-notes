/// Разбор числовых изменений из строк патчноутов.
///
/// Официальные заметки пишут изменения прозой:
///   «Decreased cooldown from 37s to 30s»
///   «Increased max placement distance from 40m to 50m»
///   «Reduced magazine size from 30 to 28»
///
/// Задача — вытащить показатель, «было» и «стало», а затем понять,
/// стало лучше или хуже. Для этого мало знать направление: кулдаун
/// вниз — это хорошо, а урон вниз — плохо. Поэтому у показателей есть
/// полярность: у одних «больше = лучше», у других «меньше = лучше».
library;

import '../models/models.dart';

class _ChangePattern {
  const _ChangePattern(this.regex);
  final RegExp regex;
}

final List<_ChangePattern> _patterns = [
  // from 37s to 30s / 37s to 30s
  _ChangePattern(RegExp(
    r'(-?\d+(?:[.,]\d+)?)\s*([a-zA-Zа-яА-Я%]{0,6})?\s+(?:to|→|->)\s+(-?\d+(?:[.,]\d+)?)\s*([a-zA-Zа-яА-Я%]{0,6})?',
    caseSensitive: false,
  )),
  // 37s → 30s (без слова to)
  _ChangePattern(RegExp(
    r'(-?\d+(?:[.,]\d+)?)\s*([a-zA-Zа-яА-Я%]{0,6})?\s*(?:→|->)\s*(-?\d+(?:[.,]\d+)?)\s*([a-zA-Zа-яА-Я%]{0,6})?',
    caseSensitive: false,
  )),
];

/// Показатели, у которых меньшее значение — это улучшение.
const List<String> _lowerIsBetter = [
  'cooldown',
  'reload',
  'spread',
  'recoil',
  'falloff',
  'deploy',
  'windup',
  'wind-up',
  'charge time',
  'delay',
  'swap',
  'cost',
  'ttk',
  'respawn',
  'kick',
  'bloom',
  'dispersion',
  'recovery',
  'penalty',
  'slow',
  'vfx',
];

/// Показатели, у которых большее значение — улучшение.
const List<String> _higherIsBetter = [
  'damage',
  'ammo',
  'magazine',
  'round',
  'capacity',
  'health',
  'hp',
  'radius',
  'range',
  'speed',
  'duration',
  'healing',
  'heal',
  'point',
  'projectile',
  'shot',
  'count',
  'rate',
  'accuracy',
  'armor',
  'resistance',
  'scalar',
  'reserve',
  'distance',
  'angle',
  'shield',
  'amount',
];

bool lowerIsBetter(String stat) {
  final s = stat.toLowerCase();
  for (final key in _lowerIsBetter) {
    if (s.contains(key)) return true;
  }
  // «respawn time», «time to reload» — но не «duration», у которой
  // длительность обычно и есть польза (дольше невидимость — лучше).
  if (s.contains('time') && !s.contains('duration')) return true;
  return false;
}

bool _knownStat(String stat) {
  final s = stat.toLowerCase();
  return _lowerIsBetter.any(s.contains) ||
      _higherIsBetter.any(s.contains) ||
      s.contains('time');
}

int _verbDirection(String text) {
  final head = text.toLowerCase();
  final up = RegExp(r'\b(increas|rais|buff|boost|improv|expand)\w*').firstMatch(head);
  final down = RegExp(r'\b(decreas|reduc|lower|nerf|cut|shrink)\w*').firstMatch(head);
  if (up == null && down == null) return 0;
  if (up == null) return -1;
  if (down == null) return 1;
  return up.start <= down.start ? 1 : -1;
}

String _cleanStat(String prefix, String suffix) {
  var stat = prefix.trim();
  stat = stat.replaceFirst(RegExp(r'\b(from|by|of|at|to)\s*$', caseSensitive: false), '');
  stat = stat.replaceFirst(
    RegExp(
      r'^(?:increased|increases|increasing|decreased|decreases|decreasing|reduced|reduces|reducing|lowered|lower|raised|raise|buffed|buff|boosted|boost|improved|improve|expanded|expand|cut|nerfed|nerf)\s+',
      caseSensitive: false,
    ),
    '',
  );
  // «Dome Shield health increased from 250 to 600» — глагол стоит после показателя.
  stat = stat.replaceFirst(
    RegExp(
      r'\s+(?:increased|decreased|reduced|lowered|raised|buffed|nerfed|boosted|improved)$',
      caseSensitive: false,
    ),
    '',
  );
  stat = stat.replaceFirst(RegExp(r'^(?:the|a|an)\s+', caseSensitive: false), '');
  stat = stat.replaceAll(RegExp(r'\s+'), ' ').trim();
  stat = stat.replaceAll(RegExp(r'[.,;:\-–—\s]+$'), '').trim();

  if (stat.isEmpty) {
    stat = suffix.trim().replaceAll(RegExp(r'\s+'), ' ');
  }
  if (stat.isEmpty) stat = 'значение';
  if (stat.length > 70) stat = stat.substring(0, 70).trim();
  return stat;
}

bool _looksLikeUnit(String unit) {
  if (unit.isEmpty) return true;
  final u = unit.toLowerCase();
  // «to», «from» и прочие слова — не единицы измерения.
  return !const {'to', 'from', 'and', 'or', 'by', 'of', 'the'}.contains(u);
}

/// Отсеивает прозу и служебные числа: суммы, даты, годы, номера версий.
/// Без этого «compete for $150,000 from November 27 to 29» превратилось бы
/// в «изменение характеристики».
bool _looksLikeProse(String line, double before, double after) {
  if (line.length > 240) return true;
  if (RegExp(r'[$€£]').hasMatch(line)) return true;
  if (before >= 1000 && after >= 1000) return true;
  if (RegExp(
    r'\b(january|february|march|april|may|june|july|august|september|october|november|december)\b',
    caseSensitive: false,
  ).hasMatch(line)) {
    return true;
  }
  if (RegExp(r',\s*(which|and|but|where|while)\b', caseSensitive: false).hasMatch(line)) {
    return true;
  }
  if (RegExp(r'^[a-zа-я]').hasMatch(line)) return true;
  if (RegExp(r'\b(update|season|version|patch)\s+\d', caseSensitive: false).hasMatch(line)) {
    return true;
  }
  return false;
}

/// Достаёт все числовые изменения из одной строки.
///
/// [category] — раздел («Gadgets», «Light», «Weapons»),
/// [item] — предмет, к которому относится строка («Zipline», «ARN-220»).
List<StatChange> parseStatChanges(
  String text, {
  required String category,
  required String item,
}) {
  if (text.isEmpty) return const [];
  if (!RegExp(r'\d').hasMatch(text)) return const [];
  if (!RegExp(r'\b(to|from)\b|→|->', caseSensitive: false).hasMatch(text)) {
    return const [];
  }

  final result = <StatChange>[];

  for (final pattern in _patterns) {
    for (final match in pattern.regex.allMatches(text)) {
      final beforeRaw = match.group(1);
      final afterRaw = match.group(3);
      if (beforeRaw == null || afterRaw == null) continue;

      final before = double.tryParse(beforeRaw.replaceAll(',', '.'));
      final after = double.tryParse(afterRaw.replaceAll(',', '.'));
      if (before == null || after == null) continue;
      if (before == after) continue;
      if (_looksLikeProse(text, before, after)) continue;

      final beforeUnit = (match.group(2) ?? '').trim();
      final afterUnit = (match.group(4) ?? '').trim();

      // Защита от «45 degrees» -> «degrees» в качестве единицы: длинные
      // «единицы» на деле являются словами, поэтому отбрасываем их.
      final unitSource = beforeUnit.isNotEmpty && beforeUnit.length <= 3
          ? beforeUnit
          : (afterUnit.isNotEmpty && afterUnit.length <= 3 ? afterUnit : '');

      final prefix = text.substring(0, match.start).trim();
      final suffix = text.substring(match.end).trim();
      final stat = _cleanStat(prefix, suffix);

      final verbDir = _verbDirection(text);
      final numericDir = after > before ? 1 : -1;
      final direction = verbDir != 0 ? verbDir : numericDir;

      Impact impact;
      if (!_knownStat(stat)) {
        // Незнакомый показатель: доверяем явному глаголу, иначе считаем,
        // что рост значения — улучшение.
        impact = direction > 0 ? Impact.buff : Impact.nerf;
      } else {
        final good = lowerIsBetter(stat) ? -direction : direction;
        impact = good > 0
            ? Impact.buff
            : (good < 0 ? Impact.nerf : Impact.neutral);
      }

      // Подсвечиваем сам фрагмент замены: «from 30 to 28».
      var start = match.start;
      final lookBehind = text.substring(0, match.start);
      final fromMatch = RegExp(r'from\s*$', caseSensitive: false).firstMatch(lookBehind);
      if (fromMatch != null) start = fromMatch.start;

      result.add(StatChange(
        category: category,
        item: item,
        stat: stat,
        before: before,
        after: after,
        unit: _looksLikeUnit(unitSource) ? unitSource : '',
        impact: impact,
        raw: text,
        highlightStart: start,
        highlightEnd: match.end,
      ));

      // Одна строка — одно изменение: не дублируем вторым шаблоном.
      break;
    }
    if (result.isNotEmpty) break;
  }

  return result;
}

/// Пробует понять, к какому предмету относится строка без явного заголовка:
/// «ARN-220: Reduced magazine size from 30 to 28» -> item = «ARN-220».
String? itemFromInlinePrefix(String text) {
  final idx = text.indexOf(':');
  if (idx <= 0 || idx > 40) return null;
  final prefix = text.substring(0, idx).trim();
  if (prefix.isEmpty) return null;
  if (RegExp(r'^\d').hasMatch(prefix)) return null;
  if (prefix.split(' ').length > 4) return null;
  return prefix;
}
