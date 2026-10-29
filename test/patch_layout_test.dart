import 'package:finals_notes/models/models.dart';
import 'package:finals_notes/ui/patch_layout.dart';
import 'package:flutter_test/flutter_test.dart';

/// Синтетический патч с реальной структурой статьи: одна секция,
/// подразделы-абзацы «PIPE | ХЕДИНГ», h3-категории, b-предметы, li-пункты.
PatchDoc _patch() {
  final blocks = <DocBlock>[
    DocBlock(kind: 'p', text: '2026.10.30'),
    DocBlock(kind: 'b', text: 'BOO!'),
    DocBlock(kind: 'p', text: 'A mysterious fog has taken over the Arena.'),
    DocBlock(kind: 'p', text: 'STORE | REVENANT COUNTESS'),
    DocBlock(kind: 'p', text: 'Spooky cosmetics arrive.'),
    DocBlock(kind: 'p', text: 'GAME UPDATE | BALANCE CHANGES'),
    // Категории в «неправильном» порядке, чтобы проверить сортировку:
    // окружение, оружие, классы.
    DocBlock(kind: 'h3', text: 'Arena Carriables'),
    DocBlock(kind: 'b', text: 'Powder Canisters'),
    DocBlock(kind: 'li', text: 'Barrels health increased from 100 to 150.'),
    DocBlock(kind: 'h3', text: 'Weapons - Melee'),
    DocBlock(kind: 'b', text: 'Dagger'),
    DocBlock(kind: 'li', text: 'Damage increased from 40 to 42.'),
    DocBlock(kind: 'h3', text: 'Archetypes'),
    DocBlock(kind: 'b', text: 'Light'),
    DocBlock(kind: 'li', text: 'Health decreased from 150 to 120.'),
    DocBlock(kind: 'b', text: 'General'),
    DocBlock(kind: 'li', text: 'Speed increased by 2%.'),
    // Пункт без числового изменения — останется текстом.
    DocBlock(kind: 'p', text: 'Dev Note: balance pass continues.'),
    DocBlock(kind: 'p', text: 'GAME UPDATE | CONTENT & BUG FIXES'),
    DocBlock(kind: 'h3', text: 'Animation'),
    DocBlock(kind: 'li', text: 'Fixed an entrance animation issue.'),
    DocBlock(kind: 'h3', text: 'VFX'),
    DocBlock(kind: 'li', text: 'Improved lighting on Seoul.'),
    DocBlock(kind: 'li', text: 'Fixed a smoke grenade artifact.'),
    DocBlock(kind: 'p', text: 'GAME INFO | GYRO UPDATE'),
    DocBlock(kind: 'li', text: 'We are working on a native gyro solution.'),
  ];

  StatChange stat({
    required String category,
    required String item,
    required String statName,
    required double before,
    required double after,
    required Impact impact,
    required String raw,
  }) {
    return StatChange(
      category: category,
      item: item,
      stat: statName,
      before: before,
      after: after,
      unit: '',
      impact: impact,
      raw: raw,
    );
  }

  return PatchDoc(
    id: 'p1',
    slug: '/patchnotes/12-2-0',
    title: 'Update 12.2.0',
    version: '12.2.0',
    date: DateTime(2026, 10, 30),
    url: 'https://www.reachthefinals.com/patchnotes/12-2-0',
    excerpt: '',
    cover: null,
    images: const [],
    sections: [PatchSection(title: 'Update', blocks: blocks)],
    stats: [
      stat(
        category: 'Arena Carriables',
        item: 'Powder Canisters',
        statName: 'Health',
        before: 100,
        after: 150,
        impact: Impact.buff,
        raw: 'Barrels health increased from 100 to 150.',
      ),
      stat(
        category: 'Weapons - Melee',
        item: 'Dagger',
        statName: 'Damage',
        before: 40,
        after: 42,
        impact: Impact.buff,
        raw: 'Damage increased from 40 to 42.',
      ),
      stat(
        category: 'Light',
        item: 'Light',
        statName: 'Health',
        before: 150,
        after: 120,
        impact: Impact.nerf,
        raw: 'Health decreased from 150 to 120.',
      ),
      stat(
        category: 'Archetypes',
        item: 'General',
        statName: 'Speed',
        before: 10,
        after: 12,
        impact: Impact.buff,
        raw: 'Speed increased by 2%.',
      ),
      // Числовое изменение без привязки к статье — упадёт в « loose».
      stat(
        category: 'Gadgets',
        item: 'Zipline',
        statName: 'Duration',
        before: 10,
        after: 12,
        impact: Impact.buff,
        raw: 'Zipline duration changed from 10 to 12.',
      ),
    ],
  );
}

