part of streaming_session;

extension _StreamingSessionAdaptiveEncoding on StreamingSession {
  int _computeFullBitrateKbpsForCaptureType({
    required int width,
    required int height,
  }) {
    final captureType =
        (streamSettings?.captureTargetType ?? streamSettings?.sourceType)
            ?.toString()
            .trim()
            .toLowerCase();
    final windowLike = captureType == 'window' || captureType == 'iterm2';

    // For low-resolution window/panel streams, keep a higher bitrate floor
    // to preserve text clarity (especially terminals/chat apps).
    // Baseline: 1080p30 => 2000 kbps; scale by area, but clamp minimum.
    return computeHighQualityBitrateKbps(
      width: width,
      height: height,
      base1080p30Kbps: 2000,
      minKbps: windowLike ? 2000 : 250,
      maxKbps: 20000,
    );
  }

  void _sendHostEncodingStatus({
    required String mode,
    int? fullBitrateKbps,
    String? reason,
  }) {
    final dc = channel;
    if (dc == null || dc.state != RTCDataChannelState.RTCDataChannelOpen) return;
    try {
      dc.send(
        RTCDataChannelMessage(
          jsonEncode({
            'hostEncodingStatus': {
              'mode': mode,
              'targetFps': streamSettings?.framerate,
              'targetBitrateKbps': streamSettings?.bitrate,
              'fullBitrateKbps': fullBitrateKbps,
              'renderFpsEwma': _adaptiveRenderFpsEwma,
              'lossEwma': _adaptiveLossEwma,
              'rttEwmaMs': _adaptiveRttEwma,
              if (reason != null) 'reason': reason,
              'ts': DateTime.now().millisecondsSinceEpoch,
            }
          }),
        ),
      );
    } catch (_) {}
  }

  Future<DesktopCapturerSource?> _findCurrentCaptureSource() async {
    if (streamSettings?.desktopSourceId == null ||
        streamSettings!.desktopSourceId!.isEmpty) {
      return null;
    }
    final sourceType =
        (streamSettings?.sourceType ?? '').toString().toLowerCase();
    final types =
        sourceType == 'screen' ? [SourceType.Screen] : [SourceType.Window];
    final sources = await desktopCapturer.getSources(types: types);
    for (final s in sources) {
      if (s.id == streamSettings!.desktopSourceId) return s;
    }
    return sources.isNotEmpty ? sources.first : null;
  }

  Future<void> _reapplyCurrentCaptureForAdaptiveFps() async {
    final source = await _findCurrentCaptureSource();
    if (source == null) return;
    final captureType =
        (streamSettings?.captureTargetType ?? streamSettings?.sourceType)
            ?.toString()
            .trim();
    final extra = <String, dynamic>{
      'captureTargetType': captureType,
      'iterm2SessionId': streamSettings?.iterm2SessionId,
      'cropRect': streamSettings?.cropRect,
    };
    final cropRect = streamSettings?.cropRect;
    await _switchCaptureToSource(
      source,
      extraCaptureTarget: extra,
      cropRectNormalized: cropRect,
      minWidthConstraint:
          captureType == 'iterm2' ? _iterm2MinWidthConstraint : null,
      minHeightConstraint:
          captureType == 'iterm2' ? _iterm2MinHeightConstraint : null,
    );
  }

