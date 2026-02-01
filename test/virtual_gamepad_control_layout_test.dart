import 'dart:ui';

import 'package:cloudplayplus/core/blocks/virtual_gamepad/control_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clampControlCenterNorm clamps using size/2 radius', () {
    // sizeNorm=0.2 => r=0.1
    final c = clampControlCenterNorm(
      center: const Offset(-1, 2),
      sizeNorm: 0.2,
    );
    expect(c.dx, 0.1);
    expect(c.dy, 0.9);
  });

  test('roundCenterNorm rounds to 3 decimals by default', () {
    final c = roundCenterNorm(const Offset(0.12349, 0.98751));
    expect(c.dx, 0.123);
    expect(c.dy, 0.988);
  });
}

