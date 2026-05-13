import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../grain/providers/grain_runs_provider.dart';
import '../../grain/services/grain_analysis_api.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runsState = ref.watch(grainRunsProvider);

    return runsState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _DashboardContent(
        stats: const _DashboardStats.empty(),
        historyError: error.toString(),
      ),
      data: (runs) => _DashboardContent(stats: _DashboardStats.fromRuns(runs)),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  final _DashboardStats stats;
  final String? historyError;

  const _DashboardContent({required this.stats, this.historyError});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Phan tich hat',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          'Mobile dung chung pipeline backend voi web: SAM/FastSAM, GridFree color features, watershed, measurement va export.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        if (historyError != null) ...[
          const SizedBox(height: 14),
          Text(historyError!, style: TextStyle(color: Colors.red.shade700)),
        ],
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
                child: _StatTile(
                    label: 'Luot thang nay', value: '${stats.thisMonthRuns}')),
            const SizedBox(width: 12),
            Expanded(
                child:
                    _StatTile(label: 'Tong luot', value: '${stats.totalRuns}')),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: _StatTile(
                    label: 'Hat da do', value: '${stats.totalSeeds}')),
            const SizedBox(width: 12),
            Expanded(
                child: _StatTile(
                    label: 'Dai TB',
                    value: '${stats.meanLengthPx.toStringAsFixed(1)} px')),
          ],
        ),
        const SizedBox(height: 18),
        const _BackendAnalysisCard(),
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

class _BackendAnalysisCard extends ConsumerStatefulWidget {
  const _BackendAnalysisCard();

  @override
  ConsumerState<_BackendAnalysisCard> createState() =>
      _BackendAnalysisCardState();
}

class _BackendAnalysisCardState extends ConsumerState<_BackendAnalysisCard> {
  final _picker = ImagePicker();
  final _api = GrainAnalysisApi();
  final _referencePixels = TextEditingController();
  final _referenceMm = TextEditingController();

  Uint8List? _selectedBytes;
  String _fileName = 'camera-frame.png';
  GrainAnalysisResult? _result;
  String? _error;
  String _previewMode = 'overlay';
  bool _busy = false;

