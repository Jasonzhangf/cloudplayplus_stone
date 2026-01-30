part of streaming_session;

extension _StreamingSessionAdaptiveEncoding on StreamingSession {
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

    final renderFps = (renderFpsAny is num) ? renderFpsAny.toDouble() : 0.0;
    final width = (widthAny is num) ? widthAny.toInt() : 0;
    final height = (heightAny is num) ? heightAny.toInt() : 0;
    final rttMs = (rttAny is num) ? rttAny.toDouble() : 0.0;

    if (renderFps <= 0 || width <= 0 || height <= 0) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // Smooth to avoid oscillations.
    _adaptiveRenderFpsEwma = _adaptiveRenderFpsEwma <= 0
        ? renderFps
        : (_adaptiveRenderFpsEwma * 0.65 + renderFps * 0.35);
    _adaptiveRttEwma = _adaptiveRttEwma <= 0
        ? rttMs
        : (_adaptiveRttEwma * 0.80 + rttMs * 0.20);

    final currentFps = streamSettings!.framerate ?? 30;
    final wantFps = pickAdaptiveTargetFps(
      renderFps: _adaptiveRenderFpsEwma,
      currentFps: currentFps,
      minFps: 15,
    );

    // Step 1: align capture FPS down to avoid encoding above render capability.
    if (wantFps < currentFps && (nowMs - _adaptiveLastFpsChangeAtMs) > 2500) {
      streamSettings!.framerate = wantFps;
      _adaptiveLastFpsChangeAtMs = nowMs;
      InputDebugService.instance.log(
          '[adaptive] fps $currentFps -> $wantFps (render~${_adaptiveRenderFpsEwma.toStringAsFixed(1)} rtt~${_adaptiveRttEwma.toStringAsFixed(0)}ms)');
      await _reapplyCurrentCaptureForAdaptiveFps();
    }

    // Compute full bitrate baseline from rendered resolution.
    final computedFull =
        computeHighQualityBitrateKbps(width: width, height: height);
    _adaptiveFullBitrateKbps = _adaptiveFullBitrateKbps == null
        ? computedFull
        : ((_adaptiveFullBitrateKbps! * 0.70) + (computedFull * 0.30)).round();
    final full = _adaptiveFullBitrateKbps!;

    // High quality mode: keep bitrate at baseline (area-scaled), only adjust FPS down.
    if (mode == 'highquality' || mode == 'high_quality' || mode == 'hq') {
      final cur = (streamSettings!.bitrate ?? full).clamp(250, 20000);
      if (cur != full && (nowMs - _adaptiveLastBitrateChangeAtMs) > 2500) {
        streamSettings!.bitrate = full;
        _adaptiveLastBitrateChangeAtMs = nowMs;
        InputDebugService.instance.log('[adaptive] HQ bitrate -> ${full}kbps');
        await _maybeRenegotiateAfterCaptureSwitch(reason: 'adaptive-hq-bitrate');
      }
      return;
    }

    // If we came from legacy huge bitrate settings (e.g. 80000kbps), reset to a sane baseline.
    final curBitrate = streamSettings!.bitrate;
    if ((curBitrate == null || curBitrate > 50000) &&
        (nowMs - _adaptiveLastBitrateChangeAtMs) > 3000) {
      streamSettings!.bitrate = full;
      _adaptiveLastBitrateChangeAtMs = nowMs;
      InputDebugService.instance.log('[adaptive] init bitrate -> ${full}kbps');
      await _maybeRenegotiateAfterCaptureSwitch(reason: 'adaptive-init-bitrate');
      return;
    }

    // Step 2: if already at 15fps but still struggling, adjust bitrate dynamically.
    final encFps = streamSettings!.framerate ?? currentFps;
    if (encFps <= 15) {
      final target = computeDynamicBitrateKbps(
        fullBitrateKbps: full,
        renderFps: _adaptiveRenderFpsEwma,
        targetFps: encFps <= 0 ? 15 : encFps,
        rttMs: _adaptiveRttEwma,
      );
      final cur = (streamSettings!.bitrate ?? full).clamp(250, 20000);
      final diffRatio = (target - cur).abs() / cur;
      if (diffRatio >= 0.12 &&
          (nowMs - _adaptiveLastBitrateChangeAtMs) > 4500) {
        streamSettings!.bitrate = target;
        _adaptiveLastBitrateChangeAtMs = nowMs;
        InputDebugService.instance
            .log('[adaptive] bitrate $cur -> ${target}kbps (full=$full)');
        await _maybeRenegotiateAfterCaptureSwitch(reason: 'adaptive-bitrate');
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

