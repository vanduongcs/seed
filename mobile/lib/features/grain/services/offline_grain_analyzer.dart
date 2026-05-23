import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class OfflineGrainAnalyzer {
  static const modelAssetPath = 'assets/models/best_float16.tflite';

  // Keep these aligned with backend/config/grain.settings.json.
  static const _inputSize = 640;
  static const _protoSize = 160;
  static const _maxSide = 1024;
  static const _confidence = 0.03;
  static const _iou = 0.60;
  static const _maxDetections = 5000;
  static const _minArea = 12;
  static const _maxArea = 200000;
  static const _maxAspectRatio = 20.0;
  static const _minSolidity = 0.4;
  static const _minExtent = 0.15;

  Interpreter? _interpreter;

  Future<OfflineModelInfo> loadModelInfo() async {
    final interpreter =
        _interpreter ??= await Interpreter.fromAsset(modelAssetPath);
    return OfflineModelInfo(
      modelAssetPath: modelAssetPath,
      inputTensors: interpreter.getInputTensors().map(_tensorInfo).toList(),
      outputTensors: interpreter.getOutputTensors().map(_tensorInfo).toList(),
    );
  }

  Future<OfflineAnalyzeResult> analyze(
    Uint8List imageBytes, {
    double? referencePixels,
    double? referenceMm,
    double? referenceX1,
    double? referenceY1,
    double? referenceX2,
    double? referenceY2,
  }) async {
    final interpreter =
        _interpreter ??= await Interpreter.fromAsset(modelAssetPath);
    final original = img.decodeImage(imageBytes);
    if (original == null) throw StateError('Cannot decode selected image.');

    final originalWidth = original.width;
    final originalHeight = original.height;
    final longestSide = math.max(originalWidth, originalHeight);
    final scale = longestSide > _maxSide ? _maxSide / longestSide : 1.0;
    final processed = scale < 1.0
        ? img.copyResize(
            original,
            width: (originalWidth * scale).round(),
            height: (originalHeight * scale).round(),
            interpolation: img.Interpolation.average,
          )
        : img.Image.from(original);

    final squareSide = math.max(processed.width, processed.height);
    final square = img.Image(width: squareSide, height: squareSide, numChannels: 3);
    img.fill(square, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(square, processed, dstX: 0, dstY: 0);
    final resized = img.copyResize(
      square,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.linear,
    );

    final input = List.generate(
      1,
      (_) => List.generate(
        _inputSize,
        (y) => List.generate(_inputSize, (x) {
          final pixel = resized.getPixel(x, y);
          return [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
        }),
      ),
    );
    final predictions = List.generate(
      1,
      (_) => List.generate(38, (_) => List.filled(8400, 0.0)),
    );
    final protos = List.generate(
      1,
      (_) => List.generate(
        _protoSize,
        (_) => List.generate(_protoSize, (_) => List.filled(32, 0.0)),
      ),
    );
    interpreter.runForMultipleInputs([input], {0: predictions, 1: protos});

    final detections = _decodePredictions(predictions[0]);
    final instances = detections
        .map(
          (detection) => _decodeMask(
            protos[0],
            detection,
            width: processed.width,
            height: processed.height,
            paddedSide: squareSide,
          ),
        )
        .whereType<_Instance>()
        .toList();
    final filtered = _filterAndMeasure(
      instances,
      width: processed.width,
      height: processed.height,
      scale: scale,
      referencePixels: referencePixels,
      referenceMm: referenceMm,
      referenceX1: referenceX1,
      referenceY1: referenceY1,
      referenceX2: referenceX2,
      referenceY2: referenceY2,
    );
    final overlay = _renderOverlay(processed, filtered);
    final mask = _renderMask(filtered);

    final seedCandidateCount =
        instances.where((instance) => instance.classId == 0).length;
    final refCandidateCount = instances.length - seedCandidateCount;
    return OfflineAnalyzeResult(
      overlayPng: Uint8List.fromList(img.encodePng(overlay)),
      maskPng: Uint8List.fromList(img.encodePng(mask)),
      image: {
        'width': processed.width,
        'height': processed.height,
        'original_width': originalWidth,
        'original_height': originalHeight,
        'scale': _round(scale, 6),
      },
      measurements: filtered.measurements,
      summary: _summaryFor(filtered.measurements),
      calibration: {
        'referencePixels': referencePixels ?? 0,
        'referenceMm': referenceMm ?? 0,
        'referencePixelSpace': 'original',
        'enabled': filtered.mmPerPixel > 0,
        'mm_per_pixel': filtered.mmPerPixel,
        'referenceX1': referenceX1 ?? -1,
        'referenceY1': referenceY1 ?? -1,
        'referenceX2': referenceX2 ?? -1,
        'referenceY2': referenceY2 ?? -1,
        'excluded_reference_object_count':
            filtered.excludedReferenceObjectCount,
      },
      segmentation: {
        'pipeline': 'yolo_sam_onnx',
        'model': modelAssetPath,
        'refiner': 'disabled',
        'refiner_applied': false,
        'confidence': _confidence,
        'iou': _iou,
        'max_det': _maxDetections,
        'tiled_inference': false,
        'candidate_count': detections.length,
        'refined_candidate_count': instances.length,
        'seed_candidate_count': seedCandidateCount,
        'ref_candidate_count': refCandidateCount,
        'segment_count_before_filter': instances.length,
        'segment_count': filtered.measurements.length,
        'marker_count': filtered.measurements.length,
        'mask_filter': {
          'component_count_before': instances.length,
          'component_count_after': filtered.measurements.length,
          'ignored_ref_count': refCandidateCount,
          'excluded_reference_object_count':
              filtered.excludedReferenceObjectCount,
        },
        'effective_thresholds': {
          'minArea': _minArea,
          'maxArea': _maxArea,
          'maxSegmentAspectRatio': _maxAspectRatio,
          'minSegmentSolidity': _minSolidity,
          'minSegmentExtent': _minExtent,
        },
        'offline': true,
      },
    );
  }

  List<_Detection> _decodePredictions(List<List<double>> prediction) {
    final candidates = <_Detection>[];
    for (var i = 0; i < 8400; i++) {
      final seedScore = prediction[4][i];
      final refScore = prediction[5][i];
      final classId = seedScore >= refScore ? 0 : 1;
      final score = classId == 0 ? seedScore : refScore;
      if (score < _confidence) continue;
      final cx = prediction[0][i];
      final cy = prediction[1][i];
      final width = prediction[2][i];
      final height = prediction[3][i];
      candidates.add(
        _Detection(
          score: score,
          classId: classId,
          x1: cx - width / 2,
          y1: cy - height / 2,
          x2: cx + width / 2,
          y2: cy + height / 2,
          coefficients: List.generate(32, (c) => prediction[6 + c][i]),
        ),
      );
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));
    final kept = <_Detection>[];
    for (final candidate in candidates) {
      if (kept.every((other) => _boxIou(candidate, other) < _iou)) {
        kept.add(candidate);
        if (kept.length >= _maxDetections) break;
      }
    }
    return kept;
  }

  _Instance? _decodeMask(
    List<List<List<double>>> protos,
    _Detection detection, {
    required int width,
    required int height,
    required int paddedSide,
  }) {
    final pixels = Uint8List(width * height);
    final scale = paddedSide / _inputSize;
    final x1 = (detection.x1 * scale).floor().clamp(0, width);
    final y1 = (detection.y1 * scale).floor().clamp(0, height);
    final x2 = (detection.x2 * scale).ceil().clamp(0, width);
    final y2 = (detection.y2 * scale).ceil().clamp(0, height);
    if (x2 <= x1 || y2 <= y1) return null;

    var area = 0;
    for (var y = y1; y < y2; y++) {
      final protoY = (y / paddedSide) * _protoSize - 0.5;
      for (var x = x1; x < x2; x++) {
        final protoX = (x / paddedSide) * _protoSize - 0.5;
        var logit = 0.0;
        for (var c = 0; c < 32; c++) {
          logit += detection.coefficients[c] *
              _bilinearProto(protos, protoX, protoY, c);
        }
        if (_sigmoid(logit) <= 0.5) continue;
        pixels[y * width + x] = 1;
        area++;
      }
    }
    if (area == 0) return null;
    return _Instance(
      mask: pixels,
      confidence: detection.score,
      classId: detection.classId,
    );
  }

  _FilteredResult _filterAndMeasure(
    List<_Instance> instances, {
    required int width,
    required int height,
    required double scale,
    required double? referencePixels,
    required double? referenceMm,
    required double? referenceX1,
    required double? referenceY1,
    required double? referenceX2,
    required double? referenceY2,
  }) {
    final labels = Int32List(width * height);
    final measurements = <Map<String, dynamic>>[];
    final mmPerPixel = (referencePixels != null &&
            referencePixels > 0 &&
            referenceMm != null &&
            referenceMm > 0)
        ? referenceMm / (referencePixels * scale)
        : 0.0;
    var excludedReferenceObjectCount = 0;
    final hasReferenceLine = referenceX1 != null &&
        referenceY1 != null &&
        referenceX2 != null &&
        referenceY2 != null &&
        (referenceX1 != referenceX2 || referenceY1 != referenceY2);
    final processedLine = hasReferenceLine
        ? (
            _Point(referenceX1! * scale, referenceY1! * scale),
            _Point(referenceX2! * scale, referenceY2! * scale),
          )
        : null;
    instances.sort((a, b) => b.confidence.compareTo(a.confidence));
    for (final instance in instances) {
      if (instance.classId != 0) continue;
      if (processedLine != null &&
          _isReferenceObjectMask(
            instance.mask,
            width,
            height,
            processedLine.$1,
            processedLine.$2,
          )) {
        excludedReferenceObjectCount++;
        continue;
      }
      final available = Uint8List(width * height);
      for (var i = 0; i < available.length; i++) {
        if (instance.mask[i] != 0 && labels[i] == 0) available[i] = 1;
      }
      final metrics = _maskMetrics(available, width, height);
      if (metrics == null) continue;
      final area = metrics['area_px'] as int;
      final aspect = metrics['aspect_ratio'] as double;
      final solidity = metrics['solidity'] as double;
      final extent = metrics['extent'] as double;
      if (area < _minArea || area > _maxArea) continue;
      if (aspect > _maxAspectRatio) continue;
      if (solidity < _minSolidity || extent < _minExtent) continue;

      final id = measurements.length + 1;
      for (var i = 0; i < available.length; i++) {
        if (available[i] != 0) labels[i] = id;
      }
      measurements.add({
        'id': id,
        ...metrics,
        'area_mm2': mmPerPixel == 0
            ? 0.0
            : _round(area * mmPerPixel * mmPerPixel, 6),
        'length_mm': mmPerPixel == 0
            ? 0.0
            : _round((metrics['length_px'] as double) * mmPerPixel, 6),
        'width_mm': mmPerPixel == 0
            ? 0.0
            : _round((metrics['width_px'] as double) * mmPerPixel, 6),
        'confidence': _round(instance.confidence, 6),
        'class_id': 0,
        'class_name': 'seed',
      });
    }
    return _FilteredResult(
      labels: labels,
      measurements: measurements,
      mmPerPixel: mmPerPixel,
      width: width,
      height: height,
      excludedReferenceObjectCount: excludedReferenceObjectCount,
    );
  }

  Map<String, dynamic>? _maskMetrics(
    Uint8List mask,
    int width,
    int height,
  ) {
    final points = <_Point>[];
    var sumX = 0.0;
    var sumY = 0.0;
    var minX = width;
    var minY = height;
    var maxX = -1;
    var maxY = -1;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (mask[y * width + x] == 0) continue;
        points.add(_Point(x.toDouble(), y.toDouble()));
        sumX += x;
        sumY += y;
        minX = math.min(minX, x);
        minY = math.min(minY, y);
        maxX = math.max(maxX, x);
        maxY = math.max(maxY, y);
      }
    }
    if (points.isEmpty) return null;
    final hull = _convexHull(points);
    final hullArea = math.max(_polygonArea(hull), 1.0);
    final rectangle = _minimumBoundingRectangle(hull);
    final bboxWidth = maxX - minX + 1;
    final bboxHeight = maxY - minY + 1;
    final area = points.length;
    return {
      'area_px': area,
      'length_px': _round(rectangle.length, 3),
      'width_px': _round(rectangle.width, 3),
      'centroid_x': _round(sumX / area, 3),
      'centroid_y': _round(sumY / area, 3),
      'bbox_x': minX,
      'bbox_y': minY,
      'bbox_w': bboxWidth,
      'bbox_h': bboxHeight,
      'angle_deg': _round(rectangle.angleDegrees, 3),
      'solidity': _round(area / hullArea, 6),
      'extent': _round(area / math.max(bboxWidth * bboxHeight, 1), 6),
      'aspect_ratio': _round(rectangle.length / rectangle.width, 6),
    };
  }

  img.Image _renderOverlay(img.Image rgb, _FilteredResult result) {
    final overlay = img.Image.from(rgb);
    const palette = [
      [45, 108, 191],
      [219, 87, 86],
      [73, 160, 120],
      [235, 174, 73],
      [132, 98, 174],
      [77, 176, 196],
      [201, 112, 165],
      [122, 126, 135],
    ];
    for (var y = 0; y < result.height; y++) {
      for (var x = 0; x < result.width; x++) {
        final label = result.labels[y * result.width + x];
        if (label <= 0) continue;
        final color = palette[(label - 1) % palette.length];
        final source = overlay.getPixel(x, y);
        overlay.setPixelRgb(
          x,
          y,
          (source.r * 0.55 + color[0] * 0.45).round(),
          (source.g * 0.55 + color[1] * 0.45).round(),
          (source.b * 0.55 + color[2] * 0.45).round(),
        );
      }
    }
    return overlay;
  }

  img.Image _renderMask(_FilteredResult result) {
    final mask = img.Image(
      width: result.width,
      height: result.height,
      numChannels: 3,
    );
    for (var y = 0; y < result.height; y++) {
      for (var x = 0; x < result.width; x++) {
        final value = result.labels[y * result.width + x] > 0 ? 255 : 0;
        mask.setPixelRgb(x, y, value, value, value);
      }
    }
    return mask;
  }

  void close() {
    _interpreter?.close();
    _interpreter = null;
  }
}

