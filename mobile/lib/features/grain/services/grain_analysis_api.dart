import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';

class GrainAnalysisApi {
  final ApiClient _client;

  GrainAnalysisApi({ApiClient? client}) : _client = client ?? ApiClient();

  Future<GrainAnalysisResult> analyzeImage({
    required Uint8List bytes,
    required String fileName,
    double? referencePixels,
    double? referenceMm,
  }) async {
    final form = FormData.fromMap({
      'image': MultipartFile.fromBytes(bytes, filename: fileName),
      if (referencePixels != null && referencePixels > 0)
        'referencePixels': referencePixels.toString(),
      if (referenceMm != null && referenceMm > 0)
        'referenceMm': referenceMm.toString(),
      if (referencePixels != null && referencePixels > 0)
        'referencePixelSpace': 'original',
    });

    final response = await _client.dio.post(
      '/grain/analyze',
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    );
    return GrainAnalysisResult.fromJson(
      Map<String, dynamic>.from(response.data['data'] as Map),
    );
  }

  Future<GrainRunDetail> getRun(String id) async {
    final response = await _client.get('/grain/runs/$id');
    return GrainRunDetail.fromJson(
      Map<String, dynamic>.from(response.data['data'] as Map),
    );
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
        'overlay': json['overlay_png_base64']?.toString() ?? '',
        'labels': json['labels_png_base64']?.toString() ?? '',
        'mask': json['mask_png_base64']?.toString() ?? '',
        'seedMask': json['seed_mask_png_base64']?.toString() ?? '',
        'kmeansMask': json['kmeans_mask_png_base64']?.toString() ?? '',
        'clusters': json['cluster_png_base64']?.toString() ?? '',
      },
    );
  }

  int get count => _asInt(summary['count']);
  double get meanAreaPx => _asDouble(summary['mean_area_px']);
  double get meanLengthPx => _asDouble(summary['mean_length_px']);
  double get meanWidthPx => _asDouble(summary['mean_width_px']);
  double? get meanAreaMm2 => _nullableDouble(summary['mean_area_mm2']);
  double? get meanLengthMm => _nullableDouble(summary['mean_length_mm']);
  double? get meanWidthMm => _nullableDouble(summary['mean_width_mm']);
  bool get calibrated => calibration['enabled'] == true;

  String previewBase64(String key) => previews[key] ?? '';
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
