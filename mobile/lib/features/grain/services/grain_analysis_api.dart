import 'dart:async';
import 'dart:typed_data';

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
    OfflineProgressCallback? onProgress,
  }) async {
    final localAnalysis = await _offlineAnalyzer.analyze(
      bytes,
      referencePixels: referencePixels,
      referenceMm: referenceMm,
      referenceX1: referenceX1,
      referenceY1: referenceY1,
      referenceX2: referenceX2,
      referenceY2: referenceY2,
      onProgress: onProgress,
    );
    final localResult = GrainAnalysisResult.fromJson(
      localAnalysis.asApiJson(fileName),
    );
    await _localStore.save({
      'pendingSync': true,
      'clientRunId': localResult.run['id']?.toString() ?? '',
      'sourceFileName': fileName,
      'createdAt': DateTime.now().toIso8601String(),
      'result': localResult.toJson(),
    });

    if (!await isGuestMode()) {
      unawaited(_syncPendingRunsInBackground());
    }
    return localResult;
  }

  Future<GrainRunDetail> getRun(String id) async {
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
    final response = await _client.get('/grain/runs/$id');
    return GrainRunDetail.fromJson(
      Map<String, dynamic>.from(response.data['data'] as Map),
    );
  }

  Future<bool> isGuestMode() async =>
      await _storage.read(key: guestModeKey) == 'true';

  Future<void> syncPendingRuns() async {
    final pending = await _localStore.readPendingForSync();
    if (pending.isEmpty) return;
    await _client.post('/grain/runs/import', data: {'items': pending});
    await _localStore.removePendingForSync();
  }

  Future<void> _syncPendingRunsInBackground() async {
    try {
      await syncPendingRuns();
    } catch (_) {
      // Connectivity service retries pending local runs later.
    }
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
  double get rawStdLengthPx => _asDouble(summary['std_length_px']);
  double get rawStdWidthPx => _asDouble(summary['std_width_px']);
  double? get rawStdLengthMm =>
      calibrated ? _statDouble(summary['std_length_mm']) : null;
  double? get rawStdWidthMm =>
      calibrated ? _statDouble(summary['std_width_mm']) : null;
  bool get qcRobustUsedForReporting {
    final qc = summary['qc'];
    return qc is! Map || qc['robust_used_for_reporting'] != false;
  }

  dynamic _reportedStd(String rawKey, String robustKey) =>
      qcRobustUsedForReporting
          ? (summary[robustKey] ?? summary[rawKey])
          : summary[rawKey];

  double get qcStdAreaPx =>
      _asDouble(_reportedStd('std_area_px', 'robust_std_area_px'));
  double get qcStdLengthPx =>
      _asDouble(_reportedStd('std_length_px', 'robust_std_length_px'));
  double get qcStdWidthPx =>
      _asDouble(_reportedStd('std_width_px', 'robust_std_width_px'));
  double? get qcStdAreaMm2 => calibrated
      ? _statDouble(_reportedStd('std_area_mm2', 'robust_std_area_mm2'))
      : null;
  double? get qcStdLengthMm => calibrated
      ? _statDouble(_reportedStd('std_length_mm', 'robust_std_length_mm'))
      : null;
  double? get qcStdWidthMm => calibrated
      ? _statDouble(_reportedStd('std_width_mm', 'robust_std_width_mm'))
      : null;
  int get qcSuspectCount {
    final qc = summary['qc'];
    return qc is Map ? _asInt(qc['suspect_count']) : 0;
  }

  int get qcInlierCount {
    final qc = summary['qc'];
    return qc is Map ? _asInt(qc['inlier_count']) : count;
  }

  String get qcSuspectIdsLabel {
    final qc = summary['qc'];
    final rawIds = qc is Map ? qc['suspect_ids'] : null;
    if (rawIds is! List || rawIds.isEmpty) return '';
    final ids = rawIds.take(8).map((id) => '#${_asInt(id)}').join(', ');
    return rawIds.length > 8 ? '$ids, ...' : ids;
  }

  String previewBase64(String key) => previews[key] ?? '';

  String previewWithFallback(String key) {
    final selected = previewBase64(key);
    if (selected.isNotEmpty) return selected;
    if (key != 'overlay') {
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
  return parsed.isFinite && parsed > 0 ? parsed : null;
}

double? _statDouble(dynamic value) {
  if (value == null) return null;
  final parsed = _asDouble(value);
  return parsed.isFinite && parsed >= 0 ? parsed : null;
}
