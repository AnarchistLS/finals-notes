/// Русская локализация: словарь терминов и защита имён собственных.
///
/// Правило проекта: интерфейс, названия характеристик и текст патчноутов —
/// по-русски. Названия предметов, локаций, классов и специализаций остаются
/// такими, как в игре (ARN-220, Monaco, Light, Grappling Hook).
library;

/// Названия, которые переводчик не должен трогать.
const List<String> properNames = [
  // Классы
  'Light', 'Medium', 'Heavy',
  // Специализации
  'Cloaking Device', 'Evasive Dash', 'Grappling Hook', 'Healing Beam',
  'Guardian Turret', 'Recon Senses', 'Dematerializer', 'Charge N Slam',
  'Goo Gun', 'Mesh Shield', 'Winch Claw',
  // Оружие
  'AKM', 'FCAR', 'M11', 'XP-54', 'V9S', 'LH1', 'SR-84', 'SH1900',
  'Model 1887', 'R.357', '93R', 'CL-40', 'Pike-556', 'Cerberus 12GA',
  'M60', 'Lewis Gun', 'SA1216', 'KS-23', 'Shak-50', 'Flamethrower',
  '.50 Akimbo', 'Sledgehammer', 'Spear', 'Dagger', 'Sword',
  'Throwing Knives', 'Recurve Bow', 'Double Barrel', 'M26 Matter',
  'ARN-220', 'FAMAS', 'Bullpup', 'BFR', 'CB-01',
  // Гаджеты
  'Zipline', 'Jump Pad', 'Defibrillator', 'APS Turret', 'Dome Shield',
  'Barricade', 'RPG-7', 'C4', 'Breach Charge', 'Gateway', 'Goo Grenade',
  'Glitch Grenade', 'Flashbang', 'Pyro Grenade', 'Smoke Grenade',
  'Thermal Bore', 'Tracking Dart', 'Vanishing Bomb', 'Data Reshaper',
  'Explosive Mine', 'Gas Mine', 'Glitch Trap', 'Motion Sensor', 'Stun Gun',
  'Pyro Mine', 'Anti-Gravity Cube', 'Healing Emitter',
  // Карты
  'Monaco', 'Seoul', 'Skyway Stadium', 'Las Vegas', 'Kyoto', 'Sys Horizon',
  r'Sys$Horizon', 'Fortune Stadium', 'Bernal', 'Duck It', 'Horizon',
  // Прочее из мира игры
  'THE FINALS', 'The Finals', 'Contestants', 'Contestant',
];

final RegExp _codePattern = RegExp(
  r'\b(?:[A-Z]{2,4}-\d{2,4}|R\.357|93R|LH1|M11|V9S|AKM|FCAR|M60|SA1216|KS-23)\b',
);

/// Разбивает строку на «защищённые» фрагменты и обычный текст.
List<String> detectProperNames(String text) {
  final found = <String>{};
  for (final name in properNames) {
    final re = RegExp(
      '\\b${RegExp.escape(name).replaceAll(r'\ ', r'\s+')}\\b',
      caseSensitive: name == name.toUpperCase(),
    );
    if (re.hasMatch(text)) found.add(name);
  }
  for (final match in _codePattern.allMatches(text)) {
    found.add(match.group(0)!);
  }
  return found.toList()..sort((a, b) => b.length.compareTo(a.length));
}

/// Подставляет вместо имён собственных маркеры ⟦0⟧, ⟦1⟧…
String protectTerms(String text, List<String> terms) {
  var result = text;
  for (var i = 0; i < terms.length; i++) {
    final name = terms[i];
    final re = RegExp(RegExp.escape(name), caseSensitive: false);
    result = result.replaceAll(re, '⟦$i⟧');
  }
  return result;
}

/// Возвращает имена на место (учитывает пробелы, которые мог добавить переводчик).
String restoreTerms(String text, List<String> terms) {
  var result = text;
  for (var i = 0; i < terms.length; i++) {
    result = result.replaceAll(RegExp('⟦\\s*$i\\s*⟧'), terms[i]);
  }
  return result;
}

// --- Заголовки разделов -----------------------------------------------------

