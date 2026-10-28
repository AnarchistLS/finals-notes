import 'package:finals_notes/parser/patch_parser.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _item(String body) => {
      'id': 'p1',
      'fullUrl': '/patchnotes/test',
      'title': 'Update 1.0',
      'body': body,
      'publishOn': DateTime.utc(2026, 10, 24).millisecondsSinceEpoch,
    };

void main() {
  group('Вложенные списки', () {
    test('подпункт не приклеивается к родительскому пункту', () {
      final patch = parsePatchItem(_item('''
        <h2>WEAPONS</h2>
        <p><strong>ARN-220</strong></p>
        <ul>
          <li>
            <p>Decreased the duration of empty and tactical reload from 0.68s to 0.62s</p>
            <ul>
              <li>Decreased reload loop animation from 0.88s to 0.8s</li>
            </ul>
          </li>
        </ul>
      '''));

      final lines = patch.sections
          .expand((section) => section.blocks)
          .where((block) => block.kind == 'li')
          .map((block) => block.text)
          .toList();

      expect(lines, hasLength(2));
      expect(lines.first, 'Decreased the duration of empty and tactical reload from 0.68s to 0.62s');
      expect(lines.last, 'Decreased reload loop animation from 0.88s to 0.8s');
      expect(lines.any((line) => line.contains('reloadDecrease')), isFalse);

      final stats = patch.stats.map((change) => change.stat).toList();
      expect(stats, contains('duration of empty and tactical reload'));
      expect(stats, contains('reload loop animation'));
    });

    test('пункт с вложенным списком сохраняет свой текст', () {
      final patch = parsePatchItem(_item('''
        <h2>GADGETS</h2>
        <p><strong>Flashbang</strong></p>
        <ul>
          <li>
            Increased maximum flash duration from 4.5s to 5s
            <ul>
              <li>Increased minimum flash duration from 1.5s to 2s</li>
            </ul>
          </li>
        </ul>
      '''));

      final stats = patch.stats.map((change) => change.stat).toList();
      expect(stats, contains('maximum flash duration'));
      expect(stats, contains('minimum flash duration'));
    });
  });
}