  @override
  void dispose() {
    _referencePixels.dispose();
    _referenceMm.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      imageQuality: 94,
      maxWidth: 2600,
      maxHeight: 2600,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _selectedBytes = bytes;
      _fileName = file.name;
      _result = null;
      _error = null;
      _previewMode = 'overlay';
    });
  }

  Future<void> _analyze() async {
    final bytes = _selectedBytes;
    if (bytes == null) {
      setState(() => _error = 'Chon anh hoac chup anh truoc khi xu ly.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _api.analyzeImage(
        bytes: bytes,
        fileName: _fileName,
        referencePixels: double.tryParse(_referencePixels.text.trim()),
        referenceMm: double.tryParse(_referenceMm.text.trim()),
      );
      if (!mounted) return;
      setState(() => _result = result);
      ref.invalidate(grainRunsProvider);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareCsv() async {
    final csv = _result?.csv;
    if (csv == null || csv.isEmpty) return;
    final file = await _writeTempFile(
        '${_safeStem(_fileName)}_measurements.csv', utf8.encode(csv));
    await Share.shareXFiles([XFile(file.path)], text: 'Seed measurements CSV');
  }

  Future<void> _sharePng() async {
    final base64 = _result?.previewBase64('overlay');
    if (base64 == null || base64.isEmpty) return;
    final file = await _writeTempFile(
        '${_safeStem(_fileName)}_segmentation.png', base64Decode(base64));
    await Share.shareXFiles([XFile(file.path)], text: 'Seed segmentation PNG');
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final previewBase64 = result?.previewBase64(_previewMode) ?? '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Xu ly anh',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Chon anh'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Camera'),
                ),
                ElevatedButton.icon(
                  onPressed: _busy ? null : _analyze,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_motion_outlined),
                  label: Text(_busy ? 'Dang xu ly' : 'Chay pipeline'),
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
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _referencePixels,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Vat moc (px)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _referenceMm,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Vat moc (mm)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            ],
            if (result != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                      child: _ResultTile(
                          label: 'So hat', value: '${result.count}')),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ResultTile(
                      label: 'Dien tich TB',
                      value: result.meanAreaMm2 == null
                          ? '${result.meanAreaPx.toStringAsFixed(1)} px2'
                          : '${result.meanAreaMm2!.toStringAsFixed(3)} mm2',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _ResultTile(
                      label: 'Dai TB',
                      value: result.meanLengthMm == null
                          ? '${result.meanLengthPx.toStringAsFixed(1)} px'
                          : '${result.meanLengthMm!.toStringAsFixed(2)} mm',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ResultTile(
                      label: 'Rong TB',
                      value: result.meanWidthMm == null
                          ? '${result.meanWidthPx.toStringAsFixed(1)} px'
                          : '${result.meanWidthMm!.toStringAsFixed(2)} mm',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _previewChip(mode: 'overlay', label: 'Overlay'),
                  _previewChip(mode: 'labels', label: 'Labels'),
                  _previewChip(mode: 'mask', label: 'Mask'),
                  _previewChip(mode: 'seedMask', label: 'Seed'),
                  _previewChip(mode: 'kmeansMask', label: 'KMeans'),
                  _previewChip(mode: 'clusters', label: 'Clusters'),
                ],
              ),
              const SizedBox(height: 12),
              if (previewBase64.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(base64Decode(previewBase64)),
                ),
              const SizedBox(height: 12),
              _SegmentationFacts(result: result),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ElevatedButton.icon(
                    onPressed: _shareCsv,
                    icon: const Icon(Icons.table_view_outlined),
                    label: const Text('Export CSV'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _sharePng,
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Export PNG'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _previewChip({required String mode, required String label}) {
    return ChoiceChip(
      label: Text(label),
      selected: _previewMode == mode,
      onSelected: (_) => setState(() => _previewMode = mode),
    );
  }
}

class _SegmentationFacts extends StatelessWidget {
  final GrainAnalysisResult result;

  const _SegmentationFacts({required this.result});

  @override
  Widget build(BuildContext context) {
    final segmentation = result.segmentation;
    final calibration = result.calibration;
    return Column(
      children: [
        _FactRow(
            label: 'Watershed',
            value: segmentation['watershed_mode']?.toString() ?? '-'),
        _FactRow(
            label: 'Markers',
            value: segmentation['marker_count']?.toString() ?? '-'),
        _FactRow(
            label: 'Segments truoc loc',
            value:
                segmentation['segment_count_before_filter']?.toString() ?? '-'),
        _FactRow(
            label: 'Mask source',
            value: segmentation['mask_source']?.toString() ?? '-'),
        _FactRow(
          label: 'Ty le mm',
          value: calibration['enabled'] == true
              ? '${_asDouble(calibration['mm_per_pixel']).toStringAsFixed(5)} mm/px'
              : 'chua co',
        ),
      ],
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
            Text(label,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 8),
            Text(value,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  final String label;
  final String value;

  const _ResultTile({required this.label, required this.value});

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

class _FactRow extends StatelessWidget {
  final String label;
  final String value;

  const _FactRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(color: AppTheme.textSecondary))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

Future<File> _writeTempFile(String name, List<int> bytes) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name');
  return file.writeAsBytes(bytes, flush: true);
}

String _safeStem(String name) {
  final withoutExt = name.replaceFirst(RegExp(r'\.[^.]+$'), '');
  return withoutExt.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
}

String _friendlyError(Object error) {
  if (error is DioException) {
    final message = error.response?.data is Map
        ? (error.response?.data['message']?.toString())
        : null;
    if (message != null && message.isNotEmpty) return message;
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return 'Khong ket noi duoc backend hoac worker xu ly qua lau. Kiem tra BASE_URL, server va Python dependencies.';
    }
  }
  return 'Xu ly anh that bai. Kiem tra backend, MongoDB va Python worker.';
}

double _asDouble(dynamic value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
