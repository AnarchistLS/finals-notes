/// Собирает «гифку» для Telegram-канала из видео-блока патча.
///
/// На сайте THE FINALS «GIF-анимации» — это зацикленные MP4 без звука,
/// которые Squarespace раздаёт как HLS (`playlist.m3u8` с вариантами
/// качества). Мастер-плейлист отдаётся без подписи, а ссылки на варианты
/// внутри него подписаны и живут часы — этого достаточно: бот собирает
/// файл в момент публикации и не кеширует его.
///
/// Из вариантов выбирается самый лёгкий (обычно 360p), ffmpeg remux'ит
/// MPEG-TS-сегменты в mp4 без перекодирования. Отдельная зависимость
/// пакета не нужна — файл отдаётся и в Mini App, и боту с тем же CDN.
///
/// Модуль чистый: только сеть и processes, без Flutter — можно тестировать.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Готов: список вариантов HLS и выбор самого лёгкого.
class VideoRendition {
  final String url;
  final int? width;
  final int? height;
  final int? bandwidth;

  const VideoRendition(this.url, {this.width, this.height, this.bandwidth});
}

/// Разбирает мастер-плейлист HLS (`#EXT-X-STREAM-INF … / url`).
///
/// Формат Squarespace:
/// ```
/// #EXT-X-STREAM-INF:BANDWIDTH=1577158,CODECS="avc1.,mp4a.",RESOLUTION=988x360
/// https://video.squarespace-cdn.com/…/{variant}.m3u8?Expires=…&Signature=…
/// ```
List<VideoRendition> parseMasterPlaylist(String body) {
  final result = <VideoRendition>[];
  final bandwidth = RegExp(r'BANDWIDTH=(\d+)');
  final resolution = RegExp(r'RESOLUTION=(\d+)x(\d+)');
  final lines = const LineSplitter().convert(body);

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (!line.startsWith('#EXT-X-STREAM-INF')) continue;
    final urlLine = i + 1 < lines.length ? lines[i + 1].trim() : '';
    if (urlLine.isEmpty || urlLine.startsWith('#')) continue;

    final bw = bandwidth.firstMatch(line)?.group(1);
    final res = resolution.firstMatch(line);
    result.add(VideoRendition(
      urlLine,
      bandwidth: bw == null ? null : int.tryParse(bw),
      width: res == null ? null : int.tryParse(res.group(1)!),
      height: res == null ? null : int.tryParse(res.group(2)!),
    ));
  }
  return result;
}

/// Самый лёгкий вариант: минимум по ширине (360p), с исправлением на
/// битрейт, если размер неизвестен. Для зацикленной «гифки» этого хватает.
VideoRendition? pickSmallestRendition(List<VideoRendition> renditions) {
  VideoRendition? best;
  for (final r in renditions) {
    if (best == null) {
      best = r;
      continue;
    }
    final rW = r.width ?? 0;
    final bW = best.width ?? 0;
    if (rW < bW || (rW == bW && (r.bandwidth ?? 0) < (best.bandwidth ?? 0))) {
      best = r;
    }
  }
  return best;
}

/// Скачивает самый лёгкий вариант, remux'ит MPEG-TS-сегменты в mp4
/// (`ffmpeg -c copy`, без перекодирования) и возвращает готовый файл.
///
/// Броски имеют смысл только на этапе сборки: вызывающая сторона
/// (`tool/bot.dart`) любую ошибку тушит и публикует пост без гифки.
Future<File> buildClip({
  required http.Client client,
  required String playlistUrl,
  required Directory outputDir,
  String ffmpegBinary = 'ffmpeg',
  int attempts = 2,
}) async {
  final renditions = await _loadMasterPlaylist(client, playlistUrl, attempts);
  final chosen = pickSmallestRendition(renditions);
  if (chosen == null) {
    throw const ClipException('в мастер-плейлисте нет вариантов');
  }

  final temp = await outputDir.create(recursive: true);
  final outPath =
      '${temp.path}${Platform.pathSeparator}clip-${DateTime.now().millisecondsSinceEpoch}.mp4';

  // Сегменты TS — сегменты h264+aac; копируем видео, звук выбрасываем
  // (Telegram-анимация всегда играет без звука).
  final result = await Process.run(ffmpegBinary, [
    '-nostdin',
    '-hide_banner',
    '-loglevel',
    'error',
    '-y',
    '-i',
    chosen.url,
    '-map',
    '0:v:0',
    '-an',
    '-c:v',
    'copy',
    '-movflags',
    '+faststart',
    outPath,
  ]).timeout(const Duration(seconds: 120));

  if (result.exitCode != 0) {
    final err = (result.stderr as String?)?.trim();
    final file = File(outPath);
    if (file.existsSync()) file.deleteSync();
    throw ClipException('ffmpeg завершился с ошибкой${err == null ? '' : ': $err'}');
  }

  final file = File(outPath);
  final size = file.existsSync() ? file.lengthSync() : 0;
  if (size <= 64 * 1024) {
    if (file.existsSync()) file.deleteSync();
    throw const ClipException('ffmpeg отдал пустой файл');
  }
  return file;
}

/// Броски [`ClipException`] — сценарий, когда бот должен тушить ошибку
/// и публиковать пост без гифки; сетевые исключения [client] проходят
/// наверх как есть.
Future<List<VideoRendition>> _loadMasterPlaylist(
  http.Client client,
  String url,
  int attempts,
) async {
  Object? lastError;
  for (var attempt = 1; attempt <= attempts; attempt++) {
    try {
      final response = await client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 25));
      if (response.statusCode < 500 && response.statusCode != 429) {
        if (response.statusCode != 200) {
          throw ClipException('CDN ответил ${response.statusCode} на плейлист');
        }
        return parseMasterPlaylist(utf8.decode(response.bodyBytes));
      }
      lastError = ClipException('CDN ответил ${response.statusCode} на плейлист');
    } catch (error) {
      if (error is ClipException) rethrow;
      lastError = error;
    }
    if (attempt < attempts) {
      await Future<void>.delayed(Duration(seconds: attempt * 2));
    }
  }
  throw ClipException('плейлист не получился: $lastError');
}

class ClipException implements Exception {
  final String message;
  const ClipException(this.message);

  @override
  String toString() => message;
}
