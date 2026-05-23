import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';
import 'local_grain_run_store.dart';
import 'offline_grain_analyzer.dart';

class GrainAnalysisApi {
  final ApiClient _client;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final LocalGrainRunStore _localStore = LocalGrainRunStore();
  final OfflineGrainAnalyzer _offlineAnalyzer = OfflineGrainAnalyzer();

  GrainAnalysisApi({ApiClient? client}) : _client = client ?? ApiClient();

  Future<GrainAnalysisResult> analyzeImage({
    required Uint8List bytes,
    required String fileName,
    double? referencePixels,
    double? referenceMm,
    double? referenceX1,
    double? referenceY1,
    double? referenceX2,
    double? referenceY2,
  }) async {
    final guestMode = await isGuestMode();
    GrainAnalysisResult? localResult;
    try {
      final offlineResult = await _offlineAnalyzer.analyze(
        bytes,
        referencePixels: referencePixels,
        referenceMm: referenceMm,
        referenceX1: referenceX1,
        referenceY1: referenceY1,
        referenceX2: referenceX2,
        referenceY2: referenceY2,
      );
      localResult = GrainAnalysisResult.fromJson(offlineResult.asApiJson(fileName));
    } catch (_) {
      // Fall back to server analysis if this device cannot execute TFLite.
    }
    if (localResult != null) {
      await _localStore.save({
        'clientRunId': localResult.run['id']?.toString() ?? '',
        'sourceFileName': fileName,
        'createdAt': DateTime.now().toIso8601String(),
        'result': localResult.toJson(),
      });
      if (!guestMode) {
        try {
          await syncPendingRuns();
        } catch (_) {
          // Preserve local runs until the next successful authenticated sync.
        }
      }
      return localResult;
    }

    final form = FormData.fromMap({
      'image': MultipartFile.fromBytes(bytes, filename: fileName),
      if (referencePixels != null && referencePixels > 0)
        'referencePixels': referencePixels.toString(),
      if (referenceMm != null && referenceMm > 0)
        'referenceMm': referenceMm.toString(),
      if (referencePixels != null && referencePixels > 0)
        'referencePixelSpace': 'original',
      if (referenceX1 != null) 'referenceX1': referenceX1.toString(),
      if (referenceY1 != null) 'referenceY1': referenceY1.toString(),
      if (referenceX2 != null) 'referenceX2': referenceX2.toString(),
      if (referenceY2 != null) 'referenceY2': referenceY2.toString(),
    });

    final response = await _client.post(
      guestMode ? '/grain/analyze-public' : '/grain/analyze',
      data: form,
      options: Options(
        contentType: 'multipart/form-data',
        sendTimeout: const Duration(seconds: 300),
        receiveTimeout: const Duration(seconds: 300),
      ),
    );
    final result = GrainAnalysisResult.fromJson(
      Map<String, dynamic>.from(response.data['data'] as Map),
    );
    if (guestMode) {
      await _localStore.save({
        'clientRunId': result.run['id']?.toString() ?? '',
        'sourceFileName': fileName,
        'createdAt': DateTime.now().toIso8601String(),
        'result': result.toJson(),
      });
    }
    return result;
  }

  Future<GrainRunDetail> getRun(String id) async {
    if (id.startsWith('local-')) {
      final localRuns = await _localStore.readAll();
      for (final localRun in localRuns) {
        final rawResult = localRun['result'];
        if (rawResult is! Map) continue;
        final result = GrainAnalysisResult.fromJson(
          Map<String, dynamic>.from(rawResult),
        );
        if (result.run['id']?.toString() == id) {
          return GrainRunDetail(run: result.run, result: result);
        }
      }
    }
    final response = await _client.get('/grain/runs/$id');
    return GrainRunDetail.fromJson(
      Map<String, dynamic>.from(response.data['data'] as Map),
    );
  }

  Future<bool> isGuestMode() async =>
      await _storage.read(key: guestModeKey) == 'true';

  Future<void> syncPendingRuns() async {
    final pending = await _localStore.readAll();
    if (pending.isEmpty) return;
    await _client.post('/grain/runs/import', data: {'items': pending});
    await _localStore.clear();
  }
}

