import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:seed_mobile/features/grain/services/offline_grain_analyzer.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('offline grain analyzer benchmark', (tester) async {
    const rawPaths = String.fromEnvironment(
      'SEED_BENCHMARK_IMAGES',
      defaultValue: '/sdcard/Download/SeedBench/adzuki_1.jpg',
    );
    const iterations = int.fromEnvironment(
      'SEED_BENCHMARK_ITERATIONS',
      defaultValue: 2,
    );
    final paths = rawPaths
        .split(';')
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toList();
    final analyzer = OfflineGrainAnalyzer();
    addTearDown(analyzer.close);

    final rows = <Map<String, dynamic>>[];
    for (final path in paths) {
      final bytes = await File(path).readAsBytes();
      for (var iteration = 0; iteration < iterations; iteration++) {
        final stopwatch = Stopwatch()..start();
        final result = await analyzer.analyze(Uint8List.fromList(bytes));
        stopwatch.stop();
        final row = <String, dynamic>{
          'image': path.split('/').last,
          'iteration': iteration + 1,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
          'count': result.summary['count'],
          'qc_status': (result.summary['qc'] as Map?)?['status'],
          'model_profile': result.segmentation['model_profile'],
          'model_input_size': result.segmentation['model_input_size'],
          'intra_op_threads': result.segmentation['intra_op_threads'],
          'preview_width': result.segmentation['preview_width'],
          'preview_height': result.segmentation['preview_height'],
          'preview_scale': result.segmentation['preview_scale'],
          'multi_pass_count': result.segmentation['multi_pass_count'],
          'candidate_count': result.segmentation['candidate_count'],
          'segment_count': result.segmentation['segment_count'],
          'fallback_reason': result.segmentation['fallback_reason'],
          'memory': await _readMemoryInfo(),
        };
        rows.add(row);
        // Stable prefix makes adb/flutter logs easy to parse.
        // ignore: avoid_print
        print('SEED_BENCHMARK ${jsonEncode(row)}');
      }
    }
    binding.reportData = <String, dynamic>{'seed_benchmark': rows};
  });
}

Future<Map<String, dynamic>?> _readMemoryInfo() async {
  const channel = MethodChannel('vn.mekonglab.seedvision/device_memory');
  try {
    final result = await channel.invokeMethod<Map<dynamic, dynamic>>(
      'getMemoryInfo',
    );
    if (result == null) return null;
    return result.map((key, value) => MapEntry(key.toString(), value));
  } catch (_) {
    return null;
  }
}
