import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class OfflineGrainAnalyzer {
  static const modelAssetPath = 'assets/models/best_float16.tflite';
  static const _inputSize = 640;
  static const _protoSize = 160;
  static const _confidence = 0.25;
  static const _iou = 0.60;
  static const _maxDetections = 300;

  Interpreter? _interpreter;

  Future<OfflineModelInfo> loadModelInfo() async {
    final interpreter = _interpreter ??= await Interpreter.fromAsset(modelAssetPath);
    return OfflineModelInfo(
      modelAssetPath: modelAssetPath,
      inputTensors: interpreter.getInputTensors().map(_tensorInfo).toList(),
      outputTensors: interpreter.getOutputTensors().map(_tensorInfo).toList(),
    );
  }

  Future<OfflineAnalyzeResult> analyze(Uint8List imageBytes) async {
    final interpreter = _interpreter ??= await Interpreter.fromAsset(modelAssetPath);
    final original = img.decodeImage(imageBytes);
    if (original == null) throw StateError('Cannot decode selected image.');

    final side = math.max(original.width, original.height);
    final square = img.Image(width: side, height: side, numChannels: 3);
    img.compositeImage(square, original, dstX: 0, dstY: 0);
    final resized = img.copyResize(square, width: _inputSize, height: _inputSize);
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
    final predictions = List.generate(1, (_) => List.generate(38, (_) => List.filled(8400, 0.0)));
    final protos = List.generate(
      1,
      (_) => List.generate(
        _protoSize,
        (_) => List.generate(_protoSize, (_) => List.filled(32, 0.0)),
      ),
    );
    interpreter.runForMultipleInputs([input], {0: predictions, 1: protos});

    final selected = _decodePredictions(predictions[0]);
    final overlay = img.Image.from(original);
    final measurements = <Map<String, dynamic>>[];
    var totalArea = 0.0;
    var totalLength = 0.0;
    var totalWidth = 0.0;

    for (var index = 0; index < selected.length; index++) {
      final detection = selected[index];
      final measured = _renderMask(
        overlay,
        protos[0],
        detection,
        originalWidth: original.width,
        originalHeight: original.height,
        paddedSide: side,
        labelIndex: index + 1,
      );
      if (measured == null) continue;
      measurements.add(measured);
      totalArea += measured['area_px'] as double;
      totalLength += measured['length_px'] as double;
      totalWidth += measured['width_px'] as double;
    }

    final count = measurements.length;
    return OfflineAnalyzeResult(
      count: count,
      overlayPng: Uint8List.fromList(img.encodePng(overlay)),
      imageWidth: original.width,
      imageHeight: original.height,
      measurements: measurements,
      summary: {
        'count': count,
        'mean_area_px': count == 0 ? 0 : totalArea / count,
        'mean_length_px': count == 0 ? 0 : totalLength / count,
        'mean_width_px': count == 0 ? 0 : totalWidth / count,
      },
      segmentation: {
        'pipeline': 'tflite_yolo_seg_mobile',
        'confidence': _confidence,
        'iou': _iou,
        'max_det': _maxDetections,
        'candidate_count': selected.length,
        'seed_candidate_count': selected.length,
        'ref_candidate_count': 0,
        'offline': true,
      },
    );
  }

  List<_Detection> _decodePredictions(List<List<double>> prediction) {
    final candidates = <_Detection>[];
    for (var i = 0; i < 8400; i++) {
      final seedScore = prediction[4][i];
      final refScore = prediction[5][i];
      if (seedScore < _confidence || refScore > seedScore) continue;
      final cx = prediction[0][i];
      final cy = prediction[1][i];
      final width = prediction[2][i];
      final height = prediction[3][i];
      candidates.add(
        _Detection(
          score: seedScore,
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

  Map<String, dynamic>? _renderMask(
    img.Image overlay,
    List<List<List<double>>> protos,
    _Detection detection, {
    required int originalWidth,
    required int originalHeight,
    required int paddedSide,
    required int labelIndex,
  }) {
    final scale = paddedSide / _inputSize;
    final x1 = (detection.x1 * scale).floor().clamp(0, originalWidth);
    final y1 = (detection.y1 * scale).floor().clamp(0, originalHeight);
    final x2 = (detection.x2 * scale).ceil().clamp(0, originalWidth);
    final y2 = (detection.y2 * scale).ceil().clamp(0, originalHeight);
    if (x2 <= x1 || y2 <= y1) return null;

    var area = 0;
    var minX = originalWidth;
    var minY = originalHeight;
    var maxX = 0;
    var maxY = 0;
    for (var y = y1; y < y2; y++) {
      final py = ((y / paddedSide) * _protoSize).floor().clamp(0, _protoSize - 1);
      for (var x = x1; x < x2; x++) {
        final px = ((x / paddedSide) * _protoSize).floor().clamp(0, _protoSize - 1);
        var logit = 0.0;
        for (var c = 0; c < 32; c++) {
          logit += detection.coefficients[c] * protos[py][px][c];
        }
        if (_sigmoid(logit) <= 0.5) continue;
        area++;
        minX = math.min(minX, x);
        minY = math.min(minY, y);
        maxX = math.max(maxX, x);
        maxY = math.max(maxY, y);
        final source = overlay.getPixel(x, y);
        overlay.setPixelRgb(
          x,
          y,
          (source.r * 0.55 + 36 * 0.45).round(),
          (source.g * 0.55 + 160 * 0.45).round(),
          (source.b * 0.55 + 92 * 0.45).round(),
        );
      }
    }
    if (area == 0) return null;
    final width = (maxX - minX + 1).toDouble();
    final height = (maxY - minY + 1).toDouble();
    return {
      'id': labelIndex,
      'class_id': 0,
      'class_name': 'seed',
      'confidence': detection.score,
      'area_px': area.toDouble(),
      'length_px': math.max(width, height),
      'width_px': math.min(width, height),
      'bbox': {'x1': minX, 'y1': minY, 'x2': maxX, 'y2': maxY},
    };
  }

  void close() {
    _interpreter?.close();
    _interpreter = null;
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

double _sigmoid(double value) => 1 / (1 + math.exp(-value.clamp(-88.0, 88.0)));

OfflineTensorInfo _tensorInfo(Tensor tensor) => OfflineTensorInfo(
      name: tensor.name,
      shape: List<int>.from(tensor.shape),
      type: tensor.type.toString(),
    );

class _Detection {
  final double score;
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final List<double> coefficients;

  const _Detection({
    required this.score,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.coefficients,
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

  const OfflineTensorInfo({required this.name, required this.shape, required this.type});
}

class OfflineAnalyzeResult {
  final int count;
  final Uint8List overlayPng;
  final int imageWidth;
  final int imageHeight;
  final List<Map<String, dynamic>> measurements;
  final Map<String, dynamic> summary;
  final Map<String, dynamic> segmentation;

  const OfflineAnalyzeResult({
    required this.count,
    required this.overlayPng,
    required this.imageWidth,
    required this.imageHeight,
    required this.measurements,
    required this.summary,
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
        'image': {'width': imageWidth, 'height': imageHeight},
        'summary': summary,
        'segmentation': segmentation,
        'calibration': {'enabled': false},
        'features': {'source': 'mobile_tflite'},
        'measurements': measurements,
        'csv': '',
        'overlay_png_base64': base64Encode(overlayPng),
        'sam_mask_png_base64': '',
        'labels_png_base64': '',
        'mask_png_base64': '',
      };
}
