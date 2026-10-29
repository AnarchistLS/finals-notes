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

  group('Видео-«гифки» Squarespace', () {
    // Упрощённый фрагмент реального блока Store Update 11.11.0.
    const videoBlock = '''
      <h2>STORE | FIELD CONTROL SET</h2>
      <p>Check, one-two, one-two.. Are you receiving?</p>
      <div class="sqs-block video-block">
        <div class="sqs-native-video"
             data-config-settings="{&quot;autoPlay&quot;:true,&quot;loop&quot;:true,&quot;muted&quot;:true}"
             data-config-video="{&quot;systemDataSourceType&quot;:&quot;mp4&quot;,&quot;alexandriaUrl&quot;:&quot;https://video.squarespace-cdn.com/content/v1/62d66fa29e72c560f8efc020/780811c8-c6fd-449d-8eeb-eb202ac770e3/{variant}&quot;,&quot;durationSeconds&quot;:13.48,&quot;id&quot;:&quot;6ab267b806edba34cf21f724&quot;,&quot;systemDataVariants&quot;:&quot;2962:1080,988:360&quot;}">
        </div>
      </div>
      <p>Grab the Retro A.C.E. Set for your Multi-Device.</p>
    ''';

    test('видео превращается в блок с HLS-плейлистом', () {
      final patch = parsePatchItem(_item(videoBlock));
      final videos = patch.sections
          .expand((section) => section.blocks)
          .where((block) => block.isVideo)
          .toList();
      expect(videos, hasLength(1));
      expect(
        videos.single.url,
        'https://video.squarespace-cdn.com/content/v1/62d66fa29e72c560f8efc020/780811c8-c6fd-449d-8eeb-eb202ac770e3/playlist.m3u8',
      );
    });

    test('видео стоит в потоке между текстами, а не в конце', () {
      final patch = parsePatchItem(_item(videoBlock));
      final kinds = patch.sections
          .expand((section) => section.blocks)
          .map((block) => block.kind)
          .toList();
      expect(kinds, ['p', 'video', 'p']);
    });

    test('блок без видео-конфигурации пропускается без падения', () {
      final patch = parsePatchItem(_item('''
        <h2>EVENT PASS</h2>
        <div class="video-block"><div class="sqs-native-video"></div></div>
        <p>Generously sponsored by IVADA!</p>
      '''));
      final videos = patch.sections
          .expand((section) => section.blocks)
          .where((block) => block.isVideo)
          .toList();
      expect(videos, isEmpty);
      // Текст после «пустого» видео-блока не потерялся.
      expect(patch.sections.first.blocks.any((b) => b.kind == 'p'), isTrue);
    });
  });
}
