import 'package:cloudplayplus/utils/input/coordinate_mapping.dart';
import 'package:test/test.dart';

void main() {
  group('coordinate mapping', () {
    test('mapContentNormalizedToWindowPixel clamps and maps', () {
      final map = ContentToWindowMap(
        contentRect: const RectD(left: 0, top: 0, width: 1000, height: 500),
        windowRect: const RectD(left: 100, top: 200, width: 1000, height: 500),
      );

      expect(mapContentNormalizedToWindowPixel(map: map, u: 0, v: 0),
          const PointD(100, 200));
      expect(mapContentNormalizedToWindowPixel(map: map, u: 1, v: 1),
          const PointD(1100, 700));
      expect(mapContentNormalizedToWindowPixel(map: map, u: 0.5, v: 0.5),
          const PointD(600, 450));
      expect(mapContentNormalizedToWindowPixel(map: map, u: -1, v: 2),
          const PointD(100, 700));
    });

    test('mapViewPointToContentNormalized handles letterbox', () {
      final content = const RectD(left: 0, top: 62.5, width: 1200, height: 675);

      final topEdge = mapViewPointToContentNormalized(
        contentRect: content,
        viewPoint: const PointD(600, 62.5),
      );
      expect(topEdge.insideContent, isTrue);
      expect(topEdge.u, closeTo(0.5, 1e-9));
      expect(topEdge.v, closeTo(0, 1e-9));

      final inBar = mapViewPointToContentNormalized(
        contentRect: content,
        viewPoint: const PointD(600, 0),
      );
      expect(inBar.insideContent, isFalse);
      expect(inBar.v, closeTo(0, 1e-9));
    });
  });
}