class GrainRunDetail {
  final Map<String, dynamic> run;
  final GrainAnalysisResult result;

  const GrainRunDetail({required this.run, required this.result});

  factory GrainRunDetail.fromJson(Map<String, dynamic> json) {
    return GrainRunDetail(
      run: Map<String, dynamic>.from(json['run'] as Map? ?? {}),
      result: GrainAnalysisResult.fromJson(
        Map<String, dynamic>.from(json['result'] as Map? ?? {}),
      ),
    );
  }
}

class GrainAnalysisResult {
  final Map<String, dynamic> run;
  final Map<String, dynamic> image;
  final Map<String, dynamic> summary;
  final Map<String, dynamic> segmentation;
  final Map<String, dynamic> calibration;
  final List<Map<String, dynamic>> measurements;
  final String csv;
  final Map<String, String> previews;

  const GrainAnalysisResult({
    required this.run,
    required this.image,
    required this.summary,
    required this.segmentation,
    required this.calibration,
    required this.measurements,
    required this.csv,
    required this.previews,
  });

  factory GrainAnalysisResult.fromJson(Map<String, dynamic> json) {
    final rawMeasurements = json['measurements'] as List<dynamic>? ?? const [];
    return GrainAnalysisResult(
      run: Map<String, dynamic>.from(json['run'] as Map? ?? {}),
      image: Map<String, dynamic>.from(json['image'] as Map? ?? {}),
      summary: Map<String, dynamic>.from(json['summary'] as Map? ?? {}),
      segmentation:
          Map<String, dynamic>.from(json['segmentation'] as Map? ?? {}),
      calibration: Map<String, dynamic>.from(json['calibration'] as Map? ?? {}),
      measurements: rawMeasurements
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(),
      csv: json['csv']?.toString() ?? '',
      previews: {
        'original': json['original_png_base64']?.toString() ?? '',
        'preprocessed': json['preprocessed_png_base64']?.toString() ?? '',
        'overlay': json['overlay_png_base64']?.toString() ?? '',
        'samMask': json['sam_mask_png_base64']?.toString() ?? '',
        'labels': json['labels_png_base64']?.toString() ?? '',
        'mask': json['mask_png_base64']?.toString() ?? '',
      },
    );
  }

  Map<String, dynamic> toJson() => {
        'run': run,
        'image': image,
        'summary': summary,
        'segmentation': segmentation,
        'calibration': calibration,
        'features': {},
        'measurements': measurements,
        'csv': csv,
        'original_png_base64': previews['original'] ?? '',
        'preprocessed_png_base64': previews['preprocessed'] ?? '',
        'overlay_png_base64': previews['overlay'] ?? '',
        'sam_mask_png_base64': previews['samMask'] ?? '',
        'labels_png_base64': previews['labels'] ?? '',
        'mask_png_base64': previews['mask'] ?? '',
      };

  int get count => _asInt(summary['count']);
  double get meanAreaPx => _asDouble(summary['mean_area_px']);
  double get meanLengthPx => _asDouble(summary['mean_length_px']);
  double get meanWidthPx => _asDouble(summary['mean_width_px']);
  double? get meanAreaMm2 => _nullableDouble(summary['mean_area_mm2']);
  double? get meanLengthMm => _nullableDouble(summary['mean_length_mm']);
  double? get meanWidthMm => _nullableDouble(summary['mean_width_mm']);
  bool get calibrated => calibration['enabled'] == true;

  String previewBase64(String key) => previews[key] ?? '';

  String previewWithFallback(String key) {
    final selected = previewBase64(key);
    if (selected.isNotEmpty) return selected;
    if (key == 'samMask') {
      final mask = previewBase64('mask');
      if (mask.isNotEmpty) return mask;
      final overlay = previewBase64('overlay');
      if (overlay.isNotEmpty) return overlay;
    }
    return '';
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _asDouble(dynamic value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

double? _nullableDouble(dynamic value) {
  if (value == null) return null;
  final parsed = _asDouble(value);
  return parsed.isFinite ? parsed : null;
}
