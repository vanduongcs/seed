import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

typedef OfflineProgressCallback = void Function(double value, String phase);

const _qcMadZThreshold = 4.0;
const _qcMinOutlierMetrics = 2;

class OfflineGrainAnalyzer {
  static const modelAssetPath = 'assets/models/best.onnx';

  // Keep these aligned with backend/config/grain.settings.json.
  static const _inputSize = 640;
  static const _protoSize = 160;
  static const _maxSide = 1024;
  static const _confidence = 0.05;
  static const _iou = 0.55;
  static const _maxDetections = 5000;
  static const _minArea = 20;
  static const _maxArea = 200000;
  static const _maxAspectRatio = 14.0;
  static const _minSolidity = 0.5;
  static const _minExtent = 0.2;
  static const _enableEnhancedPass = false;

  OrtSession? _session;

  Future<OfflineModelInfo> loadModelInfo() async {
    final session = await _loadSession();
    return OfflineModelInfo(
      modelAssetPath: modelAssetPath,
      inputTensors: [
        OfflineTensorInfo(
          name: session.inputNames.first,
          shape: const [1, 3, _inputSize, _inputSize],
          type: 'float32',
        ),
      ],
      outputTensors: [
        OfflineTensorInfo(
          name: session.outputNames.first,
          shape: const [1, 38, 8400],
          type: 'float32',
        ),
        OfflineTensorInfo(
          name: session.outputNames.last,
          shape: const [1, 32, _protoSize, _protoSize],
          type: 'float32',
        ),
      ],
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
    OfflineProgressCallback? onProgress,
  }) async {
    Future<void> reportProgress(double value, String phase) async {
      onProgress?.call(value, phase);
      await Future<void>.delayed(Duration.zero);
    }

    await reportProgress(54, 'Tải mô hình tối ưu trên thiết bị');
    final session = await _loadSession();
    await reportProgress(60, 'Chuẩn bị ảnh cho mô hình ONNX');
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
    final square =
        img.Image(width: squareSide, height: squareSide, numChannels: 3);
    img.fill(square, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(square, processed, dstX: 0, dstY: 0);
    final resized = img.copyResize(
      square,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.linear,
    );

    final input = Float32List(1 * 3 * _inputSize * _inputSize);
    const channelSize = _inputSize * _inputSize;
    for (var y = 0; y < _inputSize; y++) {
      for (var x = 0; x < _inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        final index = y * _inputSize + x;
        input[index] = pixel.r / 255.0;
        input[channelSize + index] = pixel.g / 255.0;
        input[channelSize * 2 + index] = pixel.b / 255.0;
      }
    }

    final inputTensor =
        await OrtValue.fromList(input, const [1, 3, _inputSize, _inputSize]);
    await reportProgress(68, 'Chạy YOLO ONNX trên thiết bị');
    final outputs = await session.run({session.inputNames.first: inputTensor});
    late final Float32List predictions;
    late final Float32List protos;
    try {
      predictions = Float32List.fromList(
        (await outputs[session.outputNames.first]!.asFlattenedList())
            .map((value) => (value as num).toDouble())
            .toList(),
      );
      protos = Float32List.fromList(
        (await outputs[session.outputNames.last]!.asFlattenedList())
            .map((value) => (value as num).toDouble())
            .toList(),
      );
    } finally {
      await inputTensor.dispose();
      for (final output in outputs.values) {
        await output.dispose();
      }
    }

    await reportProgress(82, 'Tạo mặt nạ, đo hạt và dựng ảnh');
    var predictionsEnhanced = predictions;
    var protosEnhanced = protos;
    if (_enableEnhancedPass) {
      final enhanced = _enhanceForDetection(processed);
      final enhancedSquare =
          img.Image(width: squareSide, height: squareSide, numChannels: 3);
      img.fill(enhancedSquare, color: img.ColorRgb8(255, 255, 255));
      img.compositeImage(enhancedSquare, enhanced, dstX: 0, dstY: 0);
      final enhancedResized = img.copyResize(
        enhancedSquare,
        width: _inputSize,
        height: _inputSize,
        interpolation: img.Interpolation.linear,
      );
      final enhancedInput = Float32List(1 * 3 * _inputSize * _inputSize);
      for (var y = 0; y < _inputSize; y++) {
        for (var x = 0; x < _inputSize; x++) {
          final pixel = enhancedResized.getPixel(x, y);
          final index = y * _inputSize + x;
          enhancedInput[index] = pixel.r / 255.0;
          enhancedInput[channelSize + index] = pixel.g / 255.0;
          enhancedInput[channelSize * 2 + index] = pixel.b / 255.0;
        }
      }
      final enhancedTensor = await OrtValue.fromList(
        enhancedInput,
        const [1, 3, _inputSize, _inputSize],
      );
      final enhancedOutputs = await session.run({
        session.inputNames.first: enhancedTensor,
      });
      try {
        predictionsEnhanced = Float32List.fromList(
          (await enhancedOutputs[session.outputNames.first]!.asFlattenedList())
              .map((value) => (value as num).toDouble())
              .toList(),
        );
        protosEnhanced = Float32List.fromList(
          (await enhancedOutputs[session.outputNames.last]!.asFlattenedList())
              .map((value) => (value as num).toDouble())
              .toList(),
        );
      } finally {
        await enhancedTensor.dispose();
        for (final output in enhancedOutputs.values) {
          await output.dispose();
        }
      }
    }

    final processedPng = Uint8List.fromList(img.encodePng(processed));

    return compute(
      _finishAnalysis,
      _OfflinePostprocessInput(
        processedPng,
        predictions: predictions,
        protos: protos,
        predictionsEnhanced: predictionsEnhanced,
        protosEnhanced: protosEnhanced,
        width: processed.width,
        height: processed.height,
        paddedSide: squareSide,
        originalWidth: originalWidth,
        originalHeight: originalHeight,
        scale: scale,
        referencePixels: referencePixels,
        referenceMm: referenceMm,
        referenceX1: referenceX1,
        referenceY1: referenceY1,
        referenceX2: referenceX2,
        referenceY2: referenceY2,
      ),
    );
  }

  static OfflineAnalyzeResult _finishAnalysis(_OfflinePostprocessInput input) {
    final processed = img.decodePng(input.previewImagePng);
    if (processed == null) throw StateError('Cannot decode selected image.');
    final detections = _mergeDetections(
      _decodePredictions(input.predictions, passId: 0),
      _decodePredictions(input.predictionsEnhanced, passId: 1),
    );
    final instances = detections
        .map(
          (detection) => _decodeMask(
            detection.passId == 0 ? input.protos : input.protosEnhanced,
            detection,
            width: input.width,
            height: input.height,
            paddedSide: input.paddedSide,
          ),
        )
        .whereType<_Instance>()
        .toList();
    final filtered = _filterAndMeasure(
      instances,
      width: input.width,
      height: input.height,
      scale: input.scale,
      referencePixels: input.referencePixels,
      referenceMm: input.referenceMm,
      referenceX1: input.referenceX1,
      referenceY1: input.referenceY1,
      referenceX2: input.referenceX2,
      referenceY2: input.referenceY2,
    );
    final summary = _summaryFor(filtered.measurements);
    final overlay = _renderOverlay(processed, filtered);
    final mask = _renderMask(filtered);
    final labels = _renderLabels(filtered);
    final labelMap = _renderLabelMap(filtered);

    final seedCandidateCount =
        instances.where((instance) => instance.classId == 0).length;
    final refCandidateCount = instances.length - seedCandidateCount;
    return OfflineAnalyzeResult(
      originalPng: input.previewImagePng,
      overlayPng: Uint8List.fromList(img.encodePng(overlay)),
      maskPng: Uint8List.fromList(img.encodePng(mask)),
      labelsPng: Uint8List.fromList(img.encodePng(labels)),
      labelMapPng: Uint8List.fromList(img.encodePng(labelMap)),
      image: {
        'width': input.width,
        'height': input.height,
        'original_width': input.originalWidth,
        'original_height': input.originalHeight,
        'scale': _round(input.scale, 6),
      },
      measurements: filtered.measurements,
      summary: summary,
      calibration: {
        'referencePixels': input.referencePixels,
        'referenceMm': input.referenceMm,
        'referencePixelSpace': 'original',
        'enabled': filtered.mmPerPixel > 0,
        'mm_per_pixel': filtered.mmPerPixel,
        'referenceX1': input.referenceX1 ?? -1,
        'referenceY1': input.referenceY1 ?? -1,
        'referenceX2': input.referenceX2 ?? -1,
        'referenceY2': input.referenceY2 ?? -1,
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
        'multi_pass_enabled': _enableEnhancedPass,
        'multi_pass_count': _enableEnhancedPass ? 2 : 1,
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
        'execution': 'mobile_onnxruntime',
        'execution_provider': Platform.isAndroid ? 'XNNPACK/CPU' : 'CPU',
      },
    );
  }

  static List<_Detection> _decodePredictions(
    Float32List prediction, {
    required int passId,
  }) {
    final candidates = <_Detection>[];
    for (var i = 0; i < 8400; i++) {
      final seedScore = prediction[4 * 8400 + i];
      final refScore = prediction[5 * 8400 + i];
      final classId = seedScore >= refScore ? 0 : 1;
      final score = classId == 0 ? seedScore : refScore;
      if (score < _confidence) continue;
      final cx = prediction[0 * 8400 + i];
      final cy = prediction[1 * 8400 + i];
      final width = prediction[2 * 8400 + i];
      final height = prediction[3 * 8400 + i];
      candidates.add(
        _Detection(
          score: score,
          classId: classId,
          passId: passId,
          x1: cx - width / 2,
          y1: cy - height / 2,
          x2: cx + width / 2,
          y2: cy + height / 2,
          coefficients:
              List.generate(32, (c) => prediction[(6 + c) * 8400 + i]),
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

  static List<_Detection> _mergeDetections(
    List<_Detection> primary,
    List<_Detection> secondary,
  ) {
    final merged = <_Detection>[...primary, ...secondary]
      ..sort((a, b) => b.score.compareTo(a.score));
    final kept = <_Detection>[];
    for (final candidate in merged) {
      if (kept.every((other) => _boxIou(candidate, other) < 0.5)) {
        kept.add(candidate);
        if (kept.length >= _maxDetections) break;
      }
    }
    return kept;
  }

  static _Instance? _decodeMask(
    Float32List protos,
    _Detection detection, {
    required int width,
    required int height,
    required int paddedSide,
  }) {
    final scale = paddedSide / _inputSize;
    final x1 = (detection.x1 * scale).floor().clamp(0, width);
    final y1 = (detection.y1 * scale).floor().clamp(0, height);
    final x2 = (detection.x2 * scale).ceil().clamp(0, width);
    final y2 = (detection.y2 * scale).ceil().clamp(0, height);
    if (x2 <= x1 || y2 <= y1) return null;
    final maskWidth = x2 - x1;
    final maskHeight = y2 - y1;
    final pixels = Uint8List(maskWidth * maskHeight);

    var area = 0;
    for (var y = y1; y < y2; y++) {
      final protoY = (y / paddedSide) * _protoSize - 0.5;
      final py0 = protoY.floor().clamp(0, _protoSize - 1);
      final py1 = (py0 + 1).clamp(0, _protoSize - 1);
      final dy = (protoY - py0).clamp(0.0, 1.0);
      for (var x = x1; x < x2; x++) {
        final protoX = (x / paddedSide) * _protoSize - 0.5;
        final px0 = protoX.floor().clamp(0, _protoSize - 1);
        final px1 = (px0 + 1).clamp(0, _protoSize - 1);
        final dx = (protoX - px0).clamp(0.0, 1.0);
        final topLeftWeight = (1 - dx) * (1 - dy);
        final topRightWeight = dx * (1 - dy);
        final bottomLeftWeight = (1 - dx) * dy;
        final bottomRightWeight = dx * dy;
        var logit = 0.0;
        for (var c = 0; c < 32; c++) {
          final channelOffset = c * _protoSize * _protoSize;
          final row0 = channelOffset + py0 * _protoSize;
          final row1 = channelOffset + py1 * _protoSize;
          final value = protos[row0 + px0] * topLeftWeight +
              protos[row0 + px1] * topRightWeight +
              protos[row1 + px0] * bottomLeftWeight +
              protos[row1 + px1] * bottomRightWeight;
          logit += detection.coefficients[c] * value;
        }
        if (_sigmoid(logit) <= 0.5) continue;
        pixels[(y - y1) * maskWidth + (x - x1)] = 1;
        area++;
      }
    }
    if (area == 0) return null;
    return _Instance(
      mask: pixels,
      confidence: detection.score,
      classId: detection.classId,
      x: x1,
      y: y1,
      width: maskWidth,
      height: maskHeight,
    );
  }

  static _FilteredResult _filterAndMeasure(
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
            _Point(referenceX1 * scale, referenceY1 * scale),
            _Point(referenceX2 * scale, referenceY2 * scale),
          )
        : null;
    instances.sort((a, b) => b.confidence.compareTo(a.confidence));
    for (final instance in instances) {
      if (instance.classId != 0) continue;
      if (processedLine != null &&
          _isReferenceObjectMask(
            instance,
            width,
            height,
            processedLine.$1,
            processedLine.$2,
          )) {
        excludedReferenceObjectCount++;
        continue;
      }
      final available = Uint8List(instance.width * instance.height);
      for (var localY = 0; localY < instance.height; localY++) {
        final globalRow = (instance.y + localY) * width + instance.x;
        final localRow = localY * instance.width;
        for (var localX = 0; localX < instance.width; localX++) {
          final localIndex = localRow + localX;
          final globalIndex = globalRow + localX;
          if (instance.mask[localIndex] != 0 && labels[globalIndex] == 0) {
            available[localIndex] = 1;
          }
        }
      }
      final metrics = _maskMetrics(
        available,
        instance.width,
        instance.height,
        offsetX: instance.x,
        offsetY: instance.y,
      );
      if (metrics == null) continue;
      final area = metrics['area_px'] as int;
      final aspect = metrics['aspect_ratio'] as double;
      final solidity = metrics['solidity'] as double;
      final extent = metrics['extent'] as double;
      if (area < _minArea || area > _maxArea) continue;
      if (aspect > _maxAspectRatio) continue;
      if (solidity < _minSolidity || extent < _minExtent) continue;
      if (!_passesConfidenceAwareShapeFilter(instance.confidence, metrics)) {
        continue;
      }

      final id = measurements.length + 1;
      for (var localY = 0; localY < instance.height; localY++) {
        final globalRow = (instance.y + localY) * width + instance.x;
        final localRow = localY * instance.width;
        for (var localX = 0; localX < instance.width; localX++) {
          if (available[localRow + localX] != 0) {
            labels[globalRow + localX] = id;
          }
        }
      }
      measurements.add({
        'id': id,
        ...metrics,
        'area_mm2':
            mmPerPixel == 0 ? null : _round(area * mmPerPixel * mmPerPixel, 6),
        'length_mm': mmPerPixel == 0
            ? null
            : _round((metrics['length_px'] as double) * mmPerPixel, 6),
        'width_mm': mmPerPixel == 0
            ? null
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

  static Map<String, dynamic>? _maskMetrics(
    Uint8List mask,
    int width,
    int height, {
    required int offsetX,
    required int offsetY,
  }) {
    final points = <_Point>[];
    var sumX = 0.0;
    var sumY = 0.0;
    var minX = width + offsetX;
    var minY = height + offsetY;
    var maxX = -1;
    var maxY = -1;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (mask[y * width + x] == 0) continue;
        final globalX = x + offsetX;
        final globalY = y + offsetY;
        points.add(_Point(globalX.toDouble(), globalY.toDouble()));
        sumX += globalX;
        sumY += globalY;
        minX = math.min(minX, globalX);
        minY = math.min(minY, globalY);
        maxX = math.max(maxX, globalX);
        maxY = math.max(maxY, globalY);
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

  static img.Image _renderOverlay(img.Image rgb, _FilteredResult result) {
    final overlay = img.Image.from(rgb);
    final outlierIds = _outlierIds(result.measurements);
    for (var y = 0; y < result.height; y++) {
      for (var x = 0; x < result.width; x++) {
        final label = result.labels[y * result.width + x];
        if (label <= 0) continue;
        final color = outlierIds.contains(label)
            ? const [220, 38, 38]
            : const [37, 99, 235];
        final isEdge = _isLabelEdge(
            result.labels, result.width, result.height, x, y, label);
        final fillOpacity = isEdge ? 0.56 : 0.34;
        final source = overlay.getPixel(x, y);
        overlay.setPixelRgb(
          x,
          y,
          (source.r * (1 - fillOpacity) + color[0] * fillOpacity).round(),
          (source.g * (1 - fillOpacity) + color[1] * fillOpacity).round(),
          (source.b * (1 - fillOpacity) + color[2] * fillOpacity).round(),
        );
      }
    }
    return overlay;
  }

  static img.Image _renderMask(_FilteredResult result) {
    final mask = img.Image(
      width: result.width,
      height: result.height,
      numChannels: 4,
    );
    final outlierIds = _outlierIds(result.measurements);
    for (var y = 0; y < result.height; y++) {
      for (var x = 0; x < result.width; x++) {
        final label = result.labels[y * result.width + x];
        if (label <= 0) {
          mask.setPixelRgba(x, y, 0, 0, 0, 0);
          continue;
        }
        final isOutlier = outlierIds.contains(label);
        final isEdge = _isLabelEdge(
            result.labels, result.width, result.height, x, y, label);
        if (isEdge) {
          final edgeColor =
              isOutlier ? const [185, 28, 28] : const [30, 64, 175];
          mask.setPixelRgba(
              x, y, edgeColor[0], edgeColor[1], edgeColor[2], 255);
          continue;
        }
        final fillColor =
            isOutlier ? const [239, 68, 68] : const [59, 130, 246];
        final alpha = isOutlier ? 170 : 145;
        mask.setPixelRgba(
            x, y, fillColor[0], fillColor[1], fillColor[2], alpha);
      }
    }
    return mask;
  }

  static img.Image _renderLabelMap(_FilteredResult result) {
    final labelMap = img.Image(
      width: result.width,
      height: result.height,
      numChannels: 3,
    );
    for (var y = 0; y < result.height; y++) {
      for (var x = 0; x < result.width; x++) {
        final label = result.labels[y * result.width + x];
        labelMap.setPixelRgb(
          x,
          y,
          label & 0xFF,
          (label >> 8) & 0xFF,
          (label >> 16) & 0xFF,
        );
      }
    }
    return labelMap;
  }

  static Set<int> _outlierIds(List<Map<String, dynamic>> measurements) {
    return {
      for (final measurement in measurements)
        if (measurement['qc_outlier'] == true)
          ((measurement['id'] as num?)?.toInt() ?? -1),
    }..remove(-1);
  }

  static bool _passesConfidenceAwareShapeFilter(
    double confidence,
    Map<String, dynamic> metrics,
  ) {
    final solidity = (metrics['solidity'] as num).toDouble();
    final extent = (metrics['extent'] as num).toDouble();
    final aspect = (metrics['aspect_ratio'] as num).toDouble();
    if (confidence >= 0.18) return true;
    if (confidence >= 0.12) {
      return solidity >= 0.48 && extent >= 0.22 && aspect <= 12.0;
    }
    if (confidence >= 0.08) {
      return solidity >= 0.56 && extent >= 0.25 && aspect <= 10.0;
    }
    return solidity >= 0.62 && extent >= 0.30 && aspect <= 8.0;
  }

  static bool _isLabelEdge(
    Int32List labels,
    int width,
    int height,
    int x,
    int y,
    int label,
  ) {
    if (x == 0 || y == 0 || x == width - 1 || y == height - 1) return true;
    if (labels[y * width + (x - 1)] != label) return true;
    if (labels[y * width + (x + 1)] != label) return true;
    if (labels[(y - 1) * width + x] != label) return true;
    if (labels[(y + 1) * width + x] != label) return true;
    return false;
  }

  static img.Image _renderLabels(_FilteredResult result) {
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
    final labelsImage = img.Image(
      width: result.width,
      height: result.height,
      numChannels: 3,
    );
    for (var y = 0; y < result.height; y++) {
      for (var x = 0; x < result.width; x++) {
        final label = result.labels[y * result.width + x];
        if (label <= 0) continue;
        final color = palette[(label - 1) % palette.length];
        labelsImage.setPixelRgb(x, y, color[0], color[1], color[2]);
      }
    }
    for (final measurement in result.measurements) {
      final id = (measurement['id'] as num).toInt();
      final centroidX = (measurement['centroid_x'] as num).round();
      final centroidY = (measurement['centroid_y'] as num).round();
      img.drawString(
        labelsImage,
        '$id',
        font: img.arial14,
        x: math.max(0, centroidX - 5),
        y: math.max(0, centroidY - 7),
        color: img.ColorRgb8(255, 255, 255),
      );
    }
    return labelsImage;
  }

  static img.Image _enhanceForDetection(img.Image source) {
    final enhanced = img.Image.from(source);
    final pixelCount = math.max(1, enhanced.width * enhanced.height);
    var sumR = 0.0;
    var sumG = 0.0;
    var sumB = 0.0;
    for (var y = 0; y < enhanced.height; y++) {
      for (var x = 0; x < enhanced.width; x++) {
        final p = enhanced.getPixel(x, y);
        sumR += p.r;
        sumG += p.g;
        sumB += p.b;
      }
    }
    final meanR = sumR / pixelCount;
    final meanG = sumG / pixelCount;
    final meanB = sumB / pixelCount;
    final meanGray = (meanR + meanG + meanB) / 3.0;
    final gainR = (meanGray / math.max(meanR, 1.0)).clamp(0.8, 1.3);
    final gainG = (meanGray / math.max(meanG, 1.0)).clamp(0.8, 1.3);
    final gainB = (meanGray / math.max(meanB, 1.0)).clamp(0.8, 1.3);
    for (var y = 0; y < enhanced.height; y++) {
      for (var x = 0; x < enhanced.width; x++) {
        final p = enhanced.getPixel(x, y);
        final r = ((p.r * gainR - 128) * 1.12 + 128).round().clamp(0, 255);
        final g = ((p.g * gainG - 128) * 1.12 + 128).round().clamp(0, 255);
        final b = ((p.b * gainB - 128) * 1.12 + 128).round().clamp(0, 255);
        enhanced.setPixelRgb(x, y, r, g, b);
      }
    }
    return img.gaussianBlur(enhanced, radius: 1);
  }

  Future<OrtSession> _loadSession() async {
    final existing = _session;
    if (existing != null) return existing;
    final options = Platform.isAndroid
        ? OrtSessionOptions(
            providers: const [OrtProvider.XNNPACK, OrtProvider.CPU],
            intraOpNumThreads:
                math.max(1, math.min(4, Platform.numberOfProcessors - 1)),
            interOpNumThreads: 1,
          )
        : null;
    final loaded = await OnnxRuntime().createSessionFromAsset(
      modelAssetPath,
      options: options,
    );
    _session = loaded;
    return loaded;
  }

  Future<void> close() async {
    final session = _session;
    _session = null;
    if (session != null) await session.close();
  }
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
  final sorted = [...points]..sort((a, b) {
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
    (a.x - origin.x) * (b.y - origin.y) - (a.y - origin.y) * (b.x - origin.x);

double _sigmoid(double value) => 1 / (1 + math.exp(-value.clamp(-88.0, 88.0)));

bool _isReferenceObjectMask(
  _Instance instance,
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
    if (instance.contains(x, y)) covered++;
  }
  final midX = ((start.x + end.x) / 2).round().clamp(0, width - 1).toInt();
  final midY = ((start.y + end.y) / 2).round().clamp(0, height - 1).toInt();
  final midpointInside = instance.contains(midX, midY);
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
      'mean_area_mm2': null,
      'mean_length_mm': null,
      'mean_width_mm': null,
      'std_area_px': 0,
      'std_length_px': 0,
      'std_width_px': 0,
      'std_area_mm2': null,
      'std_length_mm': null,
      'std_width_mm': null,
      'robust_std_area_px': 0,
      'robust_std_length_px': 0,
      'robust_std_width_px': 0,
      'robust_std_area_mm2': null,
      'robust_std_length_mm': null,
      'robust_std_width_mm': null,
      'cv_length_pct': 0,
      'cv_width_pct': 0,
      'qc': {
        'method': 'median_mad_multimetric',
        'suspect_count': 0,
        'inlier_count': 0,
        'suspect_ids': <int>[],
        'review_required': false,
        'suspect_ratio': 0,
        'robust_used_for_reporting': true,
        'threshold': _qcMadZThreshold,
        'min_metrics': _qcMinOutlierMetrics,
        'status': 'ok',
      },
    };
  }
  final outliers = _qcOutlierIndices(measurements);
  final suspectRatio = outliers.length / measurements.length;
  final robustUsedForReporting = suspectRatio <= 0.05;
  for (var index = 0; index < measurements.length; index++) {
    final isOutlier = outliers.contains(index);
    measurements[index]['qc_outlier'] = isOutlier;
    measurements[index]['qc_reason'] =
        isOutlier ? 'size_outlier_mad_multimetric' : '';
  }
  final inliers = [
    for (var index = 0; index < measurements.length; index++)
      if (!outliers.contains(index)) measurements[index],
  ];
  final robustMeasurements = inliers.isEmpty ? measurements : inliers;

  List<double> values(List<Map<String, dynamic>> items, String key) =>
      items.map((item) => ((item[key] as num?)?.toDouble() ?? 0)).toList();
  double mean(List<Map<String, dynamic>> items, String key) =>
      _round(values(items, key).reduce((a, b) => a + b) / items.length, 6);
  double std(List<Map<String, dynamic>> items, String key) {
    if (items.length <= 1) return 0;
    final data = values(items, key);
    final average = data.reduce((a, b) => a + b) / data.length;
    final squaredSum = data.fold<double>(
        0, (total, value) => total + math.pow(value - average, 2));
    return _round(math.sqrt(squaredSum / (data.length - 1)), 6);
  }

  double cv(List<Map<String, dynamic>> items, String key) {
    final average = mean(items, key);
    return average > 0 ? _round(std(items, key) / average * 100, 3) : 0;
  }

  final calibrated = measurements.first['length_mm'] != null;
  double? metricMm(double Function(List<Map<String, dynamic>>, String) stat,
          List<Map<String, dynamic>> items, String key) =>
      calibrated ? stat(items, key) : null;

  return {
    'count': measurements.length,
    'total_area_px': measurements.fold<int>(
      0,
      (total, item) => total + ((item['area_px'] as num?)?.toInt() ?? 0),
    ),
    'mean_area_px': mean(measurements, 'area_px'),
    'mean_length_px': mean(measurements, 'length_px'),
    'mean_width_px': mean(measurements, 'width_px'),
    'mean_area_mm2': metricMm(mean, measurements, 'area_mm2'),
    'mean_length_mm': metricMm(mean, measurements, 'length_mm'),
    'mean_width_mm': metricMm(mean, measurements, 'width_mm'),
    'std_area_px': std(measurements, 'area_px'),
    'std_length_px': std(measurements, 'length_px'),
    'std_width_px': std(measurements, 'width_px'),
    'std_area_mm2': metricMm(std, measurements, 'area_mm2'),
    'std_length_mm': metricMm(std, measurements, 'length_mm'),
    'std_width_mm': metricMm(std, measurements, 'width_mm'),
    'robust_mean_area_px': mean(robustMeasurements, 'area_px'),
    'robust_mean_length_px': mean(robustMeasurements, 'length_px'),
    'robust_mean_width_px': mean(robustMeasurements, 'width_px'),
    'robust_mean_area_mm2': metricMm(mean, robustMeasurements, 'area_mm2'),
    'robust_mean_length_mm': metricMm(mean, robustMeasurements, 'length_mm'),
    'robust_mean_width_mm': metricMm(mean, robustMeasurements, 'width_mm'),
    'robust_std_area_px': std(robustMeasurements, 'area_px'),
    'robust_std_length_px': std(robustMeasurements, 'length_px'),
    'robust_std_width_px': std(robustMeasurements, 'width_px'),
    'robust_std_area_mm2': metricMm(std, robustMeasurements, 'area_mm2'),
    'robust_std_length_mm': metricMm(std, robustMeasurements, 'length_mm'),
    'robust_std_width_mm': metricMm(std, robustMeasurements, 'width_mm'),
    'cv_length_pct': cv(robustMeasurements, 'length_px'),
    'cv_width_pct': cv(robustMeasurements, 'width_px'),
    'qc': {
      'method': 'median_mad_multimetric',
      'threshold': _qcMadZThreshold,
      'min_metrics': _qcMinOutlierMetrics,
      'suspect_count': outliers.length,
      'inlier_count': robustMeasurements.length,
      'suspect_ids': [
        for (final index in outliers.toList()..sort())
          measurements[index]['id'],
      ],
      'review_required': outliers.isNotEmpty,
      'suspect_ratio': _round(suspectRatio, 6),
      'robust_used_for_reporting': robustUsedForReporting,
      'status': !robustUsedForReporting
          ? 'review_required'
          : (outliers.isNotEmpty ? 'suspects_flagged' : 'ok'),
    },
  };
}

Set<int> _qcOutlierIndices(List<Map<String, dynamic>> measurements) {
  if (measurements.length < 5) return {};
  final outlierCounts = List<int>.filled(measurements.length, 0);
  for (final key in ['area_px', 'length_px', 'width_px']) {
    final data = measurements
        .map((item) => ((item[key] as num?)?.toDouble() ?? 0))
        .toList();
    final middle = _median(data);
    final deviations = data.map((value) => (value - middle).abs()).toList();
    final mad = _median(deviations);
    for (var index = 0; index < data.length; index++) {
      final deviation = deviations[index];
      final isOutlier = mad <= 1e-9
          ? deviation > 1e-9
          : 0.6745 * deviation / mad > _qcMadZThreshold;
      if (isOutlier) outlierCounts[index]++;
    }
  }
  return {
    for (var index = 0; index < outlierCounts.length; index++)
      if (outlierCounts[index] >= _qcMinOutlierMetrics) index,
  };
}

double _median(List<double> values) {
  final ordered = [...values]..sort();
  final middle = ordered.length ~/ 2;
  return ordered.length.isOdd
      ? ordered[middle]
      : (ordered[middle - 1] + ordered[middle]) / 2;
}

class _Detection {
  final double score;
  final int classId;
  final int passId;
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final List<double> coefficients;

  const _Detection({
    required this.score,
    required this.classId,
    required this.passId,
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
  final int x;
  final int y;
  final int width;
  final int height;

  const _Instance({
    required this.mask,
    required this.confidence,
    required this.classId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  bool contains(int globalX, int globalY) {
    final localX = globalX - x;
    final localY = globalY - y;
    if (localX < 0 || localX >= width || localY < 0 || localY >= height) {
      return false;
    }
    return mask[localY * width + localX] != 0;
  }
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

class _OfflinePostprocessInput {
  final Uint8List previewImagePng;
  final Float32List predictions;
  final Float32List protos;
  final Float32List predictionsEnhanced;
  final Float32List protosEnhanced;
  final int width;
  final int height;
  final int paddedSide;
  final int originalWidth;
  final int originalHeight;
  final double scale;
  final double? referencePixels;
  final double? referenceMm;
  final double? referenceX1;
  final double? referenceY1;
  final double? referenceX2;
  final double? referenceY2;

  const _OfflinePostprocessInput(
    this.previewImagePng, {
    required this.predictions,
    required this.protos,
    required this.predictionsEnhanced,
    required this.protosEnhanced,
    required this.width,
    required this.height,
    required this.paddedSide,
    required this.originalWidth,
    required this.originalHeight,
    required this.scale,
    required this.referencePixels,
    required this.referenceMm,
    required this.referenceX1,
    required this.referenceY1,
    required this.referenceX2,
    required this.referenceY2,
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
  final Uint8List originalPng;
  final Uint8List overlayPng;
  final Uint8List maskPng;
  final Uint8List labelsPng;
  final Uint8List labelMapPng;
  final Map<String, dynamic> image;
  final List<Map<String, dynamic>> measurements;
  final Map<String, dynamic> summary;
  final Map<String, dynamic> calibration;
  final Map<String, dynamic> segmentation;

  const OfflineAnalyzeResult({
    required this.originalPng,
    required this.overlayPng,
    required this.maskPng,
    required this.labelsPng,
    required this.labelMapPng,
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
          'source': 'mobile_onnxruntime',
          'preprocess': {'enabled': false},
        },
        'measurements': measurements,
        'csv': _measurementsCsv(measurements),
        'original_png_base64': base64Encode(originalPng),
        'overlay_png_base64': base64Encode(overlayPng),
        'sam_mask_png_base64': base64Encode(maskPng),
        'labels_png_base64': base64Encode(labelsPng),
        'mask_png_base64': base64Encode(maskPng),
        'label_map_png_base64': base64Encode(labelMapPng),
      };
}

String _measurementsCsv(List<Map<String, dynamic>> measurements) {
  const columns = [
    'id',
    'area_px',
    'length_px',
    'width_px',
    'area_mm2',
    'length_mm',
    'width_mm',
    'centroid_x',
    'centroid_y',
    'bbox_x',
    'bbox_y',
    'bbox_w',
    'bbox_h',
    'angle_deg',
    'solidity',
    'extent',
    'aspect_ratio',
    'confidence',
    'class_id',
    'class_name',
    'qc_outlier',
    'qc_reason',
  ];
  final rows = <String>[columns.join(',')];
  for (final measurement in measurements) {
    rows.add(columns.map((column) => '${measurement[column] ?? ''}').join(','));
  }
  return '${rows.join('\n')}\n';
}
