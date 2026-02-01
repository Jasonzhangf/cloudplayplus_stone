import 'package:cloudplayplus/app/intents/app_intent.dart';
import 'package:cloudplayplus/app/state/app_state.dart';
import 'package:cloudplayplus/app/state/diagnostics_state.dart';
import 'package:cloudplayplus/app/store/app_reducer.dart';
import 'package:cloudplayplus/app/store/effects.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('upload diagnostics intent emits effect', () {
    final res = reduceApp(
      const AppState(),
      const AppIntentUploadDiagnosticsToLanHost(host: '::1', port: 17999),
    );
    expect(res.effects.whereType<AppEffectUploadDiagnosticsToLanHost>(), isNotEmpty);
  });

  test('refresh LAN hints intent emits effect', () {
    final res = reduceApp(
      const AppState(),
      const AppIntentRefreshLanHints(deviceConnectionId: 'conn-1'),
    );
    expect(res.effects.whereType<AppEffectRefreshLanHints>(), isNotEmpty);
  });

  test('diagnostics upload phase updates diagnostics state', () {
    final s0 = const AppState();
    final res = reduceApp(
      s0,
      const AppIntentInternalDiagnosticsUploadPhaseUpdated(
        phase: DiagnosticsUploadPhase.failed,
        error: 'oops',
        savedPaths: <String>['/a/b'],
      ),
    );
    expect(res.next.diagnostics.uploadPhase, DiagnosticsUploadPhase.failed);
    expect(res.next.diagnostics.lastUploadError, 'oops');
    expect(res.next.diagnostics.lastSavedPaths, ['/a/b']);
  });
}

