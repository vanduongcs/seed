import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class OfflineGrainAnalyzer {
  Future<OfflineGrainResult> analyze(
    Uint8List imageBytes, {
    double? referencePixels,
    double? referenceMm,
  }) async {
    final startedAt = DateTime.now();
    final source = img.decodeImage(imageBytes);
    if (source == null) {
      throw const OfflineGrainException('Khong doc duoc anh dau vao.');
    }

    final working = img.copyResize(
      source,
      width: math.min(source.width, 768),
      interpolation: img.Interpolation.linear,
    );
    final mask = _segmentSeeds(working);
    final components = _measureComponents(
      mask,
      sourceWidth: source.width,
      sourceHeight: source.height,
    );
    final overlay = _buildOverlay(source, mask, components);
    final elapsed = DateTime.now().difference(startedAt).inMilliseconds;

    return OfflineGrainResult(
      imageWidth: source.width,
      imageHeight: source.height,
      maskWidth: mask.width,
      maskHeight: mask.height,
      modelInputWidth: working.width,
      modelInputHeight: working.height,
      elapsedMs: elapsed,
      measurements: components,
      overlayPngBytes: overlay,
      referencePixels: referencePixels,
      referenceMm: referenceMm,
    );
  }

  _Mask _segmentSeeds(img.Image image) {
    final gray = Uint8List(image.width * image.height);
    final histogram = List<int>.filled(256, 0);
    var offset = 0;

    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        final value =
            (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);
        gray[offset++] = value;
        histogram[value]++;
      }
    }

    final threshold = _otsuThreshold(histogram, gray.length);
    final brightPixels = gray.where((value) => value > threshold).length;
    final detectBrightSeeds = brightPixels < gray.length / 2;
    final mask = Uint8List(gray.length);

    for (var i = 0; i < gray.length; i++) {
      mask[i] = detectBrightSeeds
          ? (gray[i] > threshold ? 1 : 0)
          : (gray[i] < threshold ? 1 : 0);
    }

    return _Mask(width: image.width, height: image.height, data: mask);
  }

  int _otsuThreshold(List<int> histogram, int total) {
    var sum = 0;
    for (var i = 0; i < histogram.length; i++) {
      sum += i * histogram[i];
    }

    var sumBackground = 0;
    var weightBackground = 0;
    var bestVariance = -1.0;
    var bestThreshold = 128;

    for (var threshold = 0; threshold < histogram.length; threshold++) {
      weightBackground += histogram[threshold];
      if (weightBackground == 0) continue;

      final weightForeground = total - weightBackground;
      if (weightForeground == 0) break;

      sumBackground += threshold * histogram[threshold];
      final meanBackground = sumBackground / weightBackground;
      final meanForeground = (sum - sumBackground) / weightForeground;
      final variance = weightBackground *
          weightForeground *
          math.pow(meanBackground - meanForeground, 2);

      if (variance > bestVariance) {
        bestVariance = variance.toDouble();
        bestThreshold = threshold;
      }
    }

    return bestThreshold;
  }

  List<OfflineGrainMeasurement> _measureComponents(
    _Mask mask, {
    required int sourceWidth,
    required int sourceHeight,
  }) {
    final visited = Uint8List(mask.data.length);
    final queue = Queue<int>();
    final minArea = math.max(12, (mask.data.length * 0.000035).round());
    final maxArea = math.max(minArea + 1, (mask.data.length * 0.030).round());
    final scaleX = sourceWidth / mask.width;
    final scaleY = sourceHeight / mask.height;
    final measurements = <OfflineGrainMeasurement>[];

    for (var start = 0; start < mask.data.length; start++) {
      if (visited[start] == 1 || mask.data[start] == 0) continue;

      var area = 0;
      var minX = mask.width;
      var minY = mask.height;
      var maxX = 0;
      var maxY = 0;
      var sumX = 0;
      var sumY = 0;
      visited[start] = 1;
      queue.add(start);

      while (queue.isNotEmpty) {
        final idx = queue.removeFirst();
        final x = idx % mask.width;
        final y = idx ~/ mask.width;
        area++;
        sumX += x;
        sumY += y;
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;

        for (final next in _neighbors(idx, x, y, mask.width, mask.height)) {
          if (visited[next] == 1 || mask.data[next] == 0) continue;
          visited[next] = 1;
          queue.add(next);
        }
      }

      if (area < minArea || area > maxArea) continue;
      final width = (maxX - minX + 1) * scaleX;
      final height = (maxY - minY + 1) * scaleY;
      measurements.add(OfflineGrainMeasurement(
        id: measurements.length + 1,
        areaPx: area * scaleX * scaleY,
        lengthPx: math.max(width, height),
        widthPx: math.min(width, height),
        centroidX: (sumX / area) * scaleX,
        centroidY: (sumY / area) * scaleY,
        bboxX: minX * scaleX,
        bboxY: minY * scaleY,
        bboxW: width,
        bboxH: height,
      ));
    }
    return measurements;
  }

  Iterable<int> _neighbors(int idx, int x, int y, int width, int height) sync* {
    if (x > 0) yield idx - 1;
    if (x < width - 1) yield idx + 1;
    if (y > 0) yield idx - width;
    if (y < height - 1) yield idx + width;
  }

  Uint8List _buildOverlay(
    img.Image source,
    _Mask mask,
    List<OfflineGrainMeasurement> measurements,
  ) {
    const maxSide = 900;
    final scale =
        math.min(1.0, maxSide / math.max(source.width, source.height));
    final preview = img.copyResize(
      source,
      width: math.max(1, (source.width * scale).round()),
      height: math.max(1, (source.height * scale).round()),
    );

    for (var y = 0; y < preview.height; y++) {
      for (var x = 0; x < preview.width; x++) {
        final mx =
            (x / preview.width * mask.width).floor().clamp(0, mask.width - 1);
        final my = (y / preview.height * mask.height)
            .floor()
            .clamp(0, mask.height - 1);
        if (mask.data[my * mask.width + mx] == 0) continue;
        final p = preview.getPixel(x, y);
        preview.setPixelRgb(
          x,
          y,
          (p.r * 0.58 + 46 * 0.42).round(),
          (p.g * 0.58 + 137 * 0.42).round(),
          (p.b * 0.58 + 87 * 0.42).round(),
        );
      }
    }

    final lineColor = img.ColorRgb8(28, 87, 57);
    _drawMaskContour(preview, mask, lineColor);
    for (final item in measurements) {
      img.drawRect(
        preview,
        x1: (item.bboxX * scale).round().clamp(0, preview.width - 1),
        y1: (item.bboxY * scale).round().clamp(0, preview.height - 1),
        x2: ((item.bboxX + item.bboxW) * scale).round().clamp(
              0,
              preview.width - 1,
            ),
        y2: ((item.bboxY + item.bboxH) * scale).round().clamp(
              0,
              preview.height - 1,
            ),
        color: lineColor,
        thickness: 1,
      );
    }
    return Uint8List.fromList(img.encodePng(preview));
  }

  void _drawMaskContour(img.Image preview, _Mask mask, img.Color color) {
    for (var y = 1; y < preview.height - 1; y++) {
      for (var x = 1; x < preview.width - 1; x++) {
        final mx =
            (x / preview.width * mask.width).floor().clamp(0, mask.width - 1);
        final my = (y / preview.height * mask.height)
            .floor()
            .clamp(0, mask.height - 1);
        if (mask.data[my * mask.width + mx] == 0) continue;

        final left =
            mask.data[my * mask.width + (mx - 1).clamp(0, mask.width - 1)];
        final right =
            mask.data[my * mask.width + (mx + 1).clamp(0, mask.width - 1)];
        final up =
            mask.data[(my - 1).clamp(0, mask.height - 1) * mask.width + mx];
        final down =
            mask.data[(my + 1).clamp(0, mask.height - 1) * mask.width + mx];
        if (left == 0 || right == 0 || up == 0 || down == 0) {
          preview.setPixel(x, y, color);
        }
      }
    }
  }
}