double _bilinearProto(
  List<List<List<double>>> protos,
  double x,
  double y,
  int channel,
) {
  final x0 = x.floor().clamp(0, OfflineGrainAnalyzer._protoSize - 1);
  final y0 = y.floor().clamp(0, OfflineGrainAnalyzer._protoSize - 1);
  final x1 = (x0 + 1).clamp(0, OfflineGrainAnalyzer._protoSize - 1);
  final y1 = (y0 + 1).clamp(0, OfflineGrainAnalyzer._protoSize - 1);
  final dx = (x - x0).clamp(0.0, 1.0);
  final dy = (y - y0).clamp(0.0, 1.0);
  final top = protos[y0][x0][channel] * (1 - dx) +
      protos[y0][x1][channel] * dx;
  final bottom = protos[y1][x0][channel] * (1 - dx) +
      protos[y1][x1][channel] * dx;
  return top * (1 - dy) + bottom * dy;
}

double _boxIou(_Detection a, _Detection b) {
  final x1 = math.max(a.x1, b.x1);
  final y1 = math.max(a.y1, b.y1);
  final x2 = math.min(a.x2, b.x2);
  final y2 = math.min(a.y2, b.y2);
  final intersection = math.max(0.0, x2 - x1) * math.max(0.0, y2 - y1);
  final aArea = math.max(0.0, a.x2 - a.x1) * math.max(0.0, a.y2 - a.y1);
  final bArea = math.max(0.0, b.x2 - b.x1) * math.max(0.0, b.y2 - b.y1);
  final union = aArea + bArea - intersection;
  return union == 0 ? 0 : intersection / union;
}

