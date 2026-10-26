/// Мини-сервер для локального запуска release-сборки Flutter Web.
///
/// Запуск: dart run tool/serve.dart build/web 8081
library;

import 'dart:io';

const Map<String, String> _mime = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.wasm': 'application/wasm',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.map': 'application/json',
  '.symbols': 'text/plain',
};

Future<void> main(List<String> args) async {
  final root = args.isNotEmpty ? args[0] : 'build/web';
  final port = args.length > 1 ? (int.tryParse(args[1]) ?? 8081) : 8081;

  if (!Directory(root).existsSync()) {
    stderr.writeln('Нет папки $root. Сначала: flutter build web --release');
    exitCode = 1;
    return;
  }

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('Статика из $root на http://localhost:$port');

  await for (final request in server) {
    final response = request.response;

    var path = Uri.decodeComponent(request.uri.path);
    if (path == '/' || path.isEmpty) path = '/index.html';
    // Каталог без имени файла: отдаём его index.html (нужно для сборки с
    // --base-href /<репозиторий>/, как на GitHub Pages).
    if (path.endsWith('/')) path = '${path}index.html';

    var file = File('$root$path');
    if (!file.existsSync()) {
      // Для single-page приложения всегда отдаём index.html.
      file = File('$root/index.html');
    }

    if (!file.existsSync()) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      continue;
    }

    final ext = _extension(file.path);
    response.headers.set('content-type', _mime[ext] ?? 'application/octet-stream');
    response.headers.set('cache-control', 'no-cache');
    await response.addStream(file.openRead());
    await response.close();
  }
}

String _extension(String path) {
  final index = path.lastIndexOf('.');
  if (index < 0) return '';
  return path.substring(index).toLowerCase();
}