class OfflineGrainResult {
  final int imageWidth;
  final int imageHeight;
  final int maskWidth;
  final int maskHeight;
  final int modelInputWidth;
  final int modelInputHeight;
  final int elapsedMs;
  final List<OfflineGrainMeasurement> measurements;
  final Uint8List overlayPngBytes;
  final double? referencePixels;
  final double? referenceMm;

  const OfflineGrainResult({
    required this.imageWidth,
    required this.imageHeight,
    required this.maskWidth,
    required this.maskHeight,
    required this.modelInputWidth,
    required this.modelInputHeight,
    required this.elapsedMs,
    required this.measurements,
    required this.overlayPngBytes,
    this.referencePixels,
    this.referenceMm,
  });

  int get count => measurements.length;

  double? get mmPerPixel {
    final px = referencePixels;
    final mm = referenceMm;
    if (px == null || mm == null || px <= 0 || mm <= 0) return null;
    return mm / px;
  }

  double get meanAreaPx => measurements.isEmpty
      ? 0
      : measurements.fold<double>(0, (sum, item) => sum + item.areaPx) /
          measurements.length;

  double get meanLengthPx => measurements.isEmpty
      ? 0
      : measurements.fold<double>(0, (sum, item) => sum + item.lengthPx) /
          measurements.length;

  double get meanWidthPx => measurements.isEmpty
      ? 0
      : measurements.fold<double>(0, (sum, item) => sum + item.widthPx) /
          measurements.length;

  double? get meanAreaMm2 {
    final scale = mmPerPixel;
    if (scale == null) return null;
    return meanAreaPx * scale * scale;
  }

  double? get meanLengthMm {
    final scale = mmPerPixel;
    if (scale == null) return null;
    return meanLengthPx * scale;
  }

  double? get meanWidthMm {
    final scale = mmPerPixel;
    if (scale == null) return null;
    return meanWidthPx * scale;
  }
}

class OfflineGrainMeasurement {
  final int id;
  final double areaPx;
  final double lengthPx;
  final double widthPx;
  final double centroidX;
  final double centroidY;
  final double bboxX;
  final double bboxY;
  final double bboxW;
  final double bboxH;

  const OfflineGrainMeasurement({
    required this.id,
    required this.areaPx,
    required this.lengthPx,
    required this.widthPx,
    required this.centroidX,
    required this.centroidY,
    required this.bboxX,
    required this.bboxY,
    required this.bboxW,
    required this.bboxH,
  });
}

class OfflineGrainException implements Exception {
  final String message;

  const OfflineGrainException(this.message);

  @override
  String toString() => message;
}

class _Mask {
  final int width;
  final int height;
  final Uint8List data;

  const _Mask({required this.width, required this.height, required this.data});
}
