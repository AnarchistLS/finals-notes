import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:finals_notes/data/published.dart';
import 'package:finals_notes/models/models.dart';
import 'package:finals_notes/ui/patch_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('готовый файл Mini App', () {
    final file = File('web/data/patches_ru.json');

    test('файл собирается пайплайном и разбирается обратно', () async {
      expect(
        file.existsSync(),
        isTrue,
        reason: 'сначала: dart run tool/publish.dart',
      );

      final raw = await file.readAsString();
      final repository = PublishedRepository(
        client: MockClient((request) async => http.Response.bytes(
              utf8.encode(raw),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            )),
      );

      final snapshot = await repository.load();
      expect(snapshot, isNotNull);
      expect(snapshot!.patches, isNotEmpty);
      expect(snapshot.engine, isNotEmpty);
      expect(snapshot.patches.first.doc.title, isNotEmpty);

      final withTranslations =
          snapshot.patches.where((item) => item.translations.isNotEmpty);
      expect(withTranslations, isNotEmpty);
    });

    test('ключи переводов совпадают со строками патча', () async {
      final raw = await file.readAsString();
      final repository = PublishedRepository(
        client: MockClient((request) async => http.Response.bytes(
              utf8.encode(raw),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            )),
      );
      final snapshot = await repository.load();
      expect(snapshot, isNotNull);

      for (final item in snapshot!.patches) {
        final texts = <String>{
          if (item.doc.excerpt.isNotEmpty) item.doc.excerpt,
          for (final section in item.doc.sections) ...[
            if (section.title.isNotEmpty) section.title,
            for (final block in section.blocks)
              if (block.text.isNotEmpty) block.text,
          ],
          for (final stat in item.doc.stats) ...[stat.stat, stat.category],
        };

        for (final key in item.translations.keys) {
          expect(
            texts.contains(key),
            isTrue,
            reason: 'перевод «$key» не встречается в патче ${item.doc.version}',
          );
        }
      }
    });
  });

  testWidgets('страница патча берёт готовые переводы без сети', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final doc = _doc();
    await tester.pumpWidget(
      MaterialApp(
        home: PatchPage(
          patch: doc,
          translations: const {
            'Damage increased from 30 to 36': 'Урон увеличен с 30 до 36',
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Урон увеличен с 30 до 36'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test('в готовом файле есть свежий патч 12.1.0', () async {
    final file = File('web/data/patches_ru.json');
    final raw = await file.readAsString();
    final repository = PublishedRepository(
      client: MockClient((request) async => http.Response.bytes(
            utf8.encode(raw),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          )),
    );
    final snapshot = await repository.load();
    expect(snapshot, isNotNull, reason: 'готовый файл не разбирается');
    final item = snapshot!.patches
        .where((p) => p.doc.version == '12.1.0')
        .firstOrNull;
    expect(item, isNotNull, reason: 'в файле нет патча 12.1.0');

    // Страница патча строится из этих же данных: блок баланса и его
    // готовый перевод должны быть в файле (Translocator, CB-01).
    final texts = item!.doc.sections
        .fold(<String>{}, (acc, s) => acc..addAll(s.blocks.map((b) => b.text)));
    expect(
      texts.contains('Decreased max range from 70m to 50m'),
      isTrue,
      reason: 'в 12.1.0 нет блока баланса транслокатора',
    );
    expect(
      item.translations['Decreased max range from 70m to 50m'],
      equals('Максимальная дальность действия уменьшена с 70 м до 50 м'),
    );
    expect(item.translations['Translocator'], isNotNull);
    expect(item.doc.stats.length, equals(4));
  });
}

// Вспомогательное: тестовые данные.
PatchDoc _doc() => PatchDoc(
      id: 'test-1',
      slug: 'test-1',
      title: 'Update 12.0.1',
      version: '12.0.1',
      date: DateTime(2026, 10, 21),
      url: 'https://example.com/patch',
      excerpt: '',
      cover: null,
      images: const [],
      sections: const [
        PatchSection(
          title: 'BALANCE CHANGES',
          blocks: [
            DocBlock(kind: 'p', text: 'Damage increased from 30 to 36'),
          ],
        ),
      ],
      stats: const [],
    );
