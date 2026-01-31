part of streaming_session;

extension _StreamingSessionAdaptiveEncoding on StreamingSession {
  int _medianKbps(List<int> samples) {
    if (samples.isEmpty) return 0;
    final s = List<int>.from(samples)..sort();
    return s[s.length ~/ 2];
  }

  Future<int> _sampleHostBweKbps() async {
    if (pc == null) return _adaptiveHostBweSmoothKbps;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (_adaptiveHostBweSmoothKbps > 0 &&
        (nowMs - _adaptiveHostBweLastSampleAtMs) < 800) {
      return _adaptiveHostBweSmoothKbps;
    }
    _adaptiveHostBweLastSampleAtMs = nowMs;

    int kbps = 0;
    try {
      final stats = await pc!.getStats();
      for (final report in stats) {
        if (report.type != 'candidate-pair') continue;
        final values = Map<String, dynamic>.from(report.values);
        if (values['state'] != 'succeeded' || values['nominated'] != true) {
          continue;
        }
        final bps =
            (values['availableOutgoingBitrate'] as num?)?.toDouble() ?? 0.0;
        if (bps > 0) {
          kbps = (bps / 1000.0).round().clamp(0, 200000);
          break;
        }
      }
    } catch (_) {}

    if (kbps > 0) {
      _adaptiveHostBweSamplesKbps.add(kbps);
      if (_adaptiveHostBweSamplesKbps.length > 10) {
        _adaptiveHostBweSamplesKbps.removeAt(0);
      }
      _adaptiveHostBweSmoothKbps = _medianKbps(_adaptiveHostBweSamplesKbps);
    }
    return _adaptiveHostBweSmoothKbps;
  }

  bool _isWindowLikeCaptureType() {
    final captureType =
        (streamSettings?.captureTargetType ?? streamSettings?.sourceType)
            ?.toString()
            .trim()
            .toLowerCase();
    return captureType == 'window' || captureType == 'iterm2';
  }

