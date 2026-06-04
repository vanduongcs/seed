import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

typedef OfflineProgressCallback = void Function(double value, String phase);

const _qcMadZThreshold = 4.0;
const _qcRelaxedMadZThreshold = 8.0;
const _qcMinOutlierMetrics = 2;

class OfflineGrainAnalyzer {
  static const modelAssetPath = 'assets/models/best_mobile_yolo26_640.onnx';

  // Keep these aligned with backend/config/grain.settings.json.
  static const _inputSize = 640;
  static const _protoSize = 160;
  static const _classCount = 2;
  static const _maskCoefficientCount = 32;
  static const _predictionFeatureCount =
      4 + _classCount + _maskCoefficientCount;
  static const _maxSide = 1280;
  static const _confidence = 0.05;
  static const _iou = 0.70;
  static const _maxDetections = 5000;
  static const _enableTiledInference = false;
  static const _enableFullImagePass = true;
  static const _tileSize = 640;
  static const _tileOverlap = 0.25;
  static const _mergeIou = 0.35;
  static const _mergeOverlap = 0.70;
  static const _enableRoiPrepass = true;
  static const _roiDetectionSide = 768;
  static const _roiPadding = 40;
  static const _roiMergeMaxSide = 640;
  static const _roiMinArea = 48;
  static const _roiMinBoxSide = 6;
  static const _roiMaxPasses = 24;
  static const _minArea = 20;
  static const _maxArea = 200000;
  static const _maxAspectRatio = 14.0;
  static const _minSolidity = 0.5;
  static const _minExtent = 0.2;
  static const _skinRejectRatio = 0.58;
  static const _strongSkinRejectRatio = 0.72;
  static const _adaptiveMinCandidates = 8;
  static const _adaptiveMadZ = 5.0;
  static const _dynamicAreaMultiplier = 8.0;
  static const _mergedSplitAreaRatio = 1.45;
  static const _mergedSplitLengthRatio = 1.22;
  static const _mergedSplitWidthRatio = 1.32;
  static const _mergedSplitMadZ = 3.0;
  static const _mergedSplitMaxParts = 4;

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
          shape: const [1, 300, _predictionFeatureCount],
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

    await reportProgress(54, 'Chuẩn bị nhận dạng trên thiết bị');
    final session = await _loadSession();
    await reportProgress(60, 'Chuẩn bị ảnh để nhận dạng');
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

    final rawInstances = <_Instance>[];
    var rawDetectionCount = 0;
    var passCount = 0;
    var roiPassCount = 0;
    var tilePassCount = 0;
    var roiRegions = const <_RoiBox>[];
    await reportProgress(68, 'Đang nhận dạng hạt trên thiết bị');
    if (_enableRoiPrepass) {
      roiRegions = _detectRoiRegions(processed);
      for (var i = 0; i < roiRegions.length; i++) {
        final roi = roiRegions[i];
        await reportProgress(
          68 + (14 * (i / math.max(roiRegions.length, 1))),
          'Nhận dạng ROI ${i + 1}/${roiRegions.length}',
        );
        final crop = img.copyCrop(
          processed,
          x: roi.x,
          y: roi.y,
          width: roi.width,
          height: roi.height,
        );
        final pass =
            await _runInferencePass(session, crop, roi.x, roi.y, 'roi');
        final decoded = _decodePassInstances(pass);
        rawDetectionCount += decoded.rawDetectionCount;
        rawInstances.addAll(decoded.instances);
        passCount++;
        roiPassCount++;
      }
    }
    if (rawInstances.isEmpty && _enableFullImagePass) {
      final pass = await _runInferencePass(session, processed, 0, 0, 'full');
      final decoded = _decodePassInstances(pass);
      rawDetectionCount += decoded.rawDetectionCount;
      rawInstances.addAll(decoded.instances);
      passCount++;
    }
    if (_enableTiledInference &&
        (!_enableFullImagePass ||
            processed.width > _tileSize ||
            processed.height > _tileSize)) {
      for (final y in _tileStarts(processed.height, _tileSize)) {
        for (final x in _tileStarts(processed.width, _tileSize)) {
          final tileWidth = math.min(_tileSize, processed.width - x);
          final tileHeight = math.min(_tileSize, processed.height - y);
          final tile = img.copyCrop(
            processed,
            x: x,
            y: y,
            width: tileWidth,
            height: tileHeight,
          );
          final pass = await _runInferencePass(session, tile, x, y, 'tile');
          final decoded = _decodePassInstances(pass);
          rawDetectionCount += decoded.rawDetectionCount;
          rawInstances.addAll(decoded.instances);
          passCount++;
          tilePassCount++;
        }
      }
    }

    await reportProgress(82, 'Tạo hình dạng, đo hạt và dựng ảnh');
    final processedPng = Uint8List.fromList(img.encodePng(processed));