List<_Point> _convexHull(List<_Point> points) {
  final sorted = [...points]
    ..sort((a, b) {
      final byX = a.x.compareTo(b.x);
      return byX != 0 ? byX : a.y.compareTo(b.y);
    });
  if (sorted.length <= 2) return sorted;
  final lower = <_Point>[];
  for (final point in sorted) {
    while (lower.length >= 2 &&
        _cross(lower[lower.length - 2], lower.last, point) <= 0) {
      lower.removeLast();
    }
    lower.add(point);
  }
  final upper = <_Point>[];
  for (final point in sorted.reversed) {
    while (upper.length >= 2 &&
        _cross(upper[upper.length - 2], upper.last, point) <= 0) {
      upper.removeLast();
    }
    upper.add(point);
  }
  lower.removeLast();
  upper.removeLast();
  return [...lower, ...upper];
}

double _polygonArea(List<_Point> points) {
  if (points.length < 3) return 1.0;
  var sum = 0.0;
  for (var i = 0; i < points.length; i++) {
    final next = points[(i + 1) % points.length];
    sum += points[i].x * next.y - next.x * points[i].y;
  }
  return sum.abs() / 2;
}

_RectangleMetrics _minimumBoundingRectangle(List<_Point> hull) {
  if (hull.length < 2) {
    return const _RectangleMetrics(length: 1, width: 1, angleDegrees: 0);
  }
  var bestArea = double.infinity;
  var best = const _RectangleMetrics(length: 1, width: 1, angleDegrees: 0);
  for (var i = 0; i < hull.length; i++) {
    final next = hull[(i + 1) % hull.length];
    final angle = math.atan2(next.y - hull[i].y, next.x - hull[i].x);
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    var minX = double.infinity;
    var maxX = double.negativeInfinity;
    var minY = double.infinity;
    var maxY = double.negativeInfinity;
    for (final point in hull) {
      final rx = point.x * cosA + point.y * sinA;
      final ry = -point.x * sinA + point.y * cosA;
      minX = math.min(minX, rx);
      maxX = math.max(maxX, rx);
      minY = math.min(minY, ry);
      maxY = math.max(maxY, ry);
    }
    final rectWidth = math.max(maxX - minX, 1.0);
    final rectHeight = math.max(maxY - minY, 1.0);
    final area = rectWidth * rectHeight;
    if (area < bestArea) {
      bestArea = area;
      best = _RectangleMetrics(
        length: math.max(rectWidth, rectHeight),
        width: math.min(rectWidth, rectHeight),
        angleDegrees: angle * 180 / math.pi,
      );
    }
  }
  return best;
}

