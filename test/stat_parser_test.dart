import 'package:finals_notes/models/models.dart';
import 'package:finals_notes/parser/patch_parser.dart';
import 'package:finals_notes/parser/stat_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Полярность показателей', () {
    test('кулдаун: меньше — лучше', () {
      expect(lowerIsBetter('cooldown'), isTrue);
    });

    test('урон: больше — лучше', () {
      expect(lowerIsBetter('damage per shot'), isFalse);
    });

    test('время перезарядки важнее слова duration', () {
      expect(lowerIsBetter('duration of the reload animation'), isTrue);
    });

    test('длительность невидимости: дольше — лучше', () {
      expect(lowerIsBetter('duration of invisibility'), isFalse);
    });
  });

  group('Разбор изменений', () {
    StatChange one(String text) {
      final result = parseStatChanges(text, category: 'Gadgets', item: 'Zipline');
      expect(result, hasLength(1), reason: text);
      return result.first;
    }

    test('снижение кулдауна — усиление', () {
      final change = one('Decreased cooldown from 37s to 30s');
      expect(change.stat, 'cooldown');
      expect(change.before, 37);
      expect(change.after, 30);
      expect(change.unit, 's');
      expect(change.impact, Impact.buff);
      expect(change.deltaText, '−7s');
    });

    test('рост дальности — усиление', () {
      final change = one('Increased max placement distance from 40m to 50m');
      expect(change.stat, 'max placement distance');
      expect(change.impact, Impact.buff);
    });

    test('обойма 30 -> 28 — ослабление', () {
      final change = one('Reduced magazine size from 30 to 28');
      expect(change.before, 30);
      expect(change.after, 28);
      expect(change.impact, Impact.nerf);
    });

    test('рост кулдауна — ослабление', () {
      final change = one('Increased cooldown from 30s to 45s');
      expect(change.impact, Impact.nerf);
    });

    test('время перезарядки вниз — усиление', () {
      final change = one('Decreased duration of the reload animation from 2.2s to 1.75s');
      expect(change.impact, Impact.buff);
    });

    test('время невидимости вниз — ослабление', () {
      final change = one('Decreased the duration of invisibility on the user from 6s to 5s');
      expect(change.impact, Impact.nerf);
    });

    test('урон вниз — ослабление', () {
      final change = one('Decreased H+ Infuser healing per shot from 14 to 11.');
      expect(change.impact, Impact.nerf);
    });

    test('текст без чисел не даёт изменений', () {
      expect(
        parseStatChanges('Fixed a rare crash on the podium', category: 'Stability', item: ''),
        isEmpty,
      );
    });
  });

  group('Версия патча', () {
    test('из заголовка', () {
      expect(
        detectVersion(title: 'Update 11.12.0', slug: '/patchnotes/11-120', bodyText: ''),
        '11.12.0',
      );
    });

    test('из слага вида 12-01', () {
      expect(
        detectVersion(title: 'HOTFIX & UPCOMING FIXES', slug: '/patchnotes/12-01', bodyText: ''),
        '12.0.1',
      );
    });
  });
}
