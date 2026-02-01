part of 'global_remote_screen_renderer.dart';

mixin _RemoteScreenGesturesMixin on State<GlobalRemoteScreenRenderer>, _RemoteScreenTransformMixin {
  // Provided by `_VideoScreenState` (the widget shell). These are declared here
  // so this mixin can stay independent from the concrete State class.
  SmoothScrollController get _scrollController;
  RenderBox? get renderBox;
  bool get mounted;
  bool get _isUsingTouchMode;
  bool get _isUsingTouchpadMode;
  ({double xPercent, double yPercent})? _calculatePositionPercent(
      Offset globalPosition);
  void _handleMouseModeDown(double xPercent, double yPercent);
  void _handleMouseModeUp();
  void _handleMousePositionUpdate(Offset globalPosition);

  bool get _leftButtonDown;
  set _leftButtonDown(bool v);

  // Kept in this mixin to avoid depending on `_VideoScreenState` statics.
  Duration get _twoFingerDecisionDebounce => const Duration(milliseconds: 90);

  Offset? _lastTouchpadPosition;
  final Map<int, Offset> _touchpadPointers = {};
  final Map<int, DateTime> _touchpadPointerDownTime = {}; // 记录每个手指按下的时间
  final Map<int, Offset> _touchpadPointerDownPosition = {}; // 记录每个手指按下的位置
  double? _lastPinchDistance;
  double? _initialPinchDistance;
  Offset? _initialTwoFingerCenter;
  bool _isTwoFingerScrolling = false;
  bool _isDragging = false; // 是否处于拖拽模式
  int? _draggingPointerId; // 拖拽的手指ID
  bool _lockSingleFingerAfterTwoFinger = false;
  ({double x, double y})? _lastScrollAnchor;

  // Fast tap thresholds.
  Duration get _quickTapDuration => const Duration(milliseconds: 300);
  double get _quickTapMaxDistance => 10.0;

  // Long press drag thresholds.
  Duration get _longPressDuration => const Duration(milliseconds: 3000);
  double get _longPressMaxDistance => 5.0;

  Offset? _pinchFocalPoint;
  Offset? _lastPinchFocalPoint;
  TwoFingerGestureType _twoFingerGestureType = TwoFingerGestureType.undecided;
  DateTime? _twoFingerStartTime;
  bool _twoFingerScrollActivated = false;
  double _twoFingerScrollActivationDistance = 0.0;

  void _resetTouchpadGestureState({bool lockSingleFinger = false}) {
    _touchpadPointers.clear();
    _touchpadPointerDownTime.clear();
    _touchpadPointerDownPosition.clear();
    _lastTouchpadPosition = null;
    _lastPinchDistance = null;
    _initialPinchDistance = null;
    _initialTwoFingerCenter = null;
    _pinchFocalPoint = null;
    _lastPinchFocalPoint = null;
    _twoFingerGestureType = TwoFingerGestureType.undecided;
    _twoFingerStartTime = null;
    _twoFingerScrollActivated = false;
    _twoFingerScrollActivationDistance = 0.0;
    _isTwoFingerScrolling = false;
    _lastScrollAnchor = null;
    _lockSingleFingerAfterTwoFinger = lockSingleFinger;
  }

  void _handleTouchDown(PointerDownEvent event) {
    final pos = _calculatePositionPercent(event.position);
    if (pos == null) return;

    if (_isUsingTouchMode || _isUsingTouchpadMode) {
      // 触摸模式也支持缩放/滚动/拖拽等手势：统一走 touchpad 逻辑
      _handleTouchpadDown(event);
      return;
    }
    _handleMouseModeDown(pos.xPercent, pos.yPercent);
  }

  void _handleTouchUp(PointerUpEvent event) {
    if (_isUsingTouchMode || _isUsingTouchpadMode) {
      _handleTouchpadUp(event);
      return;
    }
    _handleMouseModeUp();
  }

  void _handleTouchMove(PointerMoveEvent event) {
    final pos = _calculatePositionPercent(event.position);
    if (pos == null) return;

    if (_isUsingTouchMode || _isUsingTouchpadMode) {
      _handleTouchpadMove(event);
      return;
    }
    _handleMousePositionUpdate(event.position);
  }

  void _handleTouchpadDown(PointerDownEvent event) {
    _touchpadPointers[event.pointer] = event.position;
    _touchpadPointerDownTime[event.pointer] = DateTime.now();
    _touchpadPointerDownPosition[event.pointer] = event.position;

    if (_touchpadPointers.length == 1) {
      _lastTouchpadPosition = event.position;
      // 启动长按拖拽检测（3秒）
      _startLongPressDragDetection(event.pointer);
      _isDragging = false; // 重置拖拽状态
      _draggingPointerId = null;
      _lockSingleFingerAfterTwoFinger = false;
    } else if (_touchpadPointers.length == 2) {
      _lockSingleFingerAfterTwoFinger = true;
      _lastTouchpadPosition = null;
      _lastPinchDistance = _calculatePinchDistance();

      List<Offset> positions = _touchpadPointers.values.toList();
      Offset center = Offset(
        (positions[0].dx + positions[1].dx) / 2,
        (positions[0].dy + positions[1].dy) / 2,
      );

      _initialTwoFingerCenter = center;
      _initialPinchDistance = _calculatePinchDistance();
      _lastPinchDistance = _initialPinchDistance;
      _lastTouchpadPosition = center;
      _pinchFocalPoint = center;
      _lastPinchFocalPoint = null;
      _twoFingerGestureType = TwoFingerGestureType.undecided;

      _twoFingerStartTime = DateTime.now();
      _twoFingerScrollActivated = false;
      _twoFingerScrollActivationDistance = 0.0;

      _scrollController.startScroll();
      _isTwoFingerScrolling = true;
    }
  }

  void _handleTouchpadMove(PointerMoveEvent event) {
    _touchpadPointers[event.pointer] = event.position;

    if (_touchpadPointers.length == 1) {
      if (_lockSingleFingerAfterTwoFinger) {
        _lastTouchpadPosition = event.position;
        return;
      }
      if (_isDragging && _draggingPointerId == event.pointer) {
        _handleDraggingMove(event);
        return;
      }
      _handleSingleFingerMove(event);
    } else if (_touchpadPointers.length == 2) {
      _handleTwoFingerGesture(event);
    }
  }

  void _startLongPressDragDetection(int pointerId) {
    Future.delayed(_longPressDuration, () {
      if (!mounted) return;
      // 只有还存在这一根手指，且仍然只有一指时才进入拖拽
      if (!_touchpadPointers.containsKey(pointerId)) return;
      if (_touchpadPointers.length != 1) return;

      final downPosition = _touchpadPointerDownPosition[pointerId];
      final currentPosition = _touchpadPointers[pointerId];
      if (downPosition == null || currentPosition == null) return;

      final distance = (currentPosition - downPosition).distance;
      if (distance > _longPressMaxDistance) return;

      final pos = _calculatePositionPercent(currentPosition);
      if (pos == null) return;

      setState(() {
        _isDragging = true;
        _draggingPointerId = pointerId;
      });

      WebrtcService.currentRenderingSession?.inputController
          ?.requestMoveMouseAbsl(pos.xPercent, pos.yPercent,
              WebrtcService.currentRenderingSession!.screenId);
      WebrtcService.currentRenderingSession?.inputController
          ?.requestMouseClick(1, true);
      _leftButtonDown = true;
    });
  }

  void _handleDraggingMove(PointerMoveEvent event) {
    final pos = _calculatePositionPercent(event.position);
    if (pos == null) return;
    WebrtcService.currentRenderingSession?.inputController
        ?.requestMoveMouseAbsl(pos.xPercent, pos.yPercent,
            WebrtcService.currentRenderingSession!.screenId);
  }

  void _handleTouchpadUp(PointerEvent event) {
    // 检测是否是快速单击
    final downTime = _touchpadPointerDownTime[event.pointer];
    final downPosition = _touchpadPointerDownPosition[event.pointer];
    bool isQuickTap = false;

    if (downTime != null && downPosition != null) {
      final duration = DateTime.now().difference(downTime);
      final distance = (event.position - downPosition).distance;

      // 判断是否是快速单击
      isQuickTap =
          duration < _quickTapDuration && distance < _quickTapMaxDistance;

      if (isQuickTap) {
        // 根据当前手指数量决定是左键还是右键
        if (_touchpadPointers.length == 1) {
          // 单指快速单击 -> 左键点击
          final pos = _calculatePositionPercent(event.position);
          if (pos != null) {
            WebrtcService.currentRenderingSession?.inputController
                ?.requestMoveMouseAbsl(pos.xPercent, pos.yPercent,
                    WebrtcService.currentRenderingSession!.screenId);
          }
          WebrtcService.currentRenderingSession?.inputController
              ?.requestMouseClick(1, true); // 按下左键
          // 延迟一小段时间后松开，模拟单击
          Future.delayed(const Duration(milliseconds: 50), () {
            WebrtcService.currentRenderingSession?.inputController
                ?.requestMouseClick(1, false); // 松开左键
          });
        } else if (_touchpadPointers.length == 2) {
          // 在有一个手指按下的情况下，第二根手指快速单击 -> 右键点击
          WebrtcService.currentRenderingSession?.inputController
              ?.requestMouseClick(3, true); // 按下右键
          // 延迟一小段时间后松开，模拟单击
          Future.delayed(const Duration(milliseconds: 50), () {
            WebrtcService.currentRenderingSession?.inputController
                ?.requestMouseClick(3, false); // 松开右键
          });
          // 如果是第二根手指快速单击，停止双指滚动
          if (_isTwoFingerScrolling) {
            _scrollController.startFling();
            _isTwoFingerScrolling = false;
          }
        }
      }
    }

    // 处理拖拽模式结束
    if (_isDragging && _draggingPointerId == event.pointer) {
      // 如果这是拖拽的手指，且是最后一根手指，发送鼠标松开事件
      if (_touchpadPointers.length == 1) {
        WebrtcService.currentRenderingSession?.inputController
            ?.requestMouseClick(1, false);
        _leftButtonDown = false;
        _isDragging = false;
        _draggingPointerId = null;
      }
    }
    // 清理该手指的记录
    _touchpadPointerDownTime.remove(event.pointer);
    _touchpadPointerDownPosition.remove(event.pointer);
    _touchpadPointers.remove(event.pointer);

    // 如果不是快速单击，才处理滚动逻辑
    if (!isQuickTap) {
      if (_isTwoFingerScrolling && _touchpadPointers.length < 2) {
        _scrollController.startFling();
        _isTwoFingerScrolling = false;
      }
    }

    if (_touchpadPointers.isEmpty) {
      _lockSingleFingerAfterTwoFinger = false;
      _lastTouchpadPosition = null;
      _lastPinchDistance = null;
      _initialPinchDistance = null;
      _initialTwoFingerCenter = null;
      _pinchFocalPoint = null;
      _lastPinchFocalPoint = null;
      _twoFingerGestureType = TwoFingerGestureType.undecided;
      _twoFingerStartTime = null;
      _twoFingerScrollActivated = false;
      _twoFingerScrollActivationDistance = 0.0;
      // 如果还有拖拽状态，确保清理
      if (_isDragging) {
        WebrtcService.currentRenderingSession?.inputController
            ?.requestMouseClick(1, false); // 松开左键
        _leftButtonDown = false;
        _isDragging = false;
        _draggingPointerId = null;
      }
    } else if (_touchpadPointers.length == 1) {
      _lastTouchpadPosition = _touchpadPointers.values.first;
      _lastPinchDistance = null;
      _initialPinchDistance = null;
      _initialTwoFingerCenter = null;
      _pinchFocalPoint = null;
      _lastPinchFocalPoint = null;
      _twoFingerGestureType = TwoFingerGestureType.undecided;
      _twoFingerStartTime = null;
      _twoFingerScrollActivated = false;
      _twoFingerScrollActivationDistance = 0.0;
      // When dropping from 2 fingers to 1, avoid interpreting the remaining finger
      // as a continuation pan. Require lifting and re-touching to start panning.
      _lockSingleFingerAfterTwoFinger = true;
    }
  }

  void _handleSingleFingerMove(PointerMoveEvent event) {
    if (_lastTouchpadPosition == null) {
      _lastTouchpadPosition = event.position;
      return;
    }

    // Pan speed should scale with zoom: higher zoom => move more per gesture.
    // This keeps the content navigation usable when zoomed in (especially portrait).
    final zoomFactor = _videoScale.clamp(1.0, _maxVideoScale);
    double deltaX = (event.position.dx - _lastTouchpadPosition!.dx) *
        StreamingSettings.touchpadSensitivity *
        zoomFactor;
    double deltaY = (event.position.dy - _lastTouchpadPosition!.dy) *
        StreamingSettings.touchpadSensitivity *
        zoomFactor;
    _lastTouchpadPosition = event.position;

    // 拖拽模式下不移动画面
    if (_isDragging) {
      return;
    }

    // 触摸模式/触摸板模式：
    // - 单指移动仅用于平移本地放大画面（不发送远程鼠标移动）
    // - 不进行远程点按拖拽
    if (_videoScale > 1.0) {
      setState(() {
        final next = _videoOffset + Offset(deltaX, deltaY);
        final size = renderBox?.size ?? _lastRenderSize;
        _videoOffset = (size == null)
            ? next
            : clampVideoOffsetToBounds(
                size: size,
                scale: _videoScale,
                offset: next,
              );
      });
      return;
    }
  }

  void _handleTwoFingerGesture(PointerMoveEvent event) {
    if (_touchpadPointers.length != 2) return;

    List<Offset> positions = _touchpadPointers.values.toList();
    Offset center = Offset(
      (positions[0].dx + positions[1].dx) / 2,
      (positions[0].dy + positions[1].dy) / 2,
    );
    _pinchFocalPoint = center;

    double currentDistance = _calculatePinchDistance();

    // Ensure pinch distance is always updated (even when gesture type is undecided)
    // so that zoom-out after zoom-in keeps working.
    if (_lastPinchDistance == null || _lastPinchDistance == 0) {
      _lastPinchDistance = currentDistance;
    }

    if (_lastTouchpadPosition != null &&
        _lastPinchDistance != null &&
        _initialPinchDistance != null &&
        _initialTwoFingerCenter != null) {
      if (_twoFingerGestureType == TwoFingerGestureType.undecided) {
        double cumulativeDistanceChangeRatio =
            (currentDistance - _initialPinchDistance!).abs() /
                _initialPinchDistance!;
        final cumulativeDistanceChangePx =
            (currentDistance - _initialPinchDistance!).abs();
        final keys = _touchpadPointers.keys.toList(growable: false);
        final p1 = _touchpadPointers[keys[0]]!;
        final p2 = _touchpadPointers[keys[1]]!;
        final i1 = _touchpadPointerDownPosition[keys[0]] ?? p1;
        final i2 = _touchpadPointerDownPosition[keys[1]] ?? p2;
        final v1 = p1 - i1;
        final v2 = p2 - i2;

        _twoFingerGestureType = decideTwoFingerGestureTypeFromVectors(
          isMobile: AppPlatform.isMobile,
          v1: v1,
          v2: v2,
          cumulativeDistanceChangeRatio: cumulativeDistanceChangeRatio,
          cumulativeDistanceChangePx: cumulativeDistanceChangePx,
          verticalDominanceFactor: 5.0,
        );
      }

      if (_twoFingerGestureType == TwoFingerGestureType.zoom) {
        _twoFingerScrollActivated = false;
        _handlePinchZoom(currentDistance / _lastPinchDistance!);
      } else if (_twoFingerGestureType == TwoFingerGestureType.scroll) {
        // Allow switching from scroll -> zoom if a clear pinch emerges later.
        final cumulativeDistanceChangeRatio =
            (currentDistance - _initialPinchDistance!).abs() /
                _initialPinchDistance!;
        final cumulativeDistanceChangePx =
            (currentDistance - _initialPinchDistance!).abs();
        final keys = _touchpadPointers.keys.toList(growable: false);
        final p1 = _touchpadPointers[keys[0]]!;
        final p2 = _touchpadPointers[keys[1]]!;
        final i1 = _touchpadPointerDownPosition[keys[0]] ?? p1;
        final i2 = _touchpadPointerDownPosition[keys[1]] ?? p2;
        final v1 = p1 - i1;
        final v2 = p2 - i2;
        final maybe = decideTwoFingerGestureTypeFromVectors(
          isMobile: AppPlatform.isMobile,
          v1: v1,
          v2: v2,
          cumulativeDistanceChangeRatio: cumulativeDistanceChangeRatio,
          cumulativeDistanceChangePx: cumulativeDistanceChangePx,
          verticalDominanceFactor: 5.0,
        );
        if (maybe == TwoFingerGestureType.zoom) {
          _twoFingerGestureType = TwoFingerGestureType.zoom;
          _twoFingerScrollActivated = false;
          _handlePinchZoom(currentDistance / _lastPinchDistance!);
          _lastTouchpadPosition = center;
          _lastPinchDistance = currentDistance;
          return;
        }
        double scrollDeltaX = center.dx - _lastTouchpadPosition!.dx;
        double scrollDeltaY = center.dy - _lastTouchpadPosition!.dy;
        final sinceStart = _twoFingerStartTime == null
            ? Duration.zero
            : DateTime.now().difference(_twoFingerStartTime!);

        _twoFingerScrollActivationDistance += scrollDeltaY.abs();

        // Debounce: do not send any scroll until we are confident it's scroll.
        if (!_twoFingerScrollActivated) {
          if (shouldActivateTwoFingerScroll(
            isMobile: AppPlatform.isMobile,
            sinceStart: sinceStart,
            accumulatedScrollDistance: _twoFingerScrollActivationDistance,
            decisionDebounce: _twoFingerDecisionDebounce,
          )) {
            _twoFingerScrollActivated = true;
            _scrollController.startScroll();
          } else {
            _lastTouchpadPosition = center;
            _lastPinchDistance = currentDistance;
            return;
          }
        }
        _handleTwoFingerScroll(scrollDeltaX, scrollDeltaY);
      }
    }

    _lastTouchpadPosition = center;
    _lastPinchDistance = currentDistance;
  }

  double _calculatePinchDistance() {
    if (_touchpadPointers.length != 2) return 0.0;
    List<Offset> positions = _touchpadPointers.values.toList();
    return (positions[0] - positions[1]).distance;
  }

  void _handleTwoFingerScroll(double deltaX, double deltaY) {
    if (!StreamingSettings.touchpadTwoFingerScroll) return;
    // 仅允许垂直滚动。
    // 需求：双指上下滚动要模拟鼠标上下滚动，并且滚轮注入点在左手指位置。
    // 做法：把左手指位置作为 anchor 一并发送到滚动包，
    // 避免 move/scroll 分包导致的竞态（滚到桌面/错误窗口）。
    if (_touchpadPointers.length == 2) {
      final positions = _touchpadPointers.values.toList();
      final leftFinger =
          (positions[0].dx <= positions[1].dx) ? positions[0] : positions[1];
      final pos = _calculatePositionPercent(leftFinger);
      if (pos != null) _lastScrollAnchor = (x: pos.xPercent, y: pos.yPercent);
    } else if (_pinchFocalPoint != null) {
      // Fallback: use the two-finger center.
      final pos = _calculatePositionPercent(_pinchFocalPoint!);
      if (pos != null) _lastScrollAnchor = (x: pos.xPercent, y: pos.yPercent);
    }
    final speed = StreamingSettings.touchpadTwoFingerScrollSpeed;
    final sign = StreamingSettings.touchpadTwoFingerScrollInvert ? -1.0 : 1.0;
    _scrollController.doScroll(0, deltaY * speed * sign);
  }

  void _handlePinchZoom(double scaleChange) {
    if (!StreamingSettings.touchpadTwoFingerZoom) return;
    if (scaleChange.isNaN || scaleChange.isInfinite) return;
    // Prevent tiny jitter from causing the scale to get "stuck".
    if ((scaleChange - 1.0).abs() < 0.005) {
      return;
    }

    setState(() {
      double newScale = (_videoScale * scaleChange).clamp(1.0, _maxVideoScale);

      // Allow zooming back to 1.0 reliably.
      if (newScale <= 1.001) {
        _videoScale = 1.0;
        _videoOffset = Offset.zero;
      } else if (_pinchFocalPoint != null && renderBox != null) {
        Offset localFocal = renderBox!.globalToLocal(_pinchFocalPoint!);
        Offset viewCenter =
            Offset(renderBox!.size.width / 2, renderBox!.size.height / 2);

        Offset videoPoint =
            viewCenter + (localFocal - viewCenter - _videoOffset) / _videoScale;
        Offset newOffset =
            localFocal - viewCenter - (videoPoint - viewCenter) * newScale;

        if (_lastPinchFocalPoint != null) {
          Offset lastLocalFocal =
              renderBox!.globalToLocal(_lastPinchFocalPoint!);
          Offset focalDelta = localFocal - lastLocalFocal;
          newOffset += focalDelta;
        }

        final size = renderBox?.size;
        _videoScale = newScale;
        _videoOffset = (size == null)
            ? newOffset
            : clampVideoOffsetToBounds(
                size: size,
                scale: newScale,
                offset: newOffset,
              );
      } else {
        final size = renderBox?.size ?? _lastRenderSize;
        _videoScale = newScale;
        if (size != null) {
          _videoOffset = clampVideoOffsetToBounds(
            size: size,
            scale: newScale,
            offset: _videoOffset,
          );
        }
      }

      _lastPinchFocalPoint = _pinchFocalPoint;
    });
  }
}
