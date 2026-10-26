/// Локальный прокси для запуска Flutter-версии в браузере.
///
/// Сайт reachthefinals.com не отдаёт CORS-заголовки, поэтому браузерная
/// сборка не может обратиться к нему напрямую. Этот сервер проксирует
/// запросы и добавляет нужные заголовки.
///
/// Запуск:  dart run tool/proxy.dart 8080
/// Затем:   flutter run -d chrome --dart-define=API_BASE=http://localhost:8080
library;

import 'dart:io';

const String _upstreamHost = 'www.reachthefinals.com';

Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? (int.tryParse(args.first) ?? 8080) : 8080;
  final HttpServer server;
  try {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  } on SocketException catch (error) {
    stderr.writeln('Не удалось занять порт $port: $error');
    exitCode = 1;
    return;
  }

  final client = HttpClient()..autoUncompress = true;
  stdout.writeln('Прокси слушает http://localhost:$port -> https://$_upstreamHost');
  stdout.writeln('Остановить: Ctrl+C');

  await for (final request in server) {
    final response = request.response;
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
    response.headers.set('Access-Control-Allow-Headers', '*');

    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.noContent;
      await response.close();
      continue;
    }

    if (request.method != 'GET') {
      response.statusCode = HttpStatus.methodNotAllowed;
      response.write('Только GET');
      await response.close();
      continue;
    }

    try {
      final target = Uri(
        scheme: 'https',
        host: _upstreamHost,
        path: request.uri.path,
        query: request.uri.hasQuery ? request.uri.query : null,
      );
      final upstream = await client.getUrl(target);
      upstream.headers.set('user-agent', 'Mozilla/5.0 (FinalsNotes; personal app)');
      final upstreamResponse = await upstream.close();

      response.statusCode = upstreamResponse.statusCode;
      final contentType = upstreamResponse.headers.contentType;
      if (contentType != null) {
        response.headers.set('content-type', contentType.toString());
      }
      await response.addStream(upstreamResponse);
      await response.close();
    } catch (error) {
      response.statusCode = HttpStatus.badGateway;
      response.write('Ошибка прокси: $error');
      await response.close();
    }
  }
}