  int _computeFullBitrateKbpsForCaptureType({
    required int width,
    required int height,
  }) {
    final windowLike = _isWindowLikeCaptureType();

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

  int _computeBestBitrateKbpsForCaptureType({
    required int fullBitrateKbps,
  }) {
    // "Best" bitrate only matters for full-desktop (often 4K) where we want to
    // prefer 60fps when network allows. For window/panel, avoid overshooting.
    if (_isWindowLikeCaptureType()) return fullBitrateKbps;
    return (fullBitrateKbps * 1.5).round().clamp(fullBitrateKbps, 20000);
  }

  void _sendHostEncodingStatus({
    required String mode,
    int? fullBitrateKbps,
    String? reason,
    int? bweKbps,
    int? tierFps,
    int? tierBitrateKbps,
    int? effectiveBandwidthKbps,
  }) {
    final dc = channel;
    if (dc == null || dc.state != RTCDataChannelState.RTCDataChannelOpen)
      return;
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
              if (bweKbps != null) 'bweKbps': bweKbps,
              if (effectiveBandwidthKbps != null)
                'effectiveBandwidthKbps': effectiveBandwidthKbps,
              if (tierFps != null) 'tierFps': tierFps,
              if (tierBitrateKbps != null) 'tierBitrateKbps': tierBitrateKbps,
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

    // Controller reports both:
    // - rxFps: frames actually decoded (new video frames)
    // - uiFps/renderFps: Flutter UI rendering fps (can remain high even when repeating frames)
    final rxFpsAny =
        payload['rxFps'] ?? payload['decodeFps'] ?? payload['renderFps'];
    final uiFpsAny = payload['uiFps'] ?? payload['renderFps'];
    final widthAny = payload['width'];
    final heightAny = payload['height'];
    final rttAny = payload['rttMs'];
    final lossAny = payload['lossFraction'] ?? payload['lossPct'];
    final rxKbpsAny = payload['rxKbps'];
    final jitterMsAny = payload['jitterMs'];
    final freezeDeltaAny = payload['freezeDelta'];
    final decodeMsAny = payload['decodeMsPerFrame'];

    final rxFps = (rxFpsAny is num) ? rxFpsAny.toDouble() : 0.0;
    final uiFps = (uiFpsAny is num) ? uiFpsAny.toDouble() : 0.0;
    final width = (widthAny is num) ? widthAny.toInt() : 0;
    final height = (heightAny is num) ? heightAny.toInt() : 0;
    final rttMs = (rttAny is num) ? rttAny.toDouble() : 0.0;
    final loss = (lossAny is num) ? lossAny.toDouble() : 0.0;
    final rxKbps = (rxKbpsAny is num) ? rxKbpsAny.toDouble() : 0.0;
    final jitterMs = (jitterMsAny is num) ? jitterMsAny.toDouble() : 0.0;
    final freezeDelta = (freezeDeltaAny is num) ? freezeDeltaAny.toInt() : 0;
    final decodeMsPerFrame = (decodeMsAny is num) ? decodeMsAny.toInt() : 0;

    if (rxFps <= 0 || width <= 0 || height <= 0) return;

    if (uiFps > 0 &&
        (DateTime.now().millisecondsSinceEpoch - _adaptiveLastFpsChangeAtMs) >
            2200) {
      // Optional debug signal (not used for decisions).
      // Keep it lightweight: only log when it's clearly different.
      final diff = (uiFps - rxFps).abs();
      if (diff >= 10) {
        InputDebugService.instance.log(
            '[adaptive] stats rxFps=${rxFps.toStringAsFixed(1)} uiFps=${uiFps.toStringAsFixed(1)}');
      }
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // Smooth to avoid oscillations.
    // NOTE: despite the name, this EWMA tracks receiver decoded FPS (rxFps),
    // not Flutter UI fps (which may include repeated frames).
    _adaptiveRenderFpsEwma = _adaptiveRenderFpsEwma <= 0
        ? rxFps
        : (_adaptiveRenderFpsEwma * 0.65 + rxFps * 0.35);
    _adaptiveRttEwma = _adaptiveRttEwma <= 0
        ? rttMs
        : (_adaptiveRttEwma * 0.80 + rttMs * 0.20);
    _adaptiveLossEwma = (_adaptiveLossEwma <= 0)
        ? loss
        : (_adaptiveLossEwma * 0.80 + loss * 0.20);

    // Tiered bandwidth strategy for window/panel capture in dynamic mode.
    if (_isWindowLikeCaptureType() &&
        (mode == 'dynamic' || mode == 'dyn' || mode == 'auto')) {
      final bweKbps = await _sampleHostBweKbps();
      final decision = decideBandwidthTier(
        previous: _adaptiveTierState,
        input: BandwidthTierInput(
          bweKbps: bweKbps,
          lossFraction: _adaptiveLossEwma,
          rttMs: _adaptiveRttEwma,
          freezeDelta: freezeDelta,
          width: width,
          height: height,
        ),
        nowMs: nowMs,
      );
      _adaptiveTierState = decision.state;

      final wantFps = decision.fpsTier.clamp(5, 60);
      final wantBitrate = decision.targetBitrateKbps.clamp(25, 20000);

      final curFpsRaw = streamSettings!.framerate ?? 30;
      final curFps = curFpsRaw <= 0 ? 30 : curFpsRaw;
      final curBitrate = (streamSettings!.bitrate ?? 250).clamp(25, 20000);

      final willChangeFps = wantFps != curFps;
      final willChangeBitrate = wantBitrate != curBitrate;

      if (willChangeBitrate &&
          (nowMs - _adaptiveLastBitrateChangeAtMs) > 1800) {
        streamSettings!.bitrate = wantBitrate;
        _adaptiveLastBitrateChangeAtMs = nowMs;
        InputDebugService.instance.log(
            '[tier] bitrate $curBitrate -> $wantBitrate kbps (bwe=$bweKbps effB=${decision.effectiveBandwidthKbps}) reason=${decision.reason}');
        _sendHostEncodingStatus(
          mode: mode,
          fullBitrateKbps: wantBitrate,
          bweKbps: bweKbps,
          effectiveBandwidthKbps: decision.effectiveBandwidthKbps,
          tierFps: wantFps,
          tierBitrateKbps: wantBitrate,
          reason: 'tier-bitrate',
        );
        await _maybeRenegotiateAfterCaptureSwitch(reason: 'tier-bitrate');
      }

      if (willChangeFps && (nowMs - _adaptiveLastFpsChangeAtMs) > 1800) {
        streamSettings!.framerate = wantFps;
        _adaptiveLastFpsChangeAtMs = nowMs;
        InputDebugService.instance.log(
            '[tier] fps $curFps -> $wantFps (bwe=$bweKbps effB=${decision.effectiveBandwidthKbps}) reason=${decision.reason}');
        _sendHostEncodingStatus(
          mode: mode,
          fullBitrateKbps: wantBitrate,
          bweKbps: bweKbps,
          effectiveBandwidthKbps: decision.effectiveBandwidthKbps,
          tierFps: wantFps,
          tierBitrateKbps: wantBitrate,
          reason: 'tier-fps',
        );
        await _reapplyCurrentCaptureForAdaptiveFps();
      }

      if (!willChangeFps && !willChangeBitrate) {
        _sendHostEncodingStatus(
          mode: mode,
          fullBitrateKbps: wantBitrate,
          bweKbps: bweKbps,
          effectiveBandwidthKbps: decision.effectiveBandwidthKbps,
          tierFps: wantFps,
          tierBitrateKbps: wantBitrate,
          reason: 'tier-hold',
        );
      }

      return;
    }

    final currentFpsRaw = streamSettings!.framerate ?? 30;
    final currentFps = currentFpsRaw <= 0 ? 30 : currentFpsRaw;
    // Two floors:
    // - quality floor: 15fps (start allowing bitrate to drop below full/4)
    // - absolute floor: 5fps (last resort)
    const qualityFloorFps = 15;
    const minFps = 5;
    const maxFps = 60;

    // Compute full bitrate baseline from rendered resolution.
    final computedFull =
        _computeFullBitrateKbpsForCaptureType(width: width, height: height);
    _adaptiveFullBitrateKbps = _adaptiveFullBitrateKbps == null
        ? computedFull
        : ((_adaptiveFullBitrateKbps! * 0.70) + (computedFull * 0.30)).round();
    final full = _adaptiveFullBitrateKbps!;
    final best = _computeBestBitrateKbpsForCaptureType(fullBitrateKbps: full);

    final curBitrate = (streamSettings!.bitrate ?? full).clamp(80, 20000);

    // Always report current host-side target to the controller for debug UI.
    _sendHostEncodingStatus(mode: mode, fullBitrateKbps: full);

    // High quality mode: keep bitrate at baseline (area-scaled), only adjust FPS down.
    if (mode == 'highquality' || mode == 'high_quality' || mode == 'hq') {
      if (curBitrate != best &&
          (nowMs - _adaptiveLastBitrateChangeAtMs) > 2500) {
        streamSettings!.bitrate = best;
        _adaptiveLastBitrateChangeAtMs = nowMs;
        InputDebugService.instance.log('[adaptive] HQ bitrate -> ${best}kbps');
        _sendHostEncodingStatus(
            mode: mode, fullBitrateKbps: full, reason: 'hq-bitrate');
        await _maybeRenegotiateAfterCaptureSwitch(
            reason: 'adaptive-hq-bitrate');
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
      await _maybeRenegotiateAfterCaptureSwitch(
          reason: 'adaptive-init-bitrate');
    }

    // Policy:
    // - If loss is high: reduce bitrate first (keep FPS as-is initially).
    // - If loss is low and receiver keeps up: increase bitrate toward full, then raise FPS.
    // - If receiver FPS is low but loss is low: reduce FPS (device decode/encode bound).

    final lossPct = (_adaptiveLossEwma * 100.0);

    // Network classification:
    // - Use loss/RTT as primary signals.
    // - rxKbps is *observed receive bitrate* (VBR + content dependent), so do NOT
    //   treat "rx < target" as congestion when loss/RTT are good; otherwise the
    //   loop will ratchet bitrate down for static scenes.
    final veryLowLoss = _adaptiveLossEwma <= 0.003;
    final lowLoss = _adaptiveLossEwma <= 0.010;
    final goodRtt = _adaptiveRttEwma <= 320;
    final okRtt = _adaptiveRttEwma <= 380;
    final goodNetwork = veryLowLoss && goodRtt;
    final okNetwork = lowLoss && okRtt;
    final maxAllowedBitrate = goodNetwork ? best : full;

    // Only treat low rxKbps as a congestion signal when *also* seeing
    // non-trivial loss or elevated RTT.
    final rxLooksLimited = rxKbps > 0 && rxKbps < (curBitrate * 0.60);
    final maybeCongestedByRx = rxLooksLimited &&
        (_adaptiveLossEwma >= 0.012 || _adaptiveRttEwma >= 380);

    final badNetwork = _adaptiveLossEwma >= 0.03 ||
        _adaptiveRttEwma >= 450 ||
        maybeCongestedByRx;

    // 1) Network bad: lower bitrate (down to a floor). When encoder FPS already
    // reached the minimum bucket (typically 15fps) and it's still not smooth,
    // allow lowering bitrate further (full/8) to prioritize smoothness/latency.
    if (badNetwork) {
      // If we were in "best" bitrate, drop back to standard first.
      if (curBitrate > full &&
          (nowMs - _adaptiveLastBitrateChangeAtMs) > 2500) {
        streamSettings!.bitrate = full;
        _adaptiveLastBitrateChangeAtMs = nowMs;
        InputDebugService.instance
            .log('[adaptive] net bad: drop best->$full (was $curBitrate)');
        _sendHostEncodingStatus(
            mode: mode, fullBitrateKbps: full, reason: 'net-bad-drop-best');
        await _maybeRenegotiateAfterCaptureSwitch(
            reason: 'adaptive-net-bad-drop-best');
        return;
      }

      // If we are trying 60fps and the network turns bad, drop to 30fps first.
      if (currentFps > 30 && (nowMs - _adaptiveLastFpsChangeAtMs) > 2500) {
        streamSettings!.framerate = 30;
        _adaptiveLastFpsChangeAtMs = nowMs;
        InputDebugService.instance.log(
            '[adaptive] net bad fps $currentFps -> 30 (loss~${lossPct.toStringAsFixed(2)}% rtt~${_adaptiveRttEwma.toStringAsFixed(0)}ms)');
        _sendHostEncodingStatus(
            mode: mode, fullBitrateKbps: full, reason: 'net-bad-fps-30');
        await _reapplyCurrentCaptureForAdaptiveFps();
        return;
      }

      final minBitrate = computeAdaptiveMinBitrateKbps(
        fullBitrateKbps: full,
        targetFps: currentFps,
        // Realtime strategy: keep FPS (>=30) when possible by allowing the
        // bitrate floor to go lower even before we drop to 15fps.
        minFps: 30,
      );
      // React faster under bad network: prefer lowering quality (bitrate)
      // instead of lowering FPS, to reduce latency/queue buildup.
      final downFactor = (currentFps <= qualityFloorFps) ? 0.65 : 0.70;
      final targetBitrate =
          (curBitrate * downFactor).round().clamp(minBitrate, full);
      if (targetBitrate < curBitrate &&
          (nowMs - _adaptiveLastBitrateChangeAtMs) > 2500) {
        streamSettings!.bitrate = targetBitrate;
        _adaptiveLastBitrateChangeAtMs = nowMs;
        InputDebugService.instance.log(
            '[adaptive] net bad (loss~${lossPct.toStringAsFixed(2)}% rtt~${_adaptiveRttEwma.toStringAsFixed(0)}ms) bitrate $curBitrate -> $targetBitrate (full=$full)');
        _sendHostEncodingStatus(
            mode: mode, fullBitrateKbps: full, reason: 'net-bad-bitrate-down');
        await _maybeRenegotiateAfterCaptureSwitch(
            reason: 'adaptive-bitrate-down');
        return;
      }

      // If already near min bitrate but still bad, then reduce FPS a step
      // (30 -> 15 -> 5).
      final nearMinBitrate = curBitrate <= (minBitrate * 1.05);
      if (nearMinBitrate &&
          (nowMs - _adaptiveLastFpsChangeAtMs) > 2500 &&
          currentFps > minFps) {
        int stepDown(int cur) {
          if (cur > 30) return 30;
          if (cur > qualityFloorFps) return qualityFloorFps;
          return minFps;
        }

        final wantDown = stepDown(currentFps).clamp(minFps, currentFps);
        if (wantDown < currentFps) {
          streamSettings!.framerate = wantDown;
          _adaptiveLastFpsChangeAtMs = nowMs;
          InputDebugService.instance.log(
              '[adaptive] net bad fps $currentFps -> $wantDown (minBitrate=$minBitrate render~${_adaptiveRenderFpsEwma.toStringAsFixed(1)})');
          _sendHostEncodingStatus(
              mode: mode, fullBitrateKbps: full, reason: 'net-bad-fps-down');
          await _reapplyCurrentCaptureForAdaptiveFps();
        }
      }
      return;
    }

    // If network is only OK (not "good"), do not keep the extra "best" headroom.
    if (!goodNetwork &&
        curBitrate > full &&
        (nowMs - _adaptiveLastBitrateChangeAtMs) > 3500) {
      streamSettings!.bitrate = full;
      _adaptiveLastBitrateChangeAtMs = nowMs;
      InputDebugService.instance
          .log('[adaptive] net ok: clamp bitrate $curBitrate -> $full');
      _sendHostEncodingStatus(
          mode: mode, fullBitrateKbps: full, reason: 'net-ok-clamp-bitrate');
      await _maybeRenegotiateAfterCaptureSwitch(
          reason: 'adaptive-net-ok-clamp');
      return;
    }

    // 2) (Good/OK) network: raise bitrate toward full.
    if ((okNetwork || goodNetwork) && curBitrate < maxAllowedBitrate) {
      final minBitrate = computeAdaptiveMinBitrateKbps(
        fullBitrateKbps: full,
        targetFps: currentFps,
        minFps: qualityFloorFps,
      );
      final decodeBudgetMs = (1000.0 / currentFps);
      final decoderHealthy = freezeDelta <= 0 &&
          (decodeMsPerFrame <= 0 ||
              decodeMsPerFrame <= (decodeBudgetMs * 1.25));
      final ramp = (goodNetwork && decoderHealthy) ? 1.60 : 1.35;
      final targetBitrate =
          (curBitrate * ramp).round().clamp(minBitrate, maxAllowedBitrate);
      if (targetBitrate > curBitrate &&
          (nowMs - _adaptiveLastBitrateChangeAtMs) > 2500) {
        streamSettings!.bitrate = targetBitrate;
        _adaptiveLastBitrateChangeAtMs = nowMs;
        InputDebugService.instance.log(
            '[adaptive] net good (loss~${lossPct.toStringAsFixed(2)}% rtt~${_adaptiveRttEwma.toStringAsFixed(0)}ms) bitrate $curBitrate -> $targetBitrate (full=$full max=$maxAllowedBitrate)');
        _sendHostEncodingStatus(
            mode: mode, fullBitrateKbps: full, reason: 'net-good-bitrate-up');
        await _maybeRenegotiateAfterCaptureSwitch(
            reason: 'adaptive-bitrate-up');
        // Let bitrate settle before increasing fps.
        return;
      }
    }

    // 2.5) If encoder FPS is already at (quality) minimum but receiver still can't keep up,
    // reduce bitrate further even when loss/RTT look fine. This helps avoid
    // queue buildup (e.g. due to jitter buffer / decoder pressure).
    final decodeBudgetMs = (1000.0 / currentFps);
    final receiverStruggling = freezeDelta > 0 ||
        (decodeMsPerFrame > 0 && decodeMsPerFrame > (decodeBudgetMs * 1.35));
    final receiverLowFps = _adaptiveRenderFpsEwma > 0 &&
        _adaptiveRenderFpsEwma < (qualityFloorFps - 1.5);
    if (currentFps <= qualityFloorFps &&
        (receiverStruggling || receiverLowFps) &&
        (nowMs - _adaptiveLastBitrateChangeAtMs) > 4500) {
      final minBitrate = computeAdaptiveMinBitrateKbps(
        fullBitrateKbps: full,
        targetFps: currentFps,
        minFps: qualityFloorFps,
      );
      final targetBitrate =
          (curBitrate * 0.65).round().clamp(minBitrate, maxAllowedBitrate);
      if (targetBitrate < curBitrate) {
        streamSettings!.bitrate = targetBitrate;
        _adaptiveLastBitrateChangeAtMs = nowMs;
        InputDebugService.instance.log(
            '[adaptive] min fps but receiver low (render~${_adaptiveRenderFpsEwma.toStringAsFixed(1)} decode=${decodeMsPerFrame}ms freezeΔ=$freezeDelta) bitrate $curBitrate -> $targetBitrate (full=$full max=$maxAllowedBitrate)');
        _sendHostEncodingStatus(
            mode: mode, fullBitrateKbps: full, reason: 'min-fps-bitrate-down');
        await _maybeRenegotiateAfterCaptureSwitch(
            reason: 'adaptive-min-fps-bitrate-down');
        return;
      }
    }

    // 3) If receiver keeps up and we are near full bitrate, try raise FPS toward 30.
    final nearMaxBitrate = curBitrate >= (maxAllowedBitrate * 0.90).round();
    if ((okNetwork || goodNetwork) && nearMaxBitrate && currentFps < maxFps) {
      // Only step up if the receiver is already matching current FPS (i.e. not struggling).
      final canStepUp = _adaptiveRenderFpsEwma >= (currentFps - 1);
      if (canStepUp && (nowMs - _adaptiveLastFpsChangeAtMs) > 6500) {
        int nextFps(int cur) {
          if (cur < qualityFloorFps) return qualityFloorFps;
          if (cur < 30) return 30;
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

    // 4) Device bound: rely on decoder/freeze signals rather than "low fps"
    // (static screens can naturally have low fps without being device-limited).
    final decodeBudgetMs2 = (1000.0 / currentFps);
    final decodeSlow =
        decodeMsPerFrame > 0 && decodeMsPerFrame > (decodeBudgetMs2 * 1.35);
    final stuttering = freezeDelta > 0;
    final deviceBound = _adaptiveLossEwma <= 0.01 && (decodeSlow || stuttering);
    if (deviceBound) {
      // Realtime-first: when receiver is struggling but network loss is low,
      // try reducing bitrate (quality) before reducing FPS.
      final minBitrate = computeAdaptiveMinBitrateKbps(
        fullBitrateKbps: full,
        targetFps: currentFps,
        minFps: 30,
      );
      if (curBitrate > minBitrate &&
          (nowMs - _adaptiveLastBitrateChangeAtMs) > 2500) {
        final targetBitrate =
            (curBitrate * 0.70).round().clamp(minBitrate, maxAllowedBitrate);
        if (targetBitrate < curBitrate) {
          streamSettings!.bitrate = targetBitrate;
          _adaptiveLastBitrateChangeAtMs = nowMs;
          InputDebugService.instance.log(
              '[adaptive] device bound bitrate $curBitrate -> $targetBitrate (decode=${decodeMsPerFrame}ms freezeΔ=$freezeDelta)');
          _sendHostEncodingStatus(
            mode: mode,
            fullBitrateKbps: full,
            reason: 'device-bound-bitrate-down',
          );
          await _maybeRenegotiateAfterCaptureSwitch(
              reason: 'adaptive-device-bound-bitrate-down');
          return;
        }
      }

      int wantDown = currentFps;
      if (decodeMsPerFrame > 0) {
        final maxFpsByDecode = (1000.0 / decodeMsPerFrame * 0.90).floor();
        if (maxFpsByDecode < 10) {
          wantDown = minFps;
        } else if (maxFpsByDecode < 20) {
          wantDown = qualityFloorFps;
        } else if (maxFpsByDecode < 40) {
          wantDown = 30;
        }
      } else {
        wantDown = pickAdaptiveTargetFps(
          renderFps: _adaptiveRenderFpsEwma,
          currentFps: currentFps,
          minFps: minFps,
        );
      }
      wantDown = wantDown.clamp(minFps, currentFps);
      if (wantDown < currentFps &&
          (nowMs - _adaptiveLastFpsChangeAtMs) > 2500) {
        streamSettings!.framerate = wantDown;
        _adaptiveLastFpsChangeAtMs = nowMs;
        InputDebugService.instance.log(
            '[adaptive] device bound fps $currentFps -> $wantDown (decode=${decodeMsPerFrame}ms freezeΔ=$freezeDelta jitter=${jitterMs.toStringAsFixed(1)}ms loss~${lossPct.toStringAsFixed(2)}%)');
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