const Map<String, String> _headings = {
  'GAME UPDATE': 'ОБНОВЛЕНИЕ ИГРЫ',
  'BALANCE CHANGES': 'ИЗМЕНЕНИЯ БАЛАНСА',
  'CONTENT AND BUG FIXES': 'КОНТЕНТ И ИСПРАВЛЕНИЯ',
  'BUG FIXES': 'ИСПРАВЛЕНИЯ',
  'KNOWN ISSUES': 'ИЗВЕСТНЫЕ ПРОБЛЕМЫ',
  'QUALITY OF LIFE': 'УДОБСТВО',
  'WEAPONS': 'ОРУЖИЕ',
  'WEAPON': 'ОРУЖИЕ',
  'GADGETS': 'ГАДЖЕТЫ',
  'GADGET': 'ГАДЖЕТ',
  'MAPS': 'КАРТЫ',
  'MAP': 'КАРТА',
  'MODES': 'РЕЖИМЫ',
  'MODE': 'РЕЖИМ',
  'SPECIALIZATIONS': 'СПЕЦИАЛИЗАЦИИ',
  'SPECIALIZATION': 'СПЕЦИАЛИЗАЦИЯ',
  'CLASSES': 'КЛАССЫ',
  'CLASS': 'КЛАСС',
  'STORE': 'МАГАЗИН',
  'EVENT': 'СОБЫТИЕ',
  'AUDIO': 'ЗВУК',
  'COSMETICS': 'КОСМЕТИКА',
  'SOCIAL': 'СОЦИАЛЬНОЕ',
  'STABILITY': 'СТАБИЛЬНОСТЬ',
  'VISUALS': 'ГРАФИКА',
  'PERFORMANCE': 'ПРОИЗВОДИТЕЛЬНОСТЬ',
  'GAMEPLAY': 'ГЕЙМПЛЕЙ',
  'UI': 'ИНТЕРФЕЙС',
  'TWITCH': 'TWITCH',
  'NETWORKING': 'СЕТЬ',
  'MATCHMAKING': 'ПОДБОР ИГР',
  'MELEE': 'БЛИЖНИЙ БОЙ',
  'RANGED': 'ДАЛЬНИЙ БОЙ',
  'ARENA CARRIABLES': 'ПРЕДМЕТЫ АРЕНЫ',
  'GAME MODES': 'РЕЖИМЫ ИГРЫ',
  'ARCHETYPES': 'АРХЕТИПЫ',
  'WEAPONS - MELEE': 'ОРУЖИЕ — БЛИЖНИЙ БОЙ',
  'WEAPONS - RANGED': 'ОРУЖИЕ — ДАЛЬНИЙ БОЙ',
};

/// Переводит заголовок раздела, сохраняя имена событий и классы.
String translateHeading(String input) {
  final text = input.trim();
  if (text.isEmpty) return text;

  // «GAME UPDATE | BALANCE CHANGES» -> переводим части по отдельности.
  final parts = text.split('|');
  if (parts.length > 1) {
    return parts
        .map((part) => translateHeading(part.trim()))
        .join(' | ');
  }

  final upper = text.toUpperCase();
  // Классы и специализации не переводим.
  if (const {'LIGHT', 'MEDIUM', 'HEAVY'}.contains(upper)) return text;

  final direct = _headings[upper];
  if (direct != null) return direct;

  return text;
}

/// Заголовок патча: «Update 11.12.0» -> «Обновление 11.12.0».
String translateTitle(String input) {
  var text = input.trim();
  if (text.isEmpty) return text;

  text = text.replaceFirst(
    RegExp(r'^Store Update\s+', caseSensitive: false),
    'Обновление магазина ',
  );
  text = text.replaceFirst(
    RegExp(r'^Midseason Update\s+', caseSensitive: false),
    'Обновление середины сезона ',
  );
  text = text.replaceFirst(
    RegExp(r'^Update\s+', caseSensitive: false),
    'Обновление ',
  );
  text = text.replaceFirst(
    RegExp(r'^Hotfix\b', caseSensitive: false),
    'Хотфикс',
  );
  text = text.replaceFirstMapped(
    RegExp(r'^Season\s+(\d+)', caseSensitive: false),
    (match) => 'Сезон ${match.group(1)}',
  );
  text = text.replaceFirst(
    RegExp(r'^Patch Notes\b', caseSensitive: false),
    'Патчноуты',
  );
  text = text.replaceFirst(
    RegExp(r'\bUpcoming Fixes\b', caseSensitive: false),
    'грядущие исправления',
  );
  return text;
}

// --- Названия характеристик ------------------------------------------------

