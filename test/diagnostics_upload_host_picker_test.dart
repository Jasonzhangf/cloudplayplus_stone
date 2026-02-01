import 'package:cloudplayplus/core/diagnostics/pick_lan_host_for_artifacts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pickLanHostForArtifacts prefers first reachable that serves /artifact', () async {
    final host = await pickLanHostForArtifacts(
      rankedHosts: const ['ip1', 'ip2', 'ip3'],
      reachable: const {'ip1': true, 'ip2': true, 'ip3': true},
      probeArtifacts: (h) async => h == 'ip2',
    );
    expect(host, 'ip2');
  });

  test('pickLanHostForArtifacts falls back to first reachable when none serve /artifact', () async {
    final host = await pickLanHostForArtifacts(
      rankedHosts: const ['ip1', 'ip2'],
      reachable: const {'ip1': false, 'ip2': true},
      probeArtifacts: (_) async => false,
    );
    expect(host, 'ip2');
  });

  test('pickLanHostForArtifacts falls back to first ranked when reachability unknown', () async {
    final host = await pickLanHostForArtifacts(
      rankedHosts: const ['ip1', 'ip2'],
      reachable: const {},
      probeArtifacts: (_) async => false,
    );
    expect(host, 'ip1');
  });
}