double _cross(_Point origin, _Point a, _Point b) =>
    (a.x - origin.x) * (b.y - origin.y) -
    (a.y - origin.y) * (b.x - origin.x);

double _sigmoid(double value) =>
    1 / (1 + math.exp(-value.clamp(-88.0, 88.0)));

bool _isReferenceObjectMask(
  Uint8List mask,
  int width,
  int height,
  _Point start,
  _Point end,
) {
  final dx = end.x - start.x;
  final dy = end.y - start.y;
  final length = math.sqrt(dx * dx + dy * dy);
  if (length <= 0) return false;
  final samples = math.max(2, length.ceil() + 1);
  var covered = 0;
  for (var i = 0; i < samples; i++) {
    final ratio = i / (samples - 1);
    final x = (start.x + dx * ratio).round().clamp(0, width - 1).toInt();
    final y = (start.y + dy * ratio).round().clamp(0, height - 1).toInt();
    if (mask[y * width + x] != 0) covered++;
  }
  final midX = ((start.x + end.x) / 2).round().clamp(0, width - 1).toInt();
  final midY = ((start.y + end.y) / 2).round().clamp(0, height - 1).toInt();
  final midpointInside = mask[midY * width + midX] != 0;
  return midpointInside && covered / samples >= 0.55;
}