/// Словарь терминов. Порядок важен: сначала длинные фразы.
const List<List<String>> _statTerms = [
  ['time to kill', 'время до убийства'],
  ['rate of fire', 'скорострельность'],
  ['damage per shot', 'урон за выстрел'],
  ['damage falloff', 'спад урона'],
  ['damage per pellet', 'урон за дробинку'],
  ['magazine size', 'размер магазина'],
  ['reload speed', 'скорость перезарядки'],
  ['reload time', 'время перезарядки'],
  ['effective range', 'эффективная дальность'],
  ['movement speed', 'скорость передвижения'],
  ['placement distance', 'дистанция установки'],
  ['deploy time', 'время установки'],
  ['charge time', 'время зарядки'],
  ['swap time', 'время смены'],
  ['lunge distance', 'дистанция рывка'],
  ['base health', 'базовое здоровье'],
  ['max health', 'максимальное здоровье'],
  ['environmental health', 'прочность окружения'],
  ['hit box', 'хитбокс'],
  ['flash intensity', 'интенсивность вспышки'],
  ['spawn preview', 'предпросмотр появления'],
  ['respawn time', 'время возрождения'],
  ['healing per shot', 'лечение за выстрел'],
  ['projectile speed', 'скорость снаряда'],
  ['fire rate', 'скорострельность'],
  ['cooldown', 'кулдаун'],
  ['reload', 'перезарядка'],
  ['magazine', 'магазин'],
  ['capacity', 'ёмкость'],
  ['ammo', 'патроны'],
  ['rounds', 'патроны'],
  ['damage', 'урон'],
  ['spread', 'разброс'],
  ['recoil', 'отдача'],
  ['falloff', 'спад урона'],
  ['range', 'дальность'],
  ['radius', 'радиус'],
  ['speed', 'скорость'],
  ['duration', 'длительность'],
  ['healing', 'лечение'],
  ['heal', 'лечение'],
  ['points', 'очки'],
  ['projectiles', 'снаряды'],
  ['projectile', 'снаряд'],
  ['distance', 'дистанция'],
  ['delay', 'задержка'],
  ['charge', 'заряд'],
  ['cost', 'стоимость'],
  ['armor', 'броня'],
  ['resistance', 'сопротивление'],
  ['accuracy', 'точность'],
  ['amount', 'количество'],
  ['count', 'количество'],
  ['shots', 'выстрелы'],
  ['shot', 'выстрел'],
  ['targets', 'цели'],
  ['target', 'цель'],
  ['players', 'игроки'],
  ['player', 'игрок'],
  ['teammates', 'союзники'],
  ['enemies', 'противники'],
  ['intensity', 'интенсивность'],
  ['threshold', 'порог'],
  ['flash', 'вспышка'],
  ['smoke', 'дым'],
  ['turrets', 'турели'],
  ['turret', 'турель'],
  ['trap', 'ловушка'],
  ['mine', 'мина'],
  ['shield', 'щит'],
  ['gateway', 'портал'],
  ['respawn', 'возрождение'],
  ['vault', 'хранилище'],
  ['spawn', 'появление'],
  ['width', 'ширина'],
  ['height', 'высота'],
  ['size', 'размер'],
  ['time', 'время'],
  // Модификаторы перед показателем: «max placement distance».
  ['maximum', 'макс.'],
  ['max', 'макс.'],
  ['minimum', 'мин.'],
  ['min', 'мин.'],
];

final Set<String> _termKeys = _statTerms.map((pair) => pair[0]).toSet();

const Set<String> _modifiers = {'max', 'maximum', 'min', 'minimum'};

/// Латиница, которая допустима в русском названии характеристики.
const Set<String> _allowedLatin = {'hp', 'ttk', 'dps', 'vfx', 'ui', 'fps', 'ping', 'xp'};

