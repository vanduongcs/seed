import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../grain/providers/grain_runs_provider.dart';
import '../../grain/services/offline_grain_analyzer.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runsState = ref.watch(grainRunsProvider);

    return runsState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _DashboardContent(
        stats: const _DashboardStats.empty(),
        error: error.toString(),
      ),
      data: (runs) => _DashboardContent(stats: _DashboardStats.fromRuns(runs)),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  final _DashboardStats stats;
  final String? error;

  const _DashboardContent({required this.stats, this.error});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Tổng quan mẫu hạt',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          'Thống kê được lấy từ các lần xử lý ảnh đã lưu trên backend.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        if (error != null) ...[
          const SizedBox(height: 14),
          Text(error!, style: TextStyle(color: Colors.red.shade700)),
        ],
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
                child: _StatTile(
                    label: 'Tháng này', value: '${stats.thisMonthRuns}')),
            const SizedBox(width: 12),
            Expanded(
                child:
                    _StatTile(label: 'Tổng lượt', value: '${stats.totalRuns}')),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: _StatTile(
                    label: 'Hạt đã đo', value: '${stats.totalSeeds}')),
            const SizedBox(width: 12),
            Expanded(
                child: _StatTile(
                    label: 'Dài TB',
                    value: '${stats.meanLengthPx.toStringAsFixed(1)} px')),
          ],
        ),
        const SizedBox(height: 18),
        const _OfflineAiCard(),
        const SizedBox(height: 18),
        const _ProcessCard(),
      ],
    );
  }
}

class _DashboardStats {
  final int totalRuns;
  final int thisMonthRuns;
  final int totalSeeds;
  final double meanLengthPx;

  const _DashboardStats({
    required this.totalRuns,
    required this.thisMonthRuns,
    required this.totalSeeds,
    required this.meanLengthPx,
  });

  const _DashboardStats.empty()
      : totalRuns = 0,
        thisMonthRuns = 0,
        totalSeeds = 0,
        meanLengthPx = 0;

  factory _DashboardStats.fromRuns(List<GrainRun> runs) {
    final now = DateTime.now();
    final thisMonthRuns = runs.where((run) {
      final createdAt = run.createdAt;
      return createdAt != null &&
          createdAt.year == now.year &&
          createdAt.month == now.month;
    }).length;
    final totalSeeds = runs.fold<int>(0, (sum, run) => sum + run.count);
    final lengthSum = runs.fold<double>(
      0,
      (sum, run) => sum + (run.meanLengthPx * run.count),
    );

    return _DashboardStats(
      totalRuns: runs.length,
      thisMonthRuns: thisMonthRuns,
      totalSeeds: totalSeeds,
      meanLengthPx: totalSeeds == 0 ? 0 : lengthSum / totalSeeds,
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;

  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProcessCard extends StatelessWidget {
  const _ProcessCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.image_search_outlined,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Pipeline xử lý ảnh',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Mobile có thể xử lý AI offline trực tiếp trên thiết bị. Backend vẫn giữ vai trò lưu lịch sử, xử lý nâng cao và đồng bộ kết quả khi cần.',
              style: TextStyle(color: AppTheme.textSecondary, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineAiCard extends StatefulWidget {
  const _OfflineAiCard();

  @override
  State<_OfflineAiCard> createState() => _OfflineAiCardState();
}

class _OfflineAiCardState extends State<_OfflineAiCard> {
  final _picker = ImagePicker();
  final _analyzer = OfflineGrainAnalyzer();
  final _referencePixelsController = TextEditingController();
  final _referenceMmController = TextEditingController();
  Uint8List? _selectedBytes;
  OfflineGrainResult? _result;
  String? _error;
  bool _busy = false;
  bool _showManualCalibration = false;

  @override
  void dispose() {
    _referencePixelsController.dispose();
    _referenceMmController.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      imageQuality: 92,
      maxWidth: 2200,
      maxHeight: 2200,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _selectedBytes = bytes;
      _result = null;
      _error = null;
    });
  }

  Future<void> _analyzeLocal() async {
    final bytes = _selectedBytes;
    if (bytes == null) {
      setState(() => _error = 'Chọn ảnh hoặc chụp ảnh trước khi xử lý local.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final referencePixels =
          double.tryParse(_referencePixelsController.text.trim());
      final referenceMm = double.tryParse(_referenceMmController.text.trim());
      final result = await _analyzer.analyze(
        bytes,
        referencePixels: referencePixels != null && referencePixels > 0
            ? referencePixels
            : null,
        referenceMm:
            referenceMm != null && referenceMm > 0 ? referenceMm : null,
      );
      if (!mounted) return;
      setState(() => _result = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppTheme.secondary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.memory, color: AppTheme.secondary),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'AI offline trên điện thoại',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Chạy model TFLite local trong app, không gửi ảnh lên server. Model cần đặt tại assets/models/seed_segmentation.tflite.',
              style: TextStyle(color: AppTheme.textSecondary, height: 1.45),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Chọn ảnh'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Camera'),
                ),
                ElevatedButton.icon(
                  onPressed: _busy ? null : _analyzeLocal,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.offline_bolt_outlined),
                  label: const Text('Xử lý local'),
                ),
              ],
            ),
            if (_selectedBytes != null) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  _selectedBytes!,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => setState(() {
                  _showManualCalibration = !_showManualCalibration;
                }),
                icon: const Icon(Icons.straighten),
                label: Text(_showManualCalibration
                    ? 'Ẩn quy đổi mm thủ công'
                    : 'Quy đổi mm thủ công'),
              ),
              if (_showManualCalibration) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _referencePixelsController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Vật mốc (px)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _referenceMmController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Vật mốc (mm)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            ],
            if (result != null) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                      child: _OfflineStat(
                          label: 'Số hạt', value: '${result.count}')),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _OfflineStat(
                          label: 'Thời gian', value: '${result.elapsedMs} ms')),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _OfflineStat(
                      label: 'Dài TB',
                      value: result.meanLengthMm == null
                          ? '${result.meanLengthPx.toStringAsFixed(1)} px'
                          : '${result.meanLengthMm!.toStringAsFixed(2)} mm',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _OfflineStat(
                      label: 'Rộng TB',
                      value: result.meanWidthMm == null
                          ? '${result.meanWidthPx.toStringAsFixed(1)} px'
                          : '${result.meanWidthMm!.toStringAsFixed(2)} mm',
                    ),
                  ),
                ],
              ),
              if (result.mmPerPixel != null) ...[
                const SizedBox(height: 10),
                _OfflineStat(
                  label: 'Tỷ lệ',
                  value: '${result.mmPerPixel!.toStringAsFixed(5)} mm/px',
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Model ${result.modelInputWidth} x ${result.modelInputHeight}, mask ${result.maskWidth} x ${result.maskHeight}',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(result.overlayPngBytes),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OfflineStat extends StatelessWidget {
  final String label;
  final String value;

  const _OfflineStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.bgDefault,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
