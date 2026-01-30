import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloudplayplus/core/cli/cloudplayplus_cli.dart';
import 'package:test/test.dart';

IOSink _sinkToBuffer(StringBuffer buf) {
  final controller = StreamController<List<int>>();
  controller.stream.transform(utf8.decoder).listen(buf.write);
  return IOSink(controller.sink, encoding: utf8);
}

Future<void> _closeSink(IOSink sink) async {
  await sink.flush();
  await sink.close();
}

void main() {
  test('cli --help prints usage', () async {
    final outBuf = StringBuffer();
    final errBuf = StringBuffer();
    final out = _sinkToBuffer(outBuf);
    final err = _sinkToBuffer(errBuf);
    final code = await runCloudPlayPlusCli(['--help'], out: out, err: err);
    await _closeSink(out);
    await _closeSink(err);

    expect(code, 0);
    expect(errBuf.toString(), isEmpty);
    final s = outBuf.toString();
    expect(s, contains('cloudplayplus-cli'));
    expect(s, contains('Usage:'));
    expect(s, contains('iterm2 list'));
  });
}

