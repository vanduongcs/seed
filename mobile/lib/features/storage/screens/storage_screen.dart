import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../grain/providers/grain_runs_provider.dart';
import '../../grain/services/grain_analysis_api.dart';

class StorageScreen extends ConsumerWidget {
  const StorageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runsState = ref.watch(grainRunsProvider);
    final isGuest = ref.watch(guestModeProvider).value ?? false;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(grainRunsProvider);
        await ref.read(grainRunsProvider.future);
      },
      child: runsState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _Header(isGuest: isGuest),
            const SizedBox(height: 18),
            Text(
              error.toString(),
              style: TextStyle(color: Colors.red.shade700),
            ),
          ],
        ),
        data: (runs) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _Header(isGuest: isGuest),
            const SizedBox(height: 18),
            if (runs.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    isGuest
                        ? 'Chưa có bản xử lý local. Chọn ảnh hoặc chụp ảnh để chạy phân tích offline.'
                        : 'Chưa có lịch sử. Hãy chạy phân tích ảnh để tạo bản đầu tiên.',
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
              )
            else
              ...runs.map((run) => _RunCard(
                    run: run,
                    onTap: () => _openRunDetail(context, run.id),
                  )),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final bool isGuest;

  const _Header({required this.isGuest});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Lịch sử xử lý',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          isGuest
              ? 'Các bản xử lý đang lưu trên điện thoại. Đăng nhập để đồng bộ vào tài khoản.'
              : 'Các lần xử lý đã đồng bộ với tài khoản của bạn trên server.',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
      ],
    );
  }
}

class _RunCard extends StatelessWidget {
  final GrainRun run;
  final VoidCallback onTap;

