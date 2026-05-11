import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';
import '../../auth/providers/auth_provider.dart';

final grainRunsProvider = FutureProvider<List<GrainRun>>((ref) async {
  try {
    final response =
        await ApiClient().get('/grain/runs', params: {'limit': 100});
    final data = response.data['data'] as Map<String, dynamic>? ?? {};
    final items = data['items'] as List<dynamic>? ?? [];
    return items
        .map(
            (item) => GrainRun.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  } on DioException catch (error) {
    if (error.response?.statusCode == 401) {
      const storage = FlutterSecureStorage();
      await storage.delete(key: accessTokenKey);
      await storage.delete(key: refreshTokenKey);
      await storage.delete(key: userKey);
      ref.invalidate(authStateProvider);
      throw const GrainRunsException(
        'Phien dang nhap da het han. Vui long dang nhap lai.',
      );
    }
    throw GrainRunsException(_friendlyDioMessage(error));
  }
});

String _friendlyDioMessage(DioException error) {
  return switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.sendTimeout =>
      'Khong ket noi duoc backend. Kiem tra server va BASE_URL.',
    DioExceptionType.connectionError =>
      'Khong ket noi duoc backend. Hay dam bao server dang chay.',
    _ => 'Khong tai duoc thong ke tu backend.',
  };
}

class GrainRunsException implements Exception {
  final String message;

  const GrainRunsException(this.message);

  @override
  String toString() => message;
}

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
