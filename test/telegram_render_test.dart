import 'package:finals_notes/models/models.dart';
import 'package:finals_notes/telegram/render.dart';
import 'package:flutter_test/flutter_test.dart';

PatchDoc _patch({
  List<StatChange> stats = const [],
  List<PatchSection> sections = const [],
  String title = 'Update 12.0.0',
  String excerpt = '',
}) {
  return PatchDoc(
    id: 'p1',
    slug: '/patchnotes/12-0-0',
    title: title,
    version: '12.0.0',
    date: DateTime(2026, 10, 24),
    url: 'https://www.reachthefinals.com/patchnotes/12-0-0',
    excerpt: excerpt,
    cover: null,
    images: const [],
    sections: sections,
    stats: stats,
  );
}

StatChange _stat({
  required String stat,
  required double before,
  required double after,
  required Impact impact,
  String item = '',
  String category = 'WEAPONS',
}) {
  return StatChange(
    category: category,
    item: item,
    stat: stat,
    before: before,
    after: after,
    unit: '',
    impact: impact,
    raw: '$stat $before -> $after',
  );
}

void main() {
  test('HTML экранируется, чтобы Telegram не ругался на разметку', () {
    expect(escapeHtml('a & b < c > d'), 'a &amp; b &lt; c &gt; d');
  });

  test('дайджест: версия, дата, счётчики, стрелки и ссылка', () {
    final patch = _patch(
      excerpt: 'Big changes are coming.',
      stats: [
        _stat(stat: 'Damage', before: 24, after: 26, impact: Impact.buff, item: 'ARN-220'),
        _stat(stat: 'Spread', before: 12, after: 14, impact: Impact.nerf, item: 'Model 1887'),
      ],
    );

    final messages = renderDigest(
      patch,
      translations: {
        'Big changes are coming.': 'Грядут большие изменения.',
        'Damage': 'Урон',
        'Spread': 'Разброс',
      },
    );

    expect(messages, hasLength(1));
    final text = messages.single;
    expect(text, contains('🔥 <b>Обновление 12.0.0</b>'));
    expect(text, contains('24.10.2026'));
    expect(text, contains('▲ 1 улучшение · ▼ 1 ослабление'));
    expect(text, contains('<b>ОРУЖИЕ</b>'));
    expect(text, contains('<b>ARN-220</b>'));
    // Словарь важнее машинного перевода: «damage» — это «урон».
    expect(text, contains('▲ урон: 24 → 26'));
    expect(text, contains('▼ разброс: 12 → 14'));
    expect(text, contains('Грядут большие изменения.'));
    expect(text, contains('https://www.reachthefinals.com/patchnotes/12-0-0'));
    expect(text.length, lessThanOrEqualTo(telegramMessageLimit));
  });

  test('большой дайджест режется на сообщения, не теряя изменения', () {
    final stats = [
      for (var i = 0; i < 200; i++)
        _stat(
          stat: 'Damage',
          before: i.toDouble(),
          after: i + 1.0,
          impact: Impact.buff,
          item: 'Weapon number $i',
        ),
    ];

    final messages = renderDigest(
      _patch(stats: stats),
      translations: {'Damage': 'Урон'},
      maxStats: 1000,
    );

    expect(messages.length, greaterThan(1));
    for (final message in messages) {
      expect(message.length, lessThanOrEqualTo(telegramMessageLimit));
    }
    expect(messages.join('\n'), contains('Weapon number 199'));
    expect(messages.last, contains('…продолжение'));
  });

  test('полный текст: разделы, пункты и экранирование', () {
    final patch = _patch(
      sections: [
        const PatchSection(
          title: 'BALANCE CHANGES',
          blocks: [
            DocBlock(kind: 'h3', text: 'WEAPONS'),
            DocBlock(kind: 'b', text: 'ARN-220'),
            DocBlock(kind: 'li', text: 'Damage increased from 24 to 26.'),
            DocBlock(kind: 'p', text: 'Fixed <script> tags in the UI.'),
            DocBlock(kind: 'img', url: 'https://example.com/a.png'),
          ],
        ),
      ],
    );

    final messages = renderFull(
      patch,
      translations: {
        'Damage increased from 24 to 26.': 'Урон увеличен с 24 до 26.',
        'Fixed <script> tags in the UI.': 'Починили теги <script> в интерфейсе.',
      },
    );

    final text = messages.single;
    expect(text, contains('<b>ИЗМЕНЕНИЯ БАЛАНСА</b>'));
    expect(text, contains('<b>ОРУЖИЕ</b>'));
    expect(text, contains('<b>ARN-220</b>'));
    expect(text, contains('• Урон увеличен с 24 до 26.'));
    expect(text, contains('&lt;script&gt;'));
    expect(text, isNot(contains('<script>')));
    expect(text, isNot(contains('example.com/a.png')));
  });

  test('длинный текст режется по словам, а не посередине', () {
    final long = List.filled(1200, 'слово').join(' ');
    final messages = splitMessageText(long, limit: 200);

    expect(messages.length, greaterThan(1));
    for (final message in messages) {
      expect(message.length, lessThanOrEqualTo(200));
      expect(message, isNot(startsWith(' ')));
      expect(message, isNot(endsWith(' ')));
    }
    expect(messages.join(' '), long);
  });

  test('без изменений дайджест показывает пункты разделов', () {
    final patch = _patch(
      sections: const [
        PatchSection(title: 'BUG FIXES', blocks: [DocBlock(kind: 'li', text: 'Fixed a crash.')]),
        PatchSection(title: 'KNOWN ISSUES', blocks: [DocBlock(kind: 'li', text: 'Sound bug.')]),
      ],
    );

    final text = renderDigest(patch).single;
    expect(text, contains('<b>ИСПРАВЛЕНИЯ</b>'));
    expect(text, contains('• Fixed a crash.'));
    expect(text, contains('<b>ИЗВЕСТНЫЕ ПРОБЛЕМЫ</b>'));
    expect(text, contains('• Sound bug.'));
  });
}
