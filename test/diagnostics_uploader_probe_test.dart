import 'dart:convert';
import 'dart:io';

import 'package:cloudplayplus/services/diagnostics/diagnostics_uploader.dart';
import 'package:flutter_test/flutter_test.dart';

Future<HttpServer> _startServer({
  required Future<void> Function(HttpRequest req) handler,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  // ignore: unawaited_futures
  server.listen(handler);
  return server;
}

void main() {
  test('probeLanHostArtifacts returns true only when /artifact/info ok', () async {
    final okServer = await _startServer(handler: (req) async {
      if (req.uri.path == '/artifact/info') {
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'ok': true, 'inboxDir': '/tmp'}));
        await req.response.close();
        return;
      }
      req.response.statusCode = 404;
      await req.response.close();
    });
    addTearDown(() => okServer.close(force: true));

    final badServer = await _startServer(handler: (req) async {
      req.response.statusCode = 404;
      await req.response.close();
    });
    addTearDown(() => badServer.close(force: true));

    expect(
      await DiagnosticsUploader.instance.probeLanHostArtifacts(
        host: InternetAddress.loopbackIPv4.address,
        port: okServer.port,
      ),
      isTrue,
    );
    expect(
      await DiagnosticsUploader.instance.probeLanHostArtifacts(
        host: InternetAddress.loopbackIPv4.address,
        port: badServer.port,
      ),
      isFalse,
    );
  });
}