  Future<void> _handleAdaptiveEncodingFeedback(dynamic payload) async {
    if (selfSessionType != SelfSessionType.controlled) return;
    if (!AppPlatform.isDeskTop) return;
    if (pc == null || streamSettings == null) return;
    if (payload is! Map) return;

    final modeAny = payload['mode'] ?? payload['encodingMode'];
    final mode = (modeAny?.toString().trim().toLowerCase() ?? '').isEmpty
        ? (streamSettings?.encodingMode?.toString().trim().toLowerCase() ?? '')
        : modeAny.toString().trim().toLowerCase();
    // Allow controller to disable adaptive feedback loop.
    if (mode == 'off') return;

    final renderFpsAny = payload['renderFps'];
    final widthAny = payload['width'];
    final heightAny = payload['height'];
    final rttAny = payload['rttMs'];
    final lossAny = payload['lossFraction'] ?? payload['lossPct'];

    final renderFps = (renderFpsAny is num) ? renderFpsAny.toDouble() : 0.0;
    final width = (widthAny is num) ? widthAny.toInt() : 0;
    final height = (heightAny is num) ? heightAny.toInt() : 0;
    final rttMs = (rttAny is num) ? rttAny.toDouble() : 0.0;
    final loss = (lossAny is num) ? lossAny.toDouble() : 0.0;

    if (renderFps <= 0 || width <= 0 || height <= 0) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // Smooth to avoid oscillations.
    _adaptiveRenderFpsEwma = _adaptiveRenderFpsEwma <= 0
        ? renderFps
        : (_adaptiveRenderFpsEwma * 0.65 + renderFps * 0.35);
    _adaptiveRttEwma = _adaptiveRttEwma <= 0
        ? rttMs
        : (_adaptiveRttEwma * 0.80 + rttMs * 0.20);
    _adaptiveLossEwma =
        (_adaptiveLossEwma <= 0) ? loss : (_adaptiveLossEwma * 0.80 + loss * 0.20);

    final currentFpsRaw = streamSettings!.framerate ?? 30;
    final currentFps = currentFpsRaw <= 0 ? 30 : currentFpsRaw;
    final minFps = 15;
    const maxFps = 60;

    // Compute full bitrate baseline from rendered resolution.
    final computedFull =
        _computeFullBitrateKbpsForCaptureType(width: width, height: height);
    _adaptiveFullBitrateKbps = _adaptiveFullBitrateKbps == null
        ? computedFull
        : ((_adaptiveFullBitrateKbps! * 0.70) + (computedFull * 0.30)).round();
    final full = _adaptiveFullBitrateKbps!;

    final curBitrate = (streamSettings!.bitrate ?? full).clamp(250, 20000);
    final rxKbpsAny = payload['rxKbps'];
    final rxKbps = (rxKbpsAny is num) ? rxKbpsAny.toDouble() : 0.0;

    // Always report current host-side target to the controller for debug UI.
    _sendHostEncodingStatus(mode: mode, fullBitrateKbps: full);

    // High quality mode: keep bitrate at baseline (area-scaled), only adjust FPS down.
    if (mode == 'highquality' || mode == 'high_quality' || mode == 'hq') {
      if (curBitrate != full && (nowMs - _adaptiveLastBitrateChangeAtMs) > 2500) {
        streamSettings!.bitrate = full;
        _adaptiveLastBitrateChangeAtMs = nowMs;
        InputDebugService.instance.log('[adaptive] HQ bitrate -> ${full}kbps');
        _sendHostEncodingStatus(
            mode: mode, fullBitrateKbps: full, reason: 'hq-bitrate');
        await _maybeRenegotiateAfterCaptureSwitch(reason: 'adaptive-hq-bitrate');
      }
      // HQ still allowed to adjust FPS down when receiver cannot keep up AND loss is low.
      final wantDown = pickAdaptiveTargetFps(
        renderFps: _adaptiveRenderFpsEwma,
        currentFps: currentFps,
        minFps: minFps,
      );
      if (_adaptiveLossEwma <= 0.01 &&
          wantDown < currentFps &&
          (nowMs - _adaptiveLastFpsChangeAtMs) > 2500) {
        streamSettings!.framerate = wantDown;
        _adaptiveLastFpsChangeAtMs = nowMs;
        InputDebugService.instance.log(
            '[adaptive] HQ fps $currentFps -> $wantDown (render~${_adaptiveRenderFpsEwma.toStringAsFixed(1)} loss~${(_adaptiveLossEwma * 100).toStringAsFixed(2)}%)');
        _sendHostEncodingStatus(
            mode: mode, fullBitrateKbps: full, reason: 'hq-fps-down');
        await _reapplyCurrentCaptureForAdaptiveFps();
      }
      return;
    }

    // If we came from legacy huge bitrate settings (e.g. 80000kbps), reset to a sane baseline.
    if ((streamSettings!.bitrate == null || streamSettings!.bitrate! > 50000) &&
        (nowMs - _adaptiveLastBitrateChangeAtMs) > 3000) {
      streamSettings!.bitrate = full;
      _adaptiveLastBitrateChangeAtMs = nowMs;
      InputDebugService.instance.log('[adaptive] init bitrate -> ${full}kbps');
      _sendHostEncodingStatus(
          mode: mode, fullBitrateKbps: full, reason: 'init-bitrate');
      await _maybeRenegotiateAfterCaptureSwitch(reason: 'adaptive-init-bitrate');
    }

    // Policy:
    // - If loss is high: reduce bitrate first (keep FPS as-is initially).
    // - If loss is low and receiver keeps up: increase bitrate toward full, then raise FPS.
    // - If receiver FPS is low but loss is low: reduce FPS (device decode/encode bound).

    final lossPct = (_adaptiveLossEwma * 100.0);
    final goodNetwork =
        _adaptiveLossEwma <= 0.005 && _adaptiveRttEwma <= 220;
    // If receiver throughput is significantly lower than target bitrate, treat as congestion.
    final bitrateNotSustainable =
        rxKbps > 0 && rxKbps < (curBitrate * 0.70);
    final badNetwork =
        _adaptiveLossEwma >= 0.03 || _adaptiveRttEwma >= 420 || bitrateNotSustainable;

    // 1) Network bad: lower bitrate (down to full/4).
    if (badNetwork) {
      final minBitrate = (full / 4).round().clamp(250, full);
      final targetBitrate =
          (curBitrate * 0.80).round().clamp(minBitrate, full);
      if (targetBitrate < curBitrate &&
          (nowMs - _adaptiveLastBitrateChangeAtMs) > 4500) {
        streamSettings!.bitrate = targetBitrate;
        _adaptiveLastBitrateChangeAtMs = nowMs;
        InputDebugService.instance.log(
            '[adaptive] net bad (loss~${lossPct.toStringAsFixed(2)}% rtt~${_adaptiveRttEwma.toStringAsFixed(0)}ms) bitrate $curBitrate -> $targetBitrate (full=$full)');
        _sendHostEncodingStatus(
            mode: mode, fullBitrateKbps: full, reason: 'net-bad-bitrate-down');
        await _maybeRenegotiateAfterCaptureSwitch(reason: 'adaptive-bitrate-down');
        return;
      }

      // If already near min bitrate but still bad, then reduce FPS a step.
      final wantDown = pickAdaptiveTargetFps(
        renderFps: _adaptiveRenderFpsEwma,
        currentFps: currentFps,
        minFps: minFps,
      );
      if (wantDown < currentFps &&
          (nowMs - _adaptiveLastFpsChangeAtMs) > 2500) {
        streamSettings!.framerate = wantDown;
        _adaptiveLastFpsChangeAtMs = nowMs;
        InputDebugService.instance.log(
            '[adaptive] net bad fps $currentFps -> $wantDown (render~${_adaptiveRenderFpsEwma.toStringAsFixed(1)})');
        _sendHostEncodingStatus(
            mode: mode, fullBitrateKbps: full, reason: 'net-bad-fps-down');
        await _reapplyCurrentCaptureForAdaptiveFps();
      }
      return;
    }

    // 2) Good network: raise bitrate toward full.
    if (goodNetwork && curBitrate < full) {
      final targetBitrate =
          (curBitrate * 1.25).round().clamp((full / 4).round(), full);
      if (targetBitrate > curBitrate &&
          (nowMs - _adaptiveLastBitrateChangeAtMs) > 5500) {
        streamSettings!.bitrate = targetBitrate;
        _adaptiveLastBitrateChangeAtMs = nowMs;
        InputDebugService.instance.log(
            '[adaptive] net good (loss~${lossPct.toStringAsFixed(2)}% rtt~${_adaptiveRttEwma.toStringAsFixed(0)}ms) bitrate $curBitrate -> $targetBitrate (full=$full)');
        _sendHostEncodingStatus(
            mode: mode, fullBitrateKbps: full, reason: 'net-good-bitrate-up');
        await _maybeRenegotiateAfterCaptureSwitch(reason: 'adaptive-bitrate-up');
        // Let bitrate settle before increasing fps.
        return;
      }
    }

    // 3) If receiver keeps up and we are near full bitrate, try raise FPS toward 30.
    final nearFullBitrate = curBitrate >= (full * 0.90).round();
    if (goodNetwork && nearFullBitrate && currentFps < maxFps) {
      // Only step up if the receiver is already matching current FPS (i.e. not struggling).
      final canStepUp = _adaptiveRenderFpsEwma >= (currentFps - 1);
      if (canStepUp && (nowMs - _adaptiveLastFpsChangeAtMs) > 6500) {
        int nextFps(int cur) {
          if (cur < 20) return 20;
          if (cur < 30) return 30;
          if (cur < 45) return 45;
          return 60;
        }

        final targetFps = nextFps(currentFps).clamp(minFps, maxFps);
        if (targetFps > currentFps) {
          streamSettings!.framerate = targetFps;
          _adaptiveLastFpsChangeAtMs = nowMs;
          InputDebugService.instance.log(
              '[adaptive] fps up $currentFps -> $targetFps (render~${_adaptiveRenderFpsEwma.toStringAsFixed(1)} loss~${lossPct.toStringAsFixed(2)}%)');
          _sendHostEncodingStatus(
              mode: mode, fullBitrateKbps: full, reason: 'fps-up');
          await _reapplyCurrentCaptureForAdaptiveFps();
          return;
        }
      }
    }

    // 4) Device bound: render fps is low but loss is low -> step down fps to keep quality.
    final deviceBound = _adaptiveLossEwma <= 0.01 &&
        _adaptiveRenderFpsEwma > 0 &&
        _adaptiveRenderFpsEwma < currentFps * 0.75;
    if (deviceBound) {
      final wantDown = pickAdaptiveTargetFps(
        renderFps: _adaptiveRenderFpsEwma,
        currentFps: currentFps,
        minFps: minFps,
      );
      if (wantDown < currentFps &&
          (nowMs - _adaptiveLastFpsChangeAtMs) > 2500) {
        streamSettings!.framerate = wantDown;
        _adaptiveLastFpsChangeAtMs = nowMs;
        InputDebugService.instance.log(
            '[adaptive] device bound fps $currentFps -> $wantDown (render~${_adaptiveRenderFpsEwma.toStringAsFixed(1)} loss~${lossPct.toStringAsFixed(2)}%)');
        _sendHostEncodingStatus(
            mode: mode, fullBitrateKbps: full, reason: 'device-bound-fps-down');
        await _reapplyCurrentCaptureForAdaptiveFps();
        return;
      }
    }
  }