double _round(num value, int decimals) {
  final factor = math.pow(10, decimals).toDouble();
  return (value * factor).round() / factor;
}

Map<String, dynamic> _summaryFor(List<Map<String, dynamic>> measurements) {
  if (measurements.isEmpty) {
    return {
      'count': 0,
      'total_area_px': 0,
      'mean_area_px': 0,
      'mean_length_px': 0,
      'mean_width_px': 0,
      'mean_area_mm2': 0,
      'mean_length_mm': 0,
      'mean_width_mm': 0,
    };
  }
  double mean(String key) => _round(
        measurements.fold<double>(
              0,
              (total, item) => total + ((item[key] as num?)?.toDouble() ?? 0),
            ) /
            measurements.length,
        6,
      );
  return {
    'count': measurements.length,
    'total_area_px': measurements.fold<int>(
      0,
      (total, item) => total + ((item['area_px'] as num?)?.toInt() ?? 0),
    ),
    'mean_area_px': mean('area_px'),
    'mean_length_px': mean('length_px'),
    'mean_width_px': mean('width_px'),
    'mean_area_mm2': mean('area_mm2'),
    'mean_length_mm': mean('length_mm'),
    'mean_width_mm': mean('width_mm'),
  };
}

OfflineTensorInfo _tensorInfo(Tensor tensor) => OfflineTensorInfo(
      name: tensor.name,
      shape: List<int>.from(tensor.shape),
      type: tensor.type.toString(),
    );