  const _RunCard({required this.run, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Center(
                  child: Text(
                    run.id.length >= 4
                        ? run.id.substring(run.id.length - 4).toUpperCase()
                        : 'RUN',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      run.sourceFileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(run.createdAt),
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${run.count} hạt - ĐLC: ${run.qcStdLengthPx == null ? '-' : _formatMeasure(run.qcStdLengthMm, 'mm', run.qcStdLengthPx!, 'px')} x ${run.qcStdWidthPx == null ? '-' : _formatMeasure(run.qcStdWidthMm, 'mm', run.qcStdWidthPx!, 'px')}',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${run.imageWidth} x ${run.imageHeight} px',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _openRunDetail(BuildContext context, String runId) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final detail = await GrainAnalysisApi().getRun(runId);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    await showDialog<void>(
      context: context,
      builder: (_) => _RunDetailDialog(detail: detail),
    );
  } catch (error) {
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Không tải được chi tiết: $error')),
    );
  }
}

class _RunDetailDialog extends StatefulWidget {
  final GrainRunDetail detail;

  const _RunDetailDialog({required this.detail});

  @override
  State<_RunDetailDialog> createState() => _RunDetailDialogState();
}

class _RunDetailDialogState extends State<_RunDetailDialog> {
  String _previewMode = 'overlay';
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final result = widget.detail.result;
    final run = widget.detail.run;
    final preview = result.previewWithFallback(_previewMode);
    final name = run['sourceFileName']?.toString() ?? 'seed-image';

    return AlertDialog(
      title: Text('Run ${_shortId(run['id']?.toString() ?? '')}'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip('original', 'Ảnh gốc'),
                  _chip('overlay', 'Đánh dấu'),
                  _chip('mask', 'Hình dạng'),
                  _chip('labels', 'Đánh số'),
                ],
              ),
              const SizedBox(height: 12),
              if (preview.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(base64Decode(preview)),
                ),
              const SizedBox(height: 12),
              _detailRow('Tổng số hạt đo được', '${result.count}'),
              _detailRow(
                  'ĐLC chiều dài (báo cáo)',
                  _formatMeasure(
                      result.qcStdLengthMm, 'mm', result.qcStdLengthPx, 'px')),
              _detailRow(
                  'ĐLC chiều rộng (báo cáo)',
                  _formatMeasure(
                      result.qcStdWidthMm, 'mm', result.qcStdWidthPx, 'px')),
              _detailRow(
                  'ĐLC diện tích (báo cáo)',
                  _formatMeasure(
                      result.qcStdAreaMm2, 'mm2', result.qcStdAreaPx, 'px2')),
              _detailRow('Vùng nghi nhiễu (QC)', '${result.qcSuspectCount}'),
              _detailRow(
                  'Tỷ lệ thước đo',
                  result.calibration['enabled'] == true
                      ? '${_asDouble(result.calibration['mm_per_pixel']).toStringAsFixed(5)} mm/px'
                      : 'Chưa thiết lập'),
              const Divider(),
              Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    _expanded
                        ? 'Ẩn thông số kỹ thuật'
                        : 'Hiển thị thông số kỹ thuật',
                    style: const TextStyle(
                        fontSize: 14, color: AppTheme.textSecondary),
                  ),
                  onExpansionChanged: (val) => setState(() => _expanded = val),
                  children: [
                    Container(
                      padding:
                          const EdgeInsets.only(left: 12, top: 4, bottom: 4),
                      decoration: const BoxDecoration(
                        border: Border(
                            left: BorderSide(color: AppTheme.border, width: 2)),
                      ),
                      child: Column(
                        children: [
                          _detailRow(
                            'Phương thức phân tích',
                            result.segmentation['execution'] ==
                                    'mobile_onnxruntime'
                                ? 'Phân đoạn instance YOLO ONNX trên thiết bị'
                                : 'Phân đoạn instance YOLO ONNX trên server',
                          ),
                          if (_asDouble(result.segmentation['confidence']) > 0)
                            _detailRow('Độ tin cậy nhận dạng',
                                '${(_asDouble(result.segmentation['confidence']) * 100).toStringAsFixed(0)}%'),
                          if (_asDouble(result.segmentation['iou']) > 0)
                            _detailRow('Độ khớp mặt nạ (IoU)',
                                '${(_asDouble(result.segmentation['iou']) * 100).toStringAsFixed(0)}%'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Đóng'),
        ),
        TextButton.icon(
          onPressed:
              result.csv.isEmpty ? null : () => _shareCsv(name, result.csv),
          icon: const Icon(Icons.table_view_outlined),
          label: const Text('Xuất CSV'),
        ),
        TextButton.icon(
          onPressed: _segmentationPng(result).isEmpty
              ? null
              : () => _sharePng(name, _segmentationPng(result)),
          icon: const Icon(Icons.image_outlined),
          label: const Text('Xuất ảnh kết quả'),
        ),
      ],
    );
  }

  Widget _chip(String mode, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _previewMode == mode,
      onSelected: (_) => setState(() => _previewMode = mode),
    );
  }
}

Widget _detailRow(String label, String value) {
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

Future<void> _shareCsv(String sourceName, String csv) async {
  final file = await _writeTempFile(
      '${_safeStem(sourceName)}_measurements.csv', utf8.encode(csv));
  await Share.shareXFiles([XFile(file.path)], text: 'Seed measurements CSV');
}

String _segmentationPng(GrainAnalysisResult result) {
  final segment = result.previewBase64('samMask');
  if (segment.isNotEmpty) return segment;
  final labels = result.previewBase64('labels');
  if (labels.isNotEmpty) return labels;
  return result.previewBase64('overlay');
}

Future<void> _sharePng(String sourceName, String base64) async {
  final file = await _writeTempFile(
      '${_safeStem(sourceName)}_segmentation.png', base64Decode(base64));
  await Share.shareXFiles([XFile(file.path)], text: 'Seed segmentation PNG');
}

Future<File> _writeTempFile(String name, List<int> bytes) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name');
  return file.writeAsBytes(bytes, flush: true);
}

String _shortId(String id) =>
    id.length >= 8 ? id.substring(id.length - 8).toUpperCase() : id;

String _safeStem(String name) {
  final withoutExt = name.replaceFirst(RegExp(r'\.[^.]+$'), '');
  return withoutExt.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
}

String _formatMeasure(
    double? primary, String primaryUnit, double fallback, String fallbackUnit) {
  if (primary != null) {
    return '${primary.toStringAsFixed(primaryUnit == 'mm2' ? 3 : 2)} $primaryUnit';
  }
  return '${fallback.toStringAsFixed(1)} $fallbackUnit';
}

String _formatDate(DateTime? value) {
  if (value == null) return '-';
  return '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/'
      '${value.year} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

double _asDouble(dynamic value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