void main() {
  test('группы идут в порядке: обновление, баланс, исправления', () {
    final groups = layoutPatchDoc(_patch());
    expect(groups, hasLength(3));
    expect(groups[0].title, kNewsTitle);
    expect(groups[1].title, kBalanceTitle);
    expect(groups[2].title, kBugfixTitle);
  });

  test('в «Об обнове» заголовки-части становятся подзаголовками', () {
    final news = layoutPatchDoc(_patch())[0];
    final headings = [
      for (final b in news.blocks)
        if (b.kind == 'h3') b.text,
    ];
    expect(headings.first, 'STORE | REVENANT COUNTESS');
    // «GAME INFO | GYRO UPDATE» — тоже новости, влиты в общий раздел.
    expect(headings, contains('GAME INFO | GYRO UPDATE'));
  });

  test('баланс: классы, затем оружие, затем окружение', () {
    final balance = layoutPatchDoc(_patch())[1];
    final h3 = [
      for (final b in balance.blocks)
        if (b.kind == 'h3') b.text,
    ];
    expect(h3, ['Archetypes', 'Weapons - Melee', 'Arena Carriables']);

    // Внутри классов: General вначале, потом Heavy/Light по порядку весов.
    final items = [
      for (final b in balance.blocks)
        if (b.kind == 'b') b.text,
    ];
    expect(items, ['General', 'Light', 'Dagger', 'Powder Canisters']);
  });

  test('карточки прикреплены к своим предметам, только один раз', () {
    final balance = layoutPatchDoc(_patch())[1];
    final generalPos =
        balance.blocks.indexWhere((b) => b.kind == 'b' && b.text == 'General');
    final generalTiles = balance.itemStats[generalPos];
    // «General» в Archetypes — его изменение прикреплено здесь.
    expect(generalTiles, isNotNull);
    expect(generalTiles, isNotEmpty);
    // …а карточки конкретных предметов — в своих категориях.
    final daggerPos =
        balance.blocks.indexWhere((b) => b.kind == 'b' && b.text == 'Dagger');
    final dagger = balance.itemStats[daggerPos]!;
    expect(dagger.single.item, 'Dagger');
  });

  test('исправления содержат только fixed-пункты, пустые категории спрятаны',
      () {
    final bugfix = layoutPatchDoc(_patch())[2];
    final texts = [
      for (final b in bugfix.blocks)
        if (b.kind != 'h3' && b.kind != 'b') b.text,
    ];
    for (final text in texts) {
      expect(_hasFixWord(text), isTrue, reason: text);
    }
    // «Improved lighting on Seoul.» пропало, а категория VFX осталась
    // делать? Нет: у неё остался fixed-пункт после него.
    expect(
      texts,
      contains('Fixed an entrance animation issue.'),
    );
    final h3 = [
      for (final b in bugfix.blocks)
        if (b.kind == 'h3') b.text,
    ];
    expect(h3, contains('VFX'));
  });

  test('статы без привязки попадают в loose', () {
    final loose = looseStats(_patch(), layoutPatchDoc(_patch()));
    expect(loose, hasLength(1));
    expect(loose.single.item, 'Zipline');
  });
}

bool _hasFixWord(String text) =>
    RegExp(r'\bfixed\b|\bno longer\b', caseSensitive: false).hasMatch(text) ||
    text.contains('исправл') ||
    text.contains('починил');
