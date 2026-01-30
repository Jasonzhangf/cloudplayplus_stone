import 'package:cloudplayplus/utils/iterm2/iterm2_crop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('iTerm2 crop computation', () {
    test('prefers doc candidate when it fits without clamping', () {
      final res = computeIterm2CropRectNorm(
        fx: 450,
        fy: 350,
        fw: 300,
        fh: 200,
        wx: 500,
        wy: 400,
        ww: 1000,
        wh: 800,
      );
      expect(res, isNotNull);
      expect(res!.tag, 'winRel: fx, fy');
      expect(res.penalty, closeTo(0.0, 1e-9));
      expect(res.cropRectNorm['x'], closeTo(0.45, 1e-9));
      expect(res.cropRectNorm['y'], closeTo(0.4375, 1e-9));
      expect(res.cropRectNorm['w'], closeTo(0.3, 1e-9));
      expect(res.cropRectNorm['h'], closeTo(0.25, 1e-9));
    });

    test('prefers rel candidate when doc would overflow', () {
      final res = computeIterm2CropRectNorm(
        fx: 200,
        fy: 150,
        fw: 300,
        fh: 200,
        wx: 100,
        wy: 100,
        ww: 800,
        wh: 600,
      );
      expect(res, isNotNull);
      expect(res!.tag, 'winRel: fx, fy');
      expect(res.cropRectNorm['x'], closeTo(200 / 800, 1e-9));
      expect(res.cropRectNorm['y'], closeTo(150 / 600, 1e-9));
      expect(res.cropRectNorm['w'], closeTo(300 / 800, 1e-9));
      expect(res.cropRectNorm['h'], closeTo(200 / 600, 1e-9));
    });

    test('always returns a normalized rect in [0..1]', () {
      final res = computeIterm2CropRectNorm(
        fx: -1000,
        fy: 9999,
        fw: 5000,
        fh: 5000,
        wx: 0,
        wy: 0,
        ww: 1920,
        wh: 1080,
      );
      expect(res, isNotNull);
      final c = res!.cropRectNorm;
      for (final k in const ['x', 'y', 'w', 'h']) {
        expect(c[k], isNotNull);
        expect(c[k]!, inInclusiveRange(0.0, 1.0));
      }
      expect(c['w']!, greaterThan(0));
      expect(c['h']!, greaterThan(0));
    });

    test('falls back to window-relative frame when window origin mismatches',
        () {
      // Simulate: windowFrame is in screen coordinates, but session frame is already
      // window-relative. Using rel/doc candidates would clamp to y=0 and show the
      // wrong (top) panel; window-relative should win with minimal penalty.
      final res = computeIterm2CropRectNorm(
        fx: 0,
        fy: 300,
        fw: 800,
        fh: 300,
        wx: 2000,
        wy: 1200,
        ww: 800,
        wh: 900,
      );
      expect(res, isNotNull);
      expect(res!.tag.startsWith('winRel:'), isTrue);
      expect(res.cropRectNorm['x'], closeTo(0.0, 1e-9));
      expect(res.cropRectNorm['y'], closeTo(300 / 900, 1e-9));
      expect(res.cropRectNorm['w'], closeTo(1.0, 1e-9));
      expect(res.cropRectNorm['h'], closeTo(300 / 900, 1e-9));
    });
  });
}