    return compute(
      _finishAnalysis,
      _OfflinePostprocessInput(
        processedPng,
        rawInstances: _mergeInstances(rawInstances),
        rawDetectionCount: rawDetectionCount,
        passCount: passCount,
        roiRegionCount: roiRegions.length,
        roiPassCount: roiPassCount,
        tilePassCount: tilePassCount,
        width: processed.width,
        height: processed.height,
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

  static _DecodedInferencePass _decodePassInstances(
      _OfflineInferencePass pass) {
    final detections = _decodePredictions(pass.predictions);
    final instances = detections
        .map(
          (detection) => _decodeMask(
            pass.protos,
            detection,
            width: pass.width,
            height: pass.height,
            paddedSide: pass.paddedSide,
            offsetX: pass.offsetX,
            offsetY: pass.offsetY,
          ),
        )
        .whereType<_Instance>()
        .toList();
    return _DecodedInferencePass(
      rawDetectionCount: detections.length,
      instances: instances,
    );
  }

  Future<_OfflineInferencePass> _runInferencePass(
    OrtSession session,
    img.Image source,
    int offsetX,
    int offsetY,
    String sourceName,
  ) async {
    final squareSide = math.max(source.width, source.height);
    final square =
        img.Image(width: squareSide, height: squareSide, numChannels: 3);
    img.fill(square, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(square, source, dstX: 0, dstY: 0);
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
    final outputs = await session.run({session.inputNames.first: inputTensor});
    try {
      return _OfflineInferencePass(
        predictions: Float32List.fromList(
          (await outputs[session.outputNames.first]!.asFlattenedList())
              .map((value) => (value as num).toDouble())
              .toList(),
        ),
        protos: Float32List.fromList(
          (await outputs[session.outputNames.last]!.asFlattenedList())
              .map((value) => (value as num).toDouble())
              .toList(),
        ),
        width: source.width,
        height: source.height,
        paddedSide: squareSide,
        offsetX: offsetX,
        offsetY: offsetY,
        source: sourceName,
      );
    } finally {
      await inputTensor.dispose();
      for (final output in outputs.values) {
        await output.dispose();
      }
    }
  }

  static List<_RoiBox> _detectRoiRegions(img.Image source) {
    final longestSide = math.max(source.width, source.height);
    final detectScale =
        longestSide > _roiDetectionSide ? _roiDetectionSide / longestSide : 1.0;
    final detect = detectScale < 1.0
        ? img.copyResize(
            source,
            width: math.max(1, (source.width * detectScale).round()),
            height: math.max(1, (source.height * detectScale).round()),
            interpolation: img.Interpolation.average,
          )
        : img.Image.from(source);
    final width = detect.width;
    final height = detect.height;
    if (width < 8 || height < 8) return const [];

    final bg = _borderColor(detect);
    final bgLuma = _luma(bg.r, bg.g, bg.b);
    final foreground = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        final pixel = detect.getPixel(x, y);
        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();
        final dr = r - bg.r;
        final dg = g - bg.g;
        final db = b - bg.b;
        final dist2 = dr * dr + dg * dg + db * db;
        final lumaDelta = (_luma(r, g, b) - bgLuma).abs();
        final saturation = _saturation(r, g, b);
        if ((dist2 > 34 * 34 && lumaDelta > 14) ||
            (dist2 > 24 * 24 && saturation > 0.18)) {
          foreground[row + x] = 1;
        }
      }
    }

    final visited = Uint8List(width * height);
    final components = <_RoiBox>[];
    final queue = Int32List(width * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final start = y * width + x;
        if (foreground[start] == 0 || visited[start] != 0) continue;
        var head = 0;
        var tail = 0;
        queue[tail++] = start;
        visited[start] = 1;
        var minX = x;
        var maxX = x;
        var minY = y;
        var maxY = y;
        var area = 0;
        while (head < tail) {
          final index = queue[head++];
          final cy = index ~/ width;
          final cx = index - cy * width;
          area++;
          minX = math.min(minX, cx);
          maxX = math.max(maxX, cx);
          minY = math.min(minY, cy);
          maxY = math.max(maxY, cy);
          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              if (dx == 0 && dy == 0) continue;
              final nx = cx + dx;
              final ny = cy + dy;
              if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
              final ni = ny * width + nx;
              if (foreground[ni] == 0 || visited[ni] != 0) continue;
              visited[ni] = 1;
              queue[tail++] = ni;
            }
          }
        }
        if (area < _roiMinArea ||
            maxX - minX + 1 < _roiMinBoxSide ||
            maxY - minY + 1 < _roiMinBoxSide) {
          continue;
        }
        final x1 = (minX / detectScale).floor() - _roiPadding;
        final y1 = (minY / detectScale).floor() - _roiPadding;
        final x2 = ((maxX + 1) / detectScale).ceil() + _roiPadding;
        final y2 = ((maxY + 1) / detectScale).ceil() + _roiPadding;
        components.add(
          _RoiBox.fromBounds(
            x1.clamp(0, source.width - 1).toInt(),
            y1.clamp(0, source.height - 1).toInt(),
            x2.clamp(1, source.width).toInt(),
            y2.clamp(1, source.height).toInt(),
          ),
        );
      }
    }
    if (components.isEmpty) return const [];
    return _mergeRoiBoxes(components)
        .where((box) => box.width > 8 && box.height > 8)
        .take(_roiMaxPasses)
        .toList();
  }

  static List<_RoiBox> _mergeRoiBoxes(List<_RoiBox> boxes) {
    final pending = [...boxes]
      ..sort((a, b) => a.y == b.y ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
    var changed = true;
    while (changed) {
      changed = false;
      for (var i = 0; i < pending.length; i++) {
        for (var j = i + 1; j < pending.length; j++) {
          final merged = pending[i].union(pending[j]);
          if (math.max(merged.width, merged.height) > _roiMergeMaxSide) {
            continue;
          }
          pending[i] = merged;
          pending.removeAt(j);
          changed = true;
          break;
        }
        if (changed) break;
      }
    }
    pending.sort((a, b) => b.area.compareTo(a.area));
    return pending;
  }

  static _RgbColor _borderColor(img.Image image) {
    var r = 0.0;
    var g = 0.0;
    var b = 0.0;
    var count = 0;
    void sample(int x, int y) {
      final pixel = image.getPixel(x, y);
      r += pixel.r;
      g += pixel.g;
      b += pixel.b;
      count++;
    }

    for (var x = 0; x < image.width; x++) {
      sample(x, 0);
      sample(x, image.height - 1);
    }
    for (var y = 1; y < image.height - 1; y++) {
      sample(0, y);
      sample(image.width - 1, y);
    }
    final divisor = math.max(count, 1);
    return _RgbColor(r / divisor, g / divisor, b / divisor);
  }

  static double _luma(double r, double g, double b) =>
      0.299 * r + 0.587 * g + 0.114 * b;

  static double _saturation(double r, double g, double b) {
    final maxChannel = math.max(r, math.max(g, b));
    final minChannel = math.min(r, math.min(g, b));
    if (maxChannel <= 1e-9) return 0;
    return (maxChannel - minChannel) / maxChannel;
  }

  static OfflineAnalyzeResult _finishAnalysis(_OfflinePostprocessInput input) {
    final processed = img.decodePng(input.previewImagePng);
    if (processed == null) throw StateError('Cannot decode selected image.');
    final rawDetectionCount = input.rawDetectionCount;
    final instances = input.rawInstances;
    final filtered = _filterAndMeasure(
      instances,
      processed,
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
      originalPng: Uint8List(0),
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
        'multi_pass_enabled': _enableRoiPrepass || _enableTiledInference,
        'multi_pass_count': input.passCount,
        'roi_prepass_enabled': _enableRoiPrepass,
        'roi_region_count': input.roiRegionCount,
        'roi_pass_count': input.roiPassCount,
        'roi_detection_side': _roiDetectionSide,
        'roi_padding': _roiPadding,
        'roi_merge_max_side': _roiMergeMaxSide,
        'tiled_inference': _enableTiledInference,
        'full_image_pass': _enableFullImagePass,
        'tile_size': _tileSize,
        'tile_overlap': _tileOverlap,
        'tile_pass_count': input.tilePassCount,
        'candidate_count': rawDetectionCount,
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
          'adaptiveThresholds': true,
          'adaptiveMinCandidates': _adaptiveMinCandidates,
          'adaptiveMadZ': _adaptiveMadZ,
          'dynamicAreaMultiplier': _dynamicAreaMultiplier,
          'skinRejectRatio': _skinRejectRatio,
          'strongSkinRejectRatio': _strongSkinRejectRatio,
          'mergedSeedSplit': true,
          'mergedSplitAreaRatio': _mergedSplitAreaRatio,
          'mergedSplitLengthRatio': _mergedSplitLengthRatio,
          'mergedSplitWidthRatio': _mergedSplitWidthRatio,
          'mergedSplitMadZ': _mergedSplitMadZ,
          'mergedSplitMaxParts': _mergedSplitMaxParts,
        },
        'offline': true,
        'execution': 'mobile_onnxruntime',
        'execution_provider': 'CPU',
      },
    );
  }

  static List<_Detection> _decodePredictions(Float32List prediction) {
    final candidateCount = prediction.length ~/ _predictionFeatureCount;
    if (candidateCount <= 0 ||
        prediction.length % _predictionFeatureCount != 0) {
      return const [];
    }
    final candidateMajor = candidateCount == 300;
    double valueAt(int feature, int candidate) {
      return candidateMajor
          ? prediction[candidate * _predictionFeatureCount + feature]
          : prediction[feature * candidateCount + candidate];
    }

    final candidates = <_Detection>[];
    for (var i = 0; i < candidateCount; i++) {
      final seedScore = valueAt(4, i);
      final refScore = valueAt(5, i);
      final classId = seedScore >= refScore ? 0 : 1;
      final score = classId == 0 ? seedScore : refScore;
      if (score < _confidence) continue;
      final cx = valueAt(0, i);
      final cy = valueAt(1, i);
      final width = valueAt(2, i);
      final height = valueAt(3, i);
      candidates.add(
        _Detection(
          score: score,
          classId: classId,
          x1: candidateMajor ? cx : cx - width / 2,
          y1: candidateMajor ? cy : cy - height / 2,
          x2: candidateMajor ? width : cx + width / 2,
          y2: candidateMajor ? height : cy + height / 2,
          coefficients:
              List.generate(_maskCoefficientCount, (c) => valueAt(6 + c, i)),
        ),
      );
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));
    final kept = <_Detection>[];
    for (final candidate in candidates) {
      if (kept.every(
        (other) =>
            other.classId != candidate.classId ||
            _boxIou(candidate, other) < _iou,
      )) {
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
    int offsetX = 0,
    int offsetY = 0,
  }) {
    final protoPlaneSize = protos.length ~/ _maskCoefficientCount;
    final protoSize = math.sqrt(protoPlaneSize).round();
    if (protoSize <= 0 ||
        protoSize * protoSize * _maskCoefficientCount != protos.length) {
      return null;
    }
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
      final protoY = (y / paddedSide) * protoSize - 0.5;
      final py0 = protoY.floor().clamp(0, protoSize - 1);
      final py1 = (py0 + 1).clamp(0, protoSize - 1);
      final dy = (protoY - py0).clamp(0.0, 1.0);
      for (var x = x1; x < x2; x++) {
        final protoX = (x / paddedSide) * protoSize - 0.5;
        final px0 = protoX.floor().clamp(0, protoSize - 1);
        final px1 = (px0 + 1).clamp(0, protoSize - 1);
        final dx = (protoX - px0).clamp(0.0, 1.0);
        final topLeftWeight = (1 - dx) * (1 - dy);
        final topRightWeight = dx * (1 - dy);
        final bottomLeftWeight = (1 - dx) * dy;
        final bottomRightWeight = dx * dy;
        var logit = 0.0;
        for (var c = 0; c < _maskCoefficientCount; c++) {
          final channelOffset = c * protoSize * protoSize;
          final row0 = channelOffset + py0 * protoSize;
          final row1 = channelOffset + py1 * protoSize;
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
      x: x1 + offsetX,
      y: y1 + offsetY,
      width: maskWidth,
      height: maskHeight,
    );
  }

  static List<int> _tileStarts(int length, int tileSize) {
    if (length <= tileSize) return [0];
    final step = math.max(1, (tileSize * (1.0 - _tileOverlap)).round()).toInt();
    final starts = <int>[];
    for (var value = 0; value <= length - tileSize; value += step) {
      starts.add(value);
    }
    final last = length - tileSize;
    if (starts.isEmpty || starts.last != last) starts.add(last);
    return starts;
  }

  static List<_Instance> _mergeInstances(List<_Instance> instances) {
    final sorted = [...instances]
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final selected = <_Instance>[];
    final selectedAreas = <int>[];
    for (final candidate in sorted) {
      final candidateArea = _instanceArea(candidate);
      if (candidateArea <= 0) continue;
      var duplicate = false;
      for (var i = 0; i < selected.length; i++) {
        if (!_instanceBboxIntersects(candidate, selected[i])) continue;
        final inter = _instanceIntersectionArea(candidate, selected[i]);
        if (inter == 0) continue;
        final union = candidateArea + selectedAreas[i] - inter;
        final iou = inter / math.max(union, 1);
        final overlap =
            inter / math.max(math.min(candidateArea, selectedAreas[i]), 1);
        if (iou >= _mergeIou || overlap >= _mergeOverlap) {
          duplicate = true;
          break;
        }
      }
      if (!duplicate) {
        selected.add(candidate);
        selectedAreas.add(candidateArea);
      }
    }
    return selected;
  }

  static int _instanceArea(_Instance instance) {
    var area = 0;
    for (final value in instance.mask) {
      if (value != 0) area++;
    }
    return area;
  }

  static bool _instanceBboxIntersects(_Instance a, _Instance b) {
    return a.x < b.x + b.width &&
        a.x + a.width > b.x &&
        a.y < b.y + b.height &&
        a.y + a.height > b.y;
  }

  static int _instanceIntersectionArea(_Instance a, _Instance b) {
    final x1 = math.max(a.x, b.x);
    final y1 = math.max(a.y, b.y);
    final x2 = math.min(a.x + a.width, b.x + b.width);
    final y2 = math.min(a.y + a.height, b.y + b.height);
    if (x2 <= x1 || y2 <= y1) return 0;
    var area = 0;
    for (var y = y1; y < y2; y++) {
      final aRow = (y - a.y) * a.width;
      final bRow = (y - b.y) * b.width;
      for (var x = x1; x < x2; x++) {
        if (a.mask[aRow + (x - a.x)] != 0 && b.mask[bRow + (x - b.x)] != 0) {
          area++;
        }
      }
    }
    return area;
  }

  static _FilteredResult _filterAndMeasure(
    List<_Instance> instances,
    img.Image rgb, {
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
    final imageArea = width * height;
    final candidates = <_MeasurementCandidate>[];
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
      final metrics = _maskMetrics(
        instance.mask,
        instance.width,
        instance.height,
        offsetX: instance.x,
        offsetY: instance.y,
      );
      if (metrics == null) continue;
      final color = _maskColorMetrics(
        rgb,
        instance.mask,
        instance.width,
        instance.height,
        offsetX: instance.x,
        offsetY: instance.y,
      );
      if (!_passesCandidateFilter(
        instance.confidence,
        metrics,
        color,
        imageArea,
        null,
      )) {
        continue;
      }
      candidates.add(_MeasurementCandidate(instance, metrics, color));
    }

    var sizeReference = _sizeReferenceFor(candidates);
    final splitCandidates =
        _splitMergedCandidates(candidates, rgb, sizeReference);
    sizeReference = _sizeReferenceFor(splitCandidates) ?? sizeReference;
    final selected = splitCandidates
        .where(
          (candidate) => _passesCandidateFilter(
            candidate.instance.confidence,
            candidate.metrics,
            candidate.color,
            imageArea,
            sizeReference,
          ),
        )
        .toList()
      ..sort((a, b) => b.priority.compareTo(a.priority));

    for (final candidate in selected) {
      final instance = candidate.instance;
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
      final color = _maskColorMetrics(
        rgb,
        available,
        instance.width,
        instance.height,
        offsetX: instance.x,
        offsetY: instance.y,
      );
      if (!_passesCandidateFilter(
        instance.confidence,
        metrics,
        color,
        imageArea,
        sizeReference,
      )) {
        continue;
      }
      final area = metrics['area_px'] as int;
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
    if (confidence >= 0.18) {
      return solidity >= 0.5 && extent >= 0.2 && aspect <= 10.5;
    }
    if (confidence >= 0.12) {
      return solidity >= 0.48 && extent >= 0.22 && aspect <= 12.0;
    }
    if (confidence >= 0.08) {
      return solidity >= 0.56 && extent >= 0.25 && aspect <= 10.0;
    }
    return solidity >= 0.62 && extent >= 0.30 && aspect <= 8.0;
  }

  static bool _passesCandidateFilter(
    double confidence,
    Map<String, dynamic> metrics,
    _MaskColorMetrics color,
    int imageArea,
    _SizeReference? sizeReference,
  ) {
    final area = metrics['area_px'] as int;
    final aspect = (metrics['aspect_ratio'] as num).toDouble();
    final solidity = (metrics['solidity'] as num).toDouble();
    final extent = (metrics['extent'] as num).toDouble();
    if (area < _minArea || area > _maxArea) return false;
    if (aspect > _maxAspectRatio) return false;
    if (solidity < _minSolidity || extent < _minExtent) return false;
    if (!_passesConfidenceAwareShapeFilter(confidence, metrics)) return false;
    if (_looksLikeLargeSkinObject(area, imageArea, color, sizeReference)) {
      return false;
    }
    if (_isDynamicNonSeedSize(metrics, color, imageArea, sizeReference)) {
      return false;
    }
    if (_isLowConfidenceOversize(confidence, metrics, sizeReference)) {
      return false;
    }
    return true;
  }

  static bool _looksLikeLargeSkinObject(
    int area,
    int imageArea,
    _MaskColorMetrics color,
    _SizeReference? reference,
  ) {
    final referenceArea = reference?.area ?? 0;
    final largeSkinFloor = [
      1800.0,
      imageArea * 0.018,
      referenceArea * 4.0,
    ].reduce(math.max);
    final strongSkinFloor = [
      1000.0,
      imageArea * 0.012,
      referenceArea * 3.0,
    ].reduce(math.max);
    if (color.skinRatio >= _skinRejectRatio && area >= largeSkinFloor) {
      return true;
    }
    if (color.skinRatio >= _strongSkinRejectRatio && area >= strongSkinFloor) {
      return true;
    }
    return false;
  }

  static bool _isDynamicNonSeedSize(
    Map<String, dynamic> metrics,
    _MaskColorMetrics color,
    int imageArea,
    _SizeReference? reference,
  ) {
    if (reference == null) return false;
    final area = (metrics['area_px'] as num).toDouble();
    final tooLarge = area > reference.areaUpper;
    final coversImage = area / math.max(imageArea, 1) > 0.08;
    return tooLarge && coversImage;
  }

  static bool _isLowConfidenceOversize(
    double confidence,
    Map<String, dynamic> metrics,
    _SizeReference? reference,
  ) {
    if (reference == null || confidence >= 0.08) return false;
    return (metrics['area_px'] as num).toDouble() > reference.area * 1.65;
  }

  static _SizeReference? _sizeReferenceFor(
    List<_MeasurementCandidate> candidates,
  ) {
    if (candidates.length < _adaptiveMinCandidates) return null;
    var referenceCandidates = candidates
        .where((candidate) => candidate.color.skinRatio < 0.35)
        .toList();
    if (referenceCandidates.length < _adaptiveMinCandidates) {
      referenceCandidates = candidates;
    }
    final areas = [
      for (final candidate in referenceCandidates)
        (candidate.metrics['area_px'] as num).toDouble(),
    ];
    final lengths = [
      for (final candidate in referenceCandidates)
        (candidate.metrics['length_px'] as num).toDouble(),
    ];
    final widths = [
      for (final candidate in referenceCandidates)
        (candidate.metrics['width_px'] as num).toDouble(),
    ];
    final aspects = [
      for (final candidate in referenceCandidates)
        (candidate.metrics['aspect_ratio'] as num).toDouble(),
    ];
    final areaMedian = _median(areas);
    final lengthMedian = _median(lengths);
    final widthMedian = _median(widths);
    final aspectMedian = _median(aspects);
    return _SizeReference(
      area: areaMedian,
      length: lengthMedian,
      width: widthMedian,
      splitEnabled: aspectMedian >= 1.75 &&
          _madRatio(areas, areaMedian) <= 0.35 &&
          _madRatio(lengths, lengthMedian) <= 0.25 &&
          _madRatio(widths, widthMedian) <= 0.25,
      areaSplitUpper: _robustUpper(
        areas,
        center: areaMedian,
        z: _mergedSplitMadZ,
        minMultiplier: _mergedSplitAreaRatio,
      ),
      lengthSplitUpper: _robustUpper(
        lengths,
        center: lengthMedian,
        z: _mergedSplitMadZ,
        minMultiplier: _mergedSplitLengthRatio,
      ),
      widthSplitUpper: _robustUpper(
        widths,
        center: widthMedian,
        z: _mergedSplitMadZ,
        minMultiplier: _mergedSplitWidthRatio,
      ),
      areaUpper: _robustUpper(
        areas,
        center: areaMedian,
        z: _adaptiveMadZ,
        minMultiplier: _dynamicAreaMultiplier,
      ),
    );
  }

  static double _robustUpper(
    List<double> values, {
    required double center,
    required double z,
    required double minMultiplier,
  }) {
    if (values.isEmpty) return center * minMultiplier;
    final deviations = values.map((value) => (value - center).abs()).toList();
    final mad = _median(deviations);
    final robustSigma = math.max(1.0, 1.4826 * mad);
    return math.max(center * minMultiplier, center + z * robustSigma);
  }

  static double _madRatio(List<double> values, double center) {
    if (values.isEmpty || center <= 1e-9) return 1;
    final deviations = values.map((value) => (value - center).abs()).toList();
    return _median(deviations) / center;
  }

  static List<_MeasurementCandidate> _splitMergedCandidates(
    List<_MeasurementCandidate> candidates,
    img.Image rgb,
    _SizeReference? reference,
  ) {
    if (reference == null) return candidates;
    final result = <_MeasurementCandidate>[];
    for (final candidate in candidates) {
      final parts = _splitCandidateIfMerged(candidate, reference);
      if (parts.length == 1) {
        result.add(candidate);
        continue;
      }
      for (final part in parts) {
        final metrics = _maskMetrics(
          part.mask,
          part.width,
          part.height,
          offsetX: part.x,
          offsetY: part.y,
        );
        if (metrics == null) continue;
        final color = _maskColorMetrics(
          rgb,
          part.mask,
          part.width,
          part.height,
          offsetX: part.x,
          offsetY: part.y,
        );
        result.add(_MeasurementCandidate(part, metrics, color));
      }
    }
    return result;
  }

  static List<_Instance> _splitCandidateIfMerged(
    _MeasurementCandidate candidate,
    _SizeReference reference,
  ) {
    var parts = [candidate.instance];
    for (var pass = 0; pass < _mergedSplitMaxParts - 1; pass++) {
      var changed = false;
      final next = <_Instance>[];
      for (final part in parts) {
        final metrics = _maskMetrics(
          part.mask,
          part.width,
          part.height,
          offsetX: part.x,
          offsetY: part.y,
        );
        if (metrics == null || !_shouldTryMergedSplit(metrics, reference)) {
          next.add(part);
          continue;
        }
        final splitMasks =
            _projectionSplitMask(part.mask, part.width, part.height, reference);
        if (splitMasks.length < 2 ||
            next.length + splitMasks.length + (parts.length - next.length - 1) >
                _mergedSplitMaxParts) {
          next.add(part);
          continue;
        }
        for (final splitMask in splitMasks) {
          next.add(
            _Instance(
              mask: splitMask,
              confidence: part.confidence * 0.98,
              classId: part.classId,
              x: part.x,
              y: part.y,
              width: part.width,
              height: part.height,
            ),
          );
        }
        changed = true;
      }
      parts = next;
      if (!changed) break;
    }
    return parts.length > 1 ? parts : [candidate.instance];
  }

  static bool _shouldTryMergedSplit(
    Map<String, dynamic> metrics,
    _SizeReference reference,
  ) {
    if (!reference.splitEnabled) return false;
    final area = (metrics['area_px'] as num).toDouble();
    final length = (metrics['length_px'] as num).toDouble();
    final width = (metrics['width_px'] as num).toDouble();
    final areaLarge = area >= reference.areaSplitUpper;
    final lengthLarge = length >= reference.lengthSplitUpper;
    final widthLarge = width >= reference.widthSplitUpper;
    return areaLarge && (lengthLarge || widthLarge);
  }

  static List<Uint8List> _projectionSplitMask(
    Uint8List mask,
    int width,
    int height,
    _SizeReference reference,
  ) {
    var count = 0;
    var sumX = 0.0;
    var sumY = 0.0;
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        if (mask[row + x] == 0) continue;
        count++;
        sumX += x;
        sumY += y;
      }
    }
    if (count < 2) return [mask];
    final meanX = sumX / count;
    final meanY = sumY / count;
    var covXx = 0.0;
    var covYy = 0.0;
    var covXy = 0.0;
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        if (mask[row + x] == 0) continue;
        final dx = x - meanX;
        final dy = y - meanY;
        covXx += dx * dx;
        covYy += dy * dy;
        covXy += dx * dy;
      }
    }
    final angle = 0.5 * math.atan2(2 * covXy, covXx - covYy);
    final majorX = math.cos(angle);
    final majorY = math.sin(angle);
    final candidates = [
      _splitMaskOnAxis(mask, width, height, majorX, majorY, reference),
      _splitMaskOnAxis(mask, width, height, -majorY, majorX, reference),
    ].where((candidate) => candidate.masks.length == 2).toList()
      ..sort((a, b) => a.score.compareTo(b.score));
    return candidates.isEmpty ? [mask] : candidates.first.masks;
  }

  static _ProjectionSplitResult _splitMaskOnAxis(
    Uint8List mask,
    int width,
    int height,
    double axisX,
    double axisY,
    _SizeReference reference,
  ) {
    var projMin = double.infinity;
    var projMax = double.negativeInfinity;
    var total = 0;
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        if (mask[row + x] == 0) continue;
        final projection = x * axisX + y * axisY;
        projMin = math.min(projMin, projection);
        projMax = math.max(projMax, projection);
        total++;
      }
    }
    final span = projMax - projMin;
    if (total < 2 || span < 8) return _ProjectionSplitResult([mask], 1);
    final binCount = math.max(12, math.min(96, (span / 4).ceil()));
    final hist = List<int>.filled(binCount, 0);
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        if (mask[row + x] == 0) continue;
        final projection = x * axisX + y * axisY;
        final bin = (((projection - projMin) / span) * binCount)
            .floor()
            .clamp(0, binCount - 1)
            .toInt();
        hist[bin]++;
      }
    }
    final cumulative = List<int>.filled(binCount, 0);
    for (var i = 0; i < binCount; i++) {
      cumulative[i] = hist[i] + (i == 0 ? 0 : cumulative[i - 1]);
    }
    final lo = math.max(2, (binCount * 0.2).floor());
    final hi = math.min(binCount - 3, (binCount * 0.8).floor());
    if (hi <= lo) return _ProjectionSplitResult([mask], 1);
    final minPartArea = math.max(20, (reference.area * 0.28).round());
    var bestScore = double.infinity;
    var bestIndex = -1;
    var bestValleyRatio = 1.0;
    for (var index = lo; index <= hi; index++) {
      final leftArea = cumulative[index];
      final rightArea = cumulative.last - leftArea;
      if (leftArea < minPartArea || rightArea < minPartArea) continue;
      final balance = math.min(leftArea, rightArea) / math.max(total, 1);
      if (balance < 0.25) continue;
      final leftPeak = hist.take(index + 1).fold<int>(0, math.max);
      final rightPeak = hist.skip(index).fold<int>(0, math.max);
      final peakFloor = math.max(1, math.min(leftPeak, rightPeak));
      final valleyRatio = hist[index] / peakFloor;
      final score = valleyRatio + (0.5 - balance).abs() * 0.6;
      if (score < bestScore) {
        bestScore = score;
        bestIndex = index;
        bestValleyRatio = valleyRatio;
      }
    }
    if (bestIndex < 0) return _ProjectionSplitResult([mask], 1);
    if (bestValleyRatio > 0.92 && total < reference.area * 1.6) {
      return _ProjectionSplitResult([mask], bestValleyRatio);
    }
    final threshold = projMin + span * ((bestIndex + 0.5) / binCount);
    final leftMask = Uint8List(mask.length);
    final rightMask = Uint8List(mask.length);
    var leftArea = 0;
    var rightArea = 0;
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        final localIndex = row + x;
        if (mask[localIndex] == 0) continue;
        final projection = x * axisX + y * axisY;
        if (projection <= threshold) {
          leftMask[localIndex] = 1;
          leftArea++;
        } else {
          rightMask[localIndex] = 1;
          rightArea++;
        }
      }
    }
    if (leftArea < minPartArea || rightArea < minPartArea) {
      return _ProjectionSplitResult([mask], 1);
    }
    if (math.min(leftArea, rightArea) / math.max(leftArea + rightArea, 1) <
        0.25) {
      return _ProjectionSplitResult([mask], 1);
    }
    final parts = [leftMask, rightMask];
    if (!_splitPartsArePlausible(parts, width, height, reference)) {
      return _ProjectionSplitResult([mask], 1);
    }
    return _ProjectionSplitResult(parts, bestValleyRatio);
  }

  static bool _splitPartsArePlausible(
    List<Uint8List> parts,
    int width,
    int height,
    _SizeReference reference,
  ) {
    final minAspect = math.max(1.35, reference.length / reference.width * 0.45);
    final maxWidth = reference.width * 1.75;
    final minLength = reference.length * 0.45;
    for (final part in parts) {
      final metrics = _maskMetrics(part, width, height, offsetX: 0, offsetY: 0);
      if (metrics == null) return false;
      if ((metrics['aspect_ratio'] as num).toDouble() < minAspect) {
        return false;
      }
      if ((metrics['width_px'] as num).toDouble() > maxWidth) return false;
      if ((metrics['length_px'] as num).toDouble() < minLength) return false;
    }
    return true;
  }

  static _MaskColorMetrics _maskColorMetrics(
    img.Image rgb,
    Uint8List mask,
    int width,
    int height, {
    required int offsetX,
    required int offsetY,
  }) {
    var count = 0;
    var skinCount = 0;
    var lumaSum = 0.0;
    for (var y = 0; y < height; y++) {
      final globalY = y + offsetY;
      if (globalY < 0 || globalY >= rgb.height) continue;
      for (var x = 0; x < width; x++) {
        if (mask[y * width + x] == 0) continue;
        final globalX = x + offsetX;
        if (globalX < 0 || globalX >= rgb.width) continue;
        final pixel = rgb.getPixel(globalX, globalY);
        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();
        count++;
        lumaSum += 0.299 * r + 0.587 * g + 0.114 * b;
        if (_isSkinLikePixel(r, g, b)) skinCount++;
      }
    }
    if (count == 0) return const _MaskColorMetrics(skinRatio: 0, luma: 0);
    return _MaskColorMetrics(
      skinRatio: skinCount / count,
      luma: lumaSum / count,
    );
  }

  static bool _isSkinLikePixel(double r, double g, double b) {
    final maxChannel = math.max(r, math.max(g, b));
    final minChannel = math.min(r, math.min(g, b));
    final cb = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b;
    final cr = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b;
    final rgbRule = r > 70 &&
        g > 35 &&
        b > 20 &&
        r > g &&
        r > b &&
        maxChannel - minChannel > 15;
    final ycbcrRule = cr >= 135 && cr <= 185 && cb >= 75 && cb <= 140;
    return rgbRule && ycbcrRule;
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

  static int _bitmapTextWidth(dynamic font, String text) {
    var width = 0;
    for (final codeUnit in text.codeUnits) {
      final character = font.characters[codeUnit];
      width += character == null
          ? (font.base as int) ~/ 2
          : character.xAdvance as int;
    }
    return width;
  }

  static void _drawReadableId(
    img.Image image,
    int id,
    int centerX,
    int centerY,
  ) {
    final text = '$id';
    final font =
        math.max(image.width, image.height) >= 720 ? img.arial48 : img.arial24;
    final textWidth = _bitmapTextWidth(font, text);
    final textHeight = font.lineHeight;
    final maxX = math.max(0, image.width - textWidth);
    final maxY = math.max(0, image.height - textHeight);
    final x = (centerX - textWidth ~/ 2).clamp(0, maxX).toInt();
    final y = (centerY - textHeight ~/ 2).clamp(0, maxY).toInt();
    const outlineOffsets = [
      [-2, -2],
      [0, -2],
      [2, -2],
      [-2, 0],
      [2, 0],
      [-2, 2],
      [0, 2],
      [2, 2],
    ];
    for (final offset in outlineOffsets) {
      img.drawString(
        image,
        text,
        font: font,
        x: x + offset[0],
        y: y + offset[1],
        color: img.ColorRgb8(0, 0, 0),
      );
    }
    img.drawString(
      image,
      text,
      font: font,
      x: x,
      y: y,
      color: img.ColorRgb8(255, 255, 255),
    );
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
      _drawReadableId(labelsImage, id, centroidX, centroidY);
    }
    return labelsImage;
  }

  Future<OrtSession> _loadSession() async {
    final existing = _session;
    if (existing != null) return existing;
    final options = Platform.isAndroid
        ? OrtSessionOptions(
            providers: const [OrtProvider.CPU],
            intraOpNumThreads: 1,
            interOpNumThreads: 1,
            useArena: false,
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
  final qcThreshold = _qcMadZThresholdFor(measurements);
  final outliers = _qcOutlierIndices(measurements, qcThreshold);
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
      'threshold': qcThreshold,
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

double _qcMadZThresholdFor(List<Map<String, dynamic>> measurements) {
  if (measurements.length < 5) return _qcMadZThreshold;

  double iqrRatio(String key) {
    final data = measurements
        .map((item) => ((item[key] as num?)?.toDouble() ?? 0))
        .toList()
      ..sort();
    final middle = _median(data);
    if (middle <= 1e-9) return 0;
    return (_percentile(data, 0.75) - _percentile(data, 0.25)) / middle;
  }

  final wideMetrics = [
    iqrRatio('area_px') >= 1.0,
    iqrRatio('length_px') >= 0.65,
    iqrRatio('width_px') >= 0.55,
  ].where((value) => value).length;
  return wideMetrics >= 2 ? _qcRelaxedMadZThreshold : _qcMadZThreshold;
}

Set<int> _qcOutlierIndices(
  List<Map<String, dynamic>> measurements,
  double threshold,
) {
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
      final isOutlier =
          mad <= 1e-9 ? deviation > 1e-9 : 0.6745 * deviation / mad > threshold;
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

double _percentile(List<double> sortedValues, double fraction) {
  if (sortedValues.isEmpty) return 0;
  final position = (sortedValues.length - 1) * fraction.clamp(0, 1);
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) return sortedValues[lower];
  final weight = position - lower;
  return sortedValues[lower] * (1 - weight) + sortedValues[upper] * weight;
}

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

class _MeasurementCandidate {
  final _Instance instance;
  final Map<String, dynamic> metrics;
  final _MaskColorMetrics color;

  const _MeasurementCandidate(this.instance, this.metrics, this.color);

  double get priority {
    final area = ((metrics['area_px'] as num?)?.toDouble() ?? 0).clamp(1, 1e9);
    final areaPenalty = math.log(area) / 80;
    final skinPenalty = color.skinRatio * 0.35;
    return instance.confidence - areaPenalty - skinPenalty;
  }
}

class _MaskColorMetrics {
  final double skinRatio;
  final double luma;

  const _MaskColorMetrics({
    required this.skinRatio,
    required this.luma,
  });
}

class _SizeReference {
  final double area;
  final double length;
  final double width;
  final bool splitEnabled;
  final double areaSplitUpper;
  final double lengthSplitUpper;
  final double widthSplitUpper;
  final double areaUpper;

  const _SizeReference({
    required this.area,
    required this.length,
    required this.width,
    required this.splitEnabled,
    required this.areaSplitUpper,
    required this.lengthSplitUpper,
    required this.widthSplitUpper,
    required this.areaUpper,
  });
}

class _ProjectionSplitResult {
  final List<Uint8List> masks;
  final double score;

  const _ProjectionSplitResult(this.masks, this.score);
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
  final List<_Instance> rawInstances;
  final int rawDetectionCount;
  final int passCount;
  final int roiRegionCount;
  final int roiPassCount;
  final int tilePassCount;
  final int width;
  final int height;
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
    required this.rawInstances,
    required this.rawDetectionCount,
    required this.passCount,
    required this.roiRegionCount,
    required this.roiPassCount,
    required this.tilePassCount,
    required this.width,
    required this.height,
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

class _OfflineInferencePass {
  final Float32List predictions;
  final Float32List protos;
  final int width;
  final int height;
  final int paddedSide;
  final int offsetX;
  final int offsetY;
  final String source;

  const _OfflineInferencePass({
    required this.predictions,
    required this.protos,
    required this.width,
    required this.height,
    required this.paddedSide,
    required this.offsetX,
    required this.offsetY,
    required this.source,
  });
}

class _DecodedInferencePass {
  final int rawDetectionCount;
  final List<_Instance> instances;

  const _DecodedInferencePass({
    required this.rawDetectionCount,
    required this.instances,
  });
}

class _RoiBox {
  final int x;
  final int y;
  final int width;
  final int height;

  const _RoiBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory _RoiBox.fromBounds(int x1, int y1, int x2, int y2) => _RoiBox(
        x: x1,
        y: y1,
        width: math.max(0, x2 - x1),
        height: math.max(0, y2 - y1),
      );

  int get area => width * height;

  _RoiBox union(_RoiBox other) {
    final x1 = math.min(x, other.x);
    final y1 = math.min(y, other.y);
    final x2 = math.max(x + width, other.x + other.width);
    final y2 = math.max(y + height, other.y + other.height);
    return _RoiBox.fromBounds(x1, y1, x2, y2);
  }
}

class _RgbColor {
  final double r;
  final double g;
  final double b;

  const _RgbColor(this.r, this.g, this.b);
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

  Map<String, dynamic> asApiJson(String fileName) {
    final maskBase64 = base64Encode(maskPng);
    return {
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
      'original_png_base64': '',
      'overlay_png_base64': base64Encode(overlayPng),
      'sam_mask_png_base64': maskBase64,
      'labels_png_base64': base64Encode(labelsPng),
      'mask_png_base64': maskBase64,
      'label_map_png_base64': base64Encode(labelMapPng),
    };
  }
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
