import 'package:finals_notes/l10n/glossary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Названия характеристик', () {
    test('простые термины', () {
      expect(translateStatName('cooldown'), 'кулдаун');
      expect(translateStatName('damage'), 'урон');
      expect(translateStatName('magazine size'), 'размер магазина');
    });

    test('фразы переводятся целиком, а не по словам', () {
      expect(translateStatName('placement distance'), 'дистанция установки');
      expect(translateStatName('max placement distance'), 'макс. дистанция установки');
    });

    test('конструкция «X of Y» переводится в родительном падеже', () {
      expect(translateStatName('Duration of Smoke'), 'длительность дыма');
      expect(translateStatName('Amount of healing'), 'количество лечения');
    });

    test('незнакомая фраза остаётся оригиналом, а не гибридом', () {
      const phrase =
          'Delay untill health regeneration kicks in after last taking damage';
      expect(translateStatName(phrase), phrase);
      expect(translateStatName('damage resistance'), 'damage resistance');
    });

    test('имя предмета остаётся как в игре', () {
      final result = translateStatName("the ARN-220's magazine size");
      expect(result, contains('ARN-220'));
      expect(result, contains('размер магазина'));
    });

    test('словарь важнее машинного перевода', () {
      expect(displayStatName('damage', {'damage': 'повреждать'}), 'Урон');
      expect(
        displayStatName(
          'reload loop animation',
          {'reload loop animation': 'анимация цикла перезагрузки'},
        ),
        'Анимация цикла перезарядки',
      );
      expect(
        displayStatName('smoke duration', {'smoke duration': 'продолжительность курения'}),
        'Длительность дыма',
      );
    });

    test('подпись для интерфейса без хвоста прозы и с заглавной', () {
      expect(
        displayStatName(
          'Dome Shield health increased',
          {'Dome Shield health increased': 'Здоровье купольного щита увеличено.'},
        ),
        'Здоровье купольного щита',
      );
      expect(displayStatName('base damage'), 'Базовый урон');
    });
  });

  group('Заголовки', () {
    test('составной заголовок', () {
      expect(
        translateHeading('GAME UPDATE | BALANCE CHANGES'),
        'ОБНОВЛЕНИЕ ИГРЫ | ИЗМЕНЕНИЯ БАЛАНСА',
      );
    });

    test('классы не переводятся', () {
      expect(translateHeading('Light'), 'Light');
      expect(translateHeading('Heavy'), 'Heavy');
    });

    test('неизвестный заголовок остаётся как есть', () {
      expect(translateHeading('SPONSOR SHOWDOWN'), 'SPONSOR SHOWDOWN');
    });
  });

  group('Заголовки патчей', () {
    test('Update', () {
      expect(translateTitle('Update 11.12.0'), 'Обновление 11.12.0');
    });

    test('Store Update', () {
      expect(translateTitle('Store Update 11.14.0'), 'Обновление магазина 11.14.0');
    });

    test('Hotfix', () {
      expect(translateTitle('HOTFIX & UPCOMING FIXES'), 'Хотфикс & грядущие исправления');
    });
  });

  group('Защита имён собственных', () {
    test('маркеры возвращают исходное название', () {
      const text = 'Nerfed the Grappling Hook range in Monaco';
      final terms = detectProperNames(text);
      expect(terms, contains('Grappling Hook'));
      expect(terms, contains('Monaco'));

      final protectedText = protectTerms(text, terms);
      expect(protectedText, isNot(contains('Monaco')));

      final restored = restoreTerms(protectedText, terms);
      expect(restored, text);
    });
  });
}