class _Detection {
  final double score;
  final int classId;
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final List<double> coefficients;

  const _Detection({
    required this.score,
    required this.classId,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.coefficients,
  });
}

class _Instance {
  final Uint8List mask;
  final double confidence;
  final int classId;

  const _Instance({
    required this.mask,
    required this.confidence,
    required this.classId,
  });
}

class _Point {
  final double x;
  final double y;

  const _Point(this.x, this.y);
}

class _RectangleMetrics {
  final double length;
  final double width;
  final double angleDegrees;

  const _RectangleMetrics({
    required this.length,
    required this.width,
    required this.angleDegrees,
  });
}

class _FilteredResult {
  final Int32List labels;
  final List<Map<String, dynamic>> measurements;
  final double mmPerPixel;
  final int width;
  final int height;
  final int excludedReferenceObjectCount;

  const _FilteredResult({
    required this.labels,
    required this.measurements,
    required this.mmPerPixel,
    required this.width,
    required this.height,
    required this.excludedReferenceObjectCount,
  });
}

class OfflineModelInfo {
  final String modelAssetPath;
  final List<OfflineTensorInfo> inputTensors;
  final List<OfflineTensorInfo> outputTensors;

  const OfflineModelInfo({
    required this.modelAssetPath,
    required this.inputTensors,
    required this.outputTensors,
  });
}

class OfflineTensorInfo {
  final String name;
  final List<int> shape;
  final String type;

  const OfflineTensorInfo({
    required this.name,
    required this.shape,
    required this.type,
  });
}

class OfflineAnalyzeResult {
  final Uint8List overlayPng;
  final Uint8List maskPng;
  final Map<String, dynamic> image;
  final List<Map<String, dynamic>> measurements;
  final Map<String, dynamic> summary;
  final Map<String, dynamic> calibration;
  final Map<String, dynamic> segmentation;

  const OfflineAnalyzeResult({
    required this.overlayPng,
    required this.maskPng,
    required this.image,
    required this.measurements,
    required this.summary,
    required this.calibration,
    required this.segmentation,
  });

  Map<String, dynamic> asApiJson(String fileName) => {
        'run': {
          'id': 'local-${DateTime.now().millisecondsSinceEpoch}',
          'sourceFileName': fileName,
          'localOnly': true,
          'offline': true,
          'createdAt': DateTime.now().toIso8601String(),
        },
        'image': image,
        'summary': summary,
        'segmentation': segmentation,
        'calibration': calibration,
        'features': {
          'pipeline': 'yolo8_nano_segment',
          'source': 'mobile_tflite',
          'preprocess': {'enabled': false},
        },
        'measurements': measurements,
        'csv': '',
        'overlay_png_base64': base64Encode(overlayPng),
        'sam_mask_png_base64': base64Encode(maskPng),
        'labels_png_base64': '',
        'mask_png_base64': base64Encode(maskPng),
      };
}