  Future<void> _maybeRenegotiateAfterCaptureSwitch({
    required String reason,
  }) async {
    // On some Android decoders/hardware pipelines, switching capture resolution/crop
    // (especially for iTerm2 panel capture) can result in transient green/black frames
    // until a fresh keyframe/codec config arrives. Renegotiation is a heavy but reliable
    // way to force the sender to emit fresh SPS/PPS.
    if (selfSessionType != SelfSessionType.controlled) return;
    if (pc == null) return;
    if (streamSettings == null) return;
    if (streamSettings?.bitrate == null) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if ((nowMs - _lastRenegotiateAtMs) < 1500) return;
    _lastRenegotiateAtMs = nowMs;

    // Only renegotiate when signaling state is stable; otherwise we risk "glare".
    if (pc!.signalingState != RTCSignalingState.RTCSignalingStateStable) {
      return;
    }

    try {
      RTCSessionDescription sdp = await pc!.createOffer({
        'mandatory': {
          'OfferToReceiveAudio': false,
          'OfferToReceiveVideo': true,
        },
        'optional': [],
      });

      // Keep codec preference consistent with initial offer.
      if (AppPlatform.isMacos) {
        final ct = (controller.devicetype).toString().toLowerCase();
        final isMobileController =
            ct == 'android' || ct == 'ios' || ct == 'androidtv';
        final prefer = isMobileController ? 'h264' : 'av1';
        setPreferredCodec(sdp, audio: 'opus', video: prefer);
      }

      await pc!.setLocalDescription(_fixSdp(sdp, streamSettings!.bitrate!));

      WebSocketService.send('offer', {
        'source_connectionid': controlled.websocketSessionid,
        'target_uid': controller.uid,
        'target_connectionid': controller.websocketSessionid,
        'description': {'sdp': sdp.sdp, 'type': sdp.type},
        'bitrate': streamSettings!.bitrate,
        'reason': reason,
      });
      InputDebugService.instance.log('HOST renegotiate sent reason=$reason');
    } catch (e) {
      InputDebugService.instance
          .log('HOST renegotiate failed reason=$reason err=$e');
    }
  }
}
