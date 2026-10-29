/// Тесты сборщика «гифок» для канала: разбор HLS-мастер-плейлиста
/// Squarespace и выбор самого лёгкого варианта.
import 'package:finals_notes/telegram/clip.dart';
import 'package:flutter_test/flutter_test.dart';

/// Реальный мастер-плейлист со страницы Store Update (значения подписей
/// обезличены, формат — как выдаёт видео-CDN Squarespace).
const String masterPlaylist = '''
#EXTM3U
#EXT-X-VERSION:7


#EXT-X-STREAM-INF:BANDWIDTH=1577158,CODECS="avc1.64001e,mp4a.40.2",RESOLUTION=988x360
https://video.squarespace-cdn.com/content/v1/62d66fa29e72c560f8efc020/780811c8-c6fd-449d-8eeb-eb202ac770e3/segments/mpegts-h264-988:360.m3u8?Expires=1793329119&Signature=ABC
#EXT-X-STREAM-INF:BANDWIDTH=3100098,CODECS="avc1.640032,mp4a.40.2",RESOLUTION=2962x1080
https://video.squarespace-cdn.com/content/v1/62d66fa29e72c560f8efc020/780811c8-c6fd-449d-8eeb-eb202ac770e3/segments/mpegts-h264-2962:1080.m3u8?Expires=1793329119&Signature=DEF
''';

void main() {
  group('parseMasterPlaylist', () {
    test('читает оба варианта Squarespace', () {
      final renditions = parseMasterPlaylist(masterPlaylist);
      expect(renditions, hasLength(2));
      expect(renditions[0].url, contains('mpegts-h264-988:360.m3u8'));
      expect(renditions[0].url, contains('Signature=ABC'));
      expect(renditions[0].width, 988);
      expect(renditions[0].height, 360);
      expect(renditions[0].bandwidth, 1577158);
      expect(renditions[1].height, 1080);
    });

    test('пустой плейлист — пустой список', () {
      expect(parseMasterPlaylist('#EXTM3U\n'), isEmpty);
    });
  });

  group('pickSmallestRendition', () {
    test('выбирает 360p для «гифки»', () {
      final renditions = parseMasterPlaylist(masterPlaylist);
      final picked = pickSmallestRendition(renditions);
      expect(picked, isNotNull);
      expect(picked!.height, 360);
    });

    test('fallback на битрейт, если разрешения нет', () {
      final picked = pickSmallestRendition(const [
        VideoRendition('high', bandwidth: 3100098),
        VideoRendition('low', bandwidth: 900000),
      ]);
      expect(picked!.url, 'low');
    });

    test('пустой список — null', () {
      expect(pickSmallestRendition(const []), isNull);
    });
  });
}
