import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final grainRunsProvider = FutureProvider<List<GrainRun>>((ref) async {
  final response = await ApiClient().get('/grain/runs', params: {'limit': 100});
  final data = response.data['data'] as Map<String, dynamic>? ?? {};
  final items = data['items'] as List<dynamic>? ?? [];
  return items
      .map((item) => GrainRun.fromJson(Map<String, dynamic>.from(item as Map)))
      .toList();
});

class GrainRun {
  final String id;
  final String sourceFileName;
  final DateTime? createdAt;
  final int count;
  final double meanLengthPx;
  final double meanWidthPx;
  final int imageWidth;
  final int imageHeight;

  const GrainRun({
    required this.id,
    required this.sourceFileName,
    required this.createdAt,
    required this.count,
    required this.meanLengthPx,
    required this.meanWidthPx,
    required this.imageWidth,
    required this.imageHeight,
  });

  factory GrainRun.fromJson(Map<String, dynamic> json) {
    final summary = Map<String, dynamic>.from(json['summary'] as Map? ?? {});
    final image = Map<String, dynamic>.from(json['image'] as Map? ?? {});
    return GrainRun(
      id: json['id']?.toString() ?? '',
      sourceFileName: json['sourceFileName']?.toString() ?? 'image.png',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      count: _asInt(summary['count']),
      meanLengthPx: _asDouble(summary['mean_length_px']),
      meanWidthPx: _asDouble(summary['mean_width_px']),
      imageWidth: _asInt(image['width']),
      imageHeight: _asInt(image['height']),
    );
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