/// Родительный падеж для конструкции «X of Y»: «duration of smoke» -> «длительность дыма».
const Map<String, String> _genitive = {
  'дым': 'дыма',
  'урон': 'урона',
  'здоровье': 'здоровья',
  'скорость': 'скорости',
  'лечение': 'лечения',
  'дальность': 'дальности',
  'радиус': 'радиуса',
  'щит': 'щита',
  'турель': 'турели',
  'турели': 'турелей',
  'ловушка': 'ловушки',
  'мина': 'мины',
  'заряд': 'заряда',
  'время': 'времени',
  'магазин': 'магазина',
  'возрождение': 'возрождения',
  'появление': 'появления',
  'хранилище': 'хранилища',
  'цель': 'цели',
  'цели': 'целей',
  'игрок': 'игрока',
  'игроки': 'игроков',
  'противники': 'противников',
  'союзники': 'союзников',
  'выстрел': 'выстрела',
  'выстрелы': 'выстрелов',
  'очки': 'очков',
  'снаряд': 'снаряда',
  'снаряды': 'снарядов',
  'ёмкость': 'ёмкости',
  'патроны': 'патронов',
  'дистанция': 'дистанции',
  'броня': 'брони',
  'сопротивление': 'сопротивления',
  'точность': 'точности',
  'количество': 'количества',
  'размер': 'размера',
  'ширина': 'ширины',
  'высота': 'высоты',
  'задержка': 'задержки',
  'стоимость': 'стоимости',
  'разброс': 'разброса',
  'отдача': 'отдачи',
  'интенсивность': 'интенсивности',
  'порог': 'порога',
  'вспышка': 'вспышки',
  'портал': 'портала',
  'движение': 'движения',
  'перезарядка': 'перезарядки',
  'кулдаун': 'кулдауна',
  'длительность': 'длительности',
  'установка': 'установки',
  'зарядка': 'зарядки',
  'смена': 'смены',
  'рывок': 'рывка',
  'прочность': 'прочности',
  'хитбокс': 'хитбокса',
  'предпросмотр': 'предпросмотра',
  'скорострельность': 'скорострельности',
};

/// Переводит название характеристики, не трогая имена предметов.
///
/// Словарный перевод применяется только к фразам, которые он покрывает
/// целиком. Если после замены остались английские слова, возвращается
/// исходная строка — лучше показать оригинал, чем «Длительность of дым».
String translateStatName(String input) {
  final text = input.trim();
  if (text.isEmpty) return text;
  if (!RegExp(r'[A-Za-z]').hasMatch(text)) return text;

  final terms = detectProperNames(text);
  final protectedText = protectTerms(text, terms);

  // «Duration of Smoke» переводим сразу в родительном падеже.
  final ofMatch = RegExp(r'^(.*?)\s+of\s+(.+)$', caseSensitive: false)
      .firstMatch(protectedText);
  if (ofMatch != null) {
    final left = _translateWords(ofMatch.group(1)!);
    final right = _translateWords(ofMatch.group(2)!);
    if (left != null && right != null && !right.contains(' ')) {
      final genitive = _genitive[right.toLowerCase()];
      if (genitive != null) {
        return _restore('$left $genitive', terms);
      }
    }
  }

  final direct = _translateWords(protectedText);
  if (direct != null) return _restore(direct, terms);

  return input;
}

/// Переводит фразу по словарю. `null`, если словарь не знает фразу целиком.
String? _translateWords(String mixed) {
  final lookup = _normalizeForLookup(mixed);
  if (lookup.isEmpty) return null;

  // Фраза считается известной, только если это словарная статья целиком
  // (возможно, с модификатором «max»/«min» впереди). Иначе переводить
  // по словам нельзя: получится «урон сопротивление» вместо
  // «сопротивление урону» — такие строки отдаём машинному переводу.
  final words = lookup.split(' ');
  final core = words.length > 1 && _modifiers.contains(words.first)
      ? words.sublist(1).join(' ')
      : lookup;
  if (!_termKeys.contains(core)) return null;

  var result = mixed;

  for (final pair in _statTerms) {
    final re = RegExp(r'\b' + RegExp.escape(pair[0]) + r'\b', caseSensitive: false);
    result = result.replaceAll(re, pair[1]);
  }

  result = result.replaceAll(RegExp(r"'s\b"), '');
  result = result.replaceAll(RegExp(r'\bthe\b', caseSensitive: false), '');
  result = result.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  result = result.replaceAll(RegExp(r'^[,\s]+|[,\s]+$'), '');

  final leftover = RegExp(r'[A-Za-z]{2,}')
      .allMatches(result)
      .map((m) => m.group(0)!.toLowerCase())
      .any((word) => !_allowedLatin.contains(word));
  if (leftover || result.isEmpty) return null;

  return result;
}

/// Приводит фразу к виду для сверки со словарём: без маркеров имён,
/// притяжательных «'s», артиклей и знаков препинания.
String _normalizeForLookup(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'⟦\s*\d+\s*⟧'), ' ')
      .replaceAll(RegExp(r"'s\b"), '')
      .replaceAll(RegExp(r'\bthe\b'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9\s.-]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _restore(String mixed, List<String> terms) {
  return restoreTerms(mixed, terms)
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();
}
