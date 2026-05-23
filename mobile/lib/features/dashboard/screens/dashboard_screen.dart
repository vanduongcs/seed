import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../grain/providers/grain_runs_provider.dart';
import '../../grain/services/grain_analysis_api.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  GrainAnalysisResult? _sessionResult;

  @override
  Widget build(BuildContext context) {
    final runsState = ref.watch(grainRunsProvider);

    return runsState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _DashboardContent(
        historyError: error.toString(),
        sessionResult: _sessionResult,
        onSessionResultChanged: (result) =>
            setState(() => _sessionResult = result),
      ),
      data: (_) => _DashboardContent(
        sessionResult: _sessionResult,
        onSessionResultChanged: (result) =>
            setState(() => _sessionResult = result),
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  final String? historyError;
  final GrainAnalysisResult? sessionResult;
  final ValueChanged<GrainAnalysisResult?> onSessionResultChanged;

  const _DashboardContent({
    this.historyError,
    required this.sessionResult,
    required this.onSessionResultChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Phân tích hạt',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
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
                    label: 'Số hạt đo được',
                    value: _formatCountStat(sessionResult?.count))),
            const SizedBox(width: 12),
            Expanded(
                child: _StatTile(
                    label: 'Chiều dài trung bình',
                    value: _formatMeasureStat(
                        sessionResult?.meanLengthMm,
                        'mm',
                        sessionResult?.meanLengthPx,
                        'px'))),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: _StatTile(
                    label: 'Chiều rộng trung bình',
                    value: _formatMeasureStat(
                        sessionResult?.meanWidthMm,
                        'mm',
                        sessionResult?.meanWidthPx,
                        'px'))),
            const SizedBox(width: 12),
            Expanded(
                child: _StatTile(
                    label: 'Diện tích trung bình',
                    value: _formatMeasureStat(
                        sessionResult?.meanAreaMm2,
                        'mm2',
                        sessionResult?.meanAreaPx,
                        'px2'))),
          ],
        ),
        const SizedBox(height: 18),
        _BackendAnalysisCard(onResultChanged: onSessionResultChanged),
      ],
    );
  }
}

String _formatMeasureStat(double? primary, String primaryUnit, double? fallback, String fallbackUnit) {
  if (primary != null && primary > 0) {
    return '${primary.toStringAsFixed(primaryUnit == 'mm2' ? 3 : 2)} $primaryUnit';
  }
  if (fallback != null) {
    return '${fallback.toStringAsFixed(1)} $fallbackUnit';
  }
  return '_';
}

String _formatCountStat(int? value) => value == null ? '_' : '$value';

class _BackendAnalysisCard extends ConsumerStatefulWidget {
  final ValueChanged<GrainAnalysisResult?> onResultChanged;

  const _BackendAnalysisCard({required this.onResultChanged});

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
  Size? _selectedImageSize;
  Offset? _referenceStart;
  Offset? _referenceEnd;
  String _fileName = 'camera-frame.png';
  GrainAnalysisResult? _result;
  String? _error;
  String _previewMode = 'samMask';
  bool _busy = false;
  double _progress = 0;
  String _progressPhase = '';
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onResultChanged(null);
    });
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _referencePixels.dispose();
    _referenceMm.dispose();
    super.dispose();
  }

  void _setProgress(double value, String phase) {
    setState(() {
      _progress = value.clamp(0, 100);
      _progressPhase = phase;
    });
  }

  void _startProgressDrift() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (!mounted) return;
      setState(() {
        if (_progress < 90) _progress = (_progress + 2).clamp(0, 90);
      });
    });
  }

  void _stopProgress() {
    _progressTimer?.cancel();
    _progressTimer = null;
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
    final decoded = img.decodeImage(bytes);
    setState(() {
      _selectedBytes = bytes;
      _selectedImageSize = decoded == null
          ? null
          : Size(decoded.width.toDouble(), decoded.height.toDouble());
      _referenceStart = null;
      _referenceEnd = null;
      _referencePixels.clear();
      _fileName = file.name;
      _result = null;
      _error = null;
      _previewMode = 'samMask';
    });
  }

  Future<void> _analyze() async {
    final bytes = _selectedBytes;
    if (bytes == null) {
      setState(() => _error = 'Chọn ảnh hoặc chụp ảnh trước khi xử lý.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    _setProgress(5, 'Chuẩn bị ảnh');
    try {
      _setProgress(
        20,
        'Xác thực phiên',
      );
      _setProgress(
        50,
        'Phân tích ảnh bằng YOLO',
      );
      _startProgressDrift();
      final referencePixels = double.tryParse(_referencePixels.text.trim());
      final referenceMm = double.tryParse(_referenceMm.text.trim());
      final result = await _api.analyzeImage(
        bytes: bytes,
        fileName: _fileName,
        referencePixels: referencePixels,
        referenceMm: referenceMm,
        referenceX1: _referenceStart?.dx,
        referenceY1: _referenceStart?.dy,
        referenceX2: _referenceEnd?.dx,
        referenceY2: _referenceEnd?.dy,
      );
      _stopProgress();
      _setProgress(96, 'Lưu kết quả');
      if (!mounted) return;
      setState(() => _result = result);
      widget.onResultChanged(result);
      _setProgress(100, 'Hoàn tất');
      ref.invalidate(grainRunsProvider);
    } catch (error) {
      _stopProgress();
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    } finally {
      _stopProgress();
      if (mounted) {
        setState(() => _busy = false);
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!mounted) return;
          setState(() {
            _progress = 0;
            _progressPhase = '';
          });
        });
      }
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
    final base64 = _result?.previewBase64('samMask').isNotEmpty == true
        ? _result?.previewBase64('samMask')
        : _result?.previewBase64('overlay');
    if (base64 == null || base64.isEmpty) return;
    final file = await _writeTempFile(
        '${_safeStem(_fileName)}_segmentation.png', base64Decode(base64));
    await Share.shareXFiles([XFile(file.path)], text: 'Seed segmentation PNG');
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final previewBase64 = result?.previewWithFallback(_previewMode) ?? '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Xử lý ảnh',
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
                  label: const Text('Chọn ảnh'),
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
                  label: Text(_busy ? 'Đang xử lý' : 'Xử lý'),
                ),
              ],
            ),
            if (_selectedBytes != null) ...[
              const SizedBox(height: 14),
              _ReferenceImageSelector(
                bytes: _selectedBytes!,
                imageSize: _selectedImageSize,
                start: _referenceStart,
                end: _referenceEnd,
                enabled: !_busy,
                onChanged: (start, end) {
                  setState(() {
                    _referenceStart = start;
                    _referenceEnd = end;
                    _referencePixels.text =
                        (end - start).distance.toStringAsFixed(1);
                  });
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _referencePixels,
                      readOnly: true,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
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
                      controller: _referenceMm,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Vật mốc (mm)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () {
                          setState(() {
                            _referenceStart = null;
                            _referenceEnd = null;
                            _referencePixels.clear();
                          });
                        },
                  icon: const Icon(Icons.clear),
                  label: const Text('Xóa đường vật mốc'),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            ],
            if (_busy) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _progressPhase.isEmpty ? 'Đang xử lý' : _progressPhase,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Text(
                    '${_progress.round()}%',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: (_progress / 100).clamp(0, 1)),
            ],
            if (result != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                      child: _ResultTile(
                          label: 'Tổng số hạt đo được', value: '${result.count}')),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ResultTile(
                      label: 'Diện tích trung bình',
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
                      label: 'Chiều dài trung bình',
                      value: result.meanLengthMm == null
                          ? '${result.meanLengthPx.toStringAsFixed(1)} px'
                          : '${result.meanLengthMm!.toStringAsFixed(2)} mm',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ResultTile(
                      label: 'Chiều rộng trung bình',
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
                  _previewChip(mode: 'samMask', label: 'Hình dạng'),
                  _previewChip(mode: 'labels', label: 'Đánh số'),
                  _previewChip(mode: 'overlay', label: 'Đánh dấu'),
                  _previewChip(mode: 'mask', label: 'Mặt nạ'),
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

class _SegmentationFacts extends ConsumerStatefulWidget {
  final GrainAnalysisResult result;

  const _SegmentationFacts({required this.result});

  @override
  ConsumerState<_SegmentationFacts> createState() => _SegmentationFactsState();
}

class _SegmentationFactsState extends ConsumerState<_SegmentationFacts> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final segmentation = widget.result.segmentation;
    final calibration = widget.result.calibration;
    final confidence = _asDouble(segmentation['confidence']);
    final iou = _asDouble(segmentation['iou']);

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(
          _expanded ? 'Ẩn thông số kỹ thuật' : 'Hiển thị thông số kỹ thuật',
          style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
        ),
        onExpansionChanged: (val) => setState(() => _expanded = val),
        children: [
          Container(
            padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: AppTheme.border, width: 2)),
            ),
            child: Column(
              children: [
                const _FactRow(
                    label: 'Phương thức phân tích',
                    value: 'YOLO segmentation'),
                if (confidence > 0)
                  _FactRow(
                      label: 'Độ tin cậy nhận dạng',
                      value: '${(confidence * 100).toStringAsFixed(0)}%'),
                if (iou > 0)
                  _FactRow(
                      label: 'Độ khớp mặt nạ (IoU)',
                      value: '${(iou * 100).toStringAsFixed(0)}%'),
                _FactRow(
                    label: 'Quét phân mảnh (Tiled)',
                    value: segmentation['tiled_inference'] == true
                        ? 'Đang bật'
                        : 'Đang tắt'),
                _FactRow(
                  label: 'Tỷ lệ thước đo',
                  value: calibration['enabled'] == true
                      ? '${_asDouble(calibration['mm_per_pixel']).toStringAsFixed(5)} mm/px'
                      : 'Chưa thiết lập',
                ),
                _FactRow(
                  label: 'Vật mốc đã loại khỏi thống kê',
                  value:
                      '${calibration['excluded_reference_object_count'] ?? 0}',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferenceImageSelector extends StatelessWidget {
  final Uint8List bytes;
  final Size? imageSize;
  final Offset? start;
  final Offset? end;
  final bool enabled;
  final void Function(Offset start, Offset end) onChanged;

  const _ReferenceImageSelector({
    required this.bytes,
    required this.imageSize,
    required this.start,
    required this.end,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final sourceSize = imageSize;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 240,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final canvasSize = Size(constraints.maxWidth, 240);
            final fittedRect = sourceSize == null
                ? Offset.zero & canvasSize
                : _containedRect(canvasSize, sourceSize);

            Offset? imagePoint(Offset localPoint) {
              if (sourceSize == null || !fittedRect.contains(localPoint)) {
                return null;
              }
              return Offset(
                (localPoint.dx - fittedRect.left) /
                    fittedRect.width *
                    sourceSize.width,
                (localPoint.dy - fittedRect.top) /
                    fittedRect.height *
                    sourceSize.height,
              );
            }

            return GestureDetector(
              onPanStart: enabled
                  ? (details) {
                      final point = imagePoint(details.localPosition);
                      if (point != null) onChanged(point, point);
                    }
                  : null,
              onPanUpdate: enabled
                  ? (details) {
                      if (start == null) return;
                      final point = imagePoint(details.localPosition);
                      if (point != null) onChanged(start!, point);
                    }
                  : null,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: const Color(0xFFF8FAF7),
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  ),
                  CustomPaint(
                    painter: _ReferenceLinePainter(
                      fittedRect: fittedRect,
                      imageSize: sourceSize,
                      start: start,
                      end: end,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

Rect _containedRect(Size target, Size source) {
  final scale = math.min(target.width / source.width, target.height / source.height);
  final fitted = Size(source.width * scale, source.height * scale);
  return Rect.fromLTWH(
    (target.width - fitted.width) / 2,
    (target.height - fitted.height) / 2,
    fitted.width,
    fitted.height,
  );
}

class _ReferenceLinePainter extends CustomPainter {
  final Rect fittedRect;
  final Size? imageSize;
  final Offset? start;
  final Offset? end;

  const _ReferenceLinePainter({
    required this.fittedRect,
    required this.imageSize,
    required this.start,
    required this.end,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final sourceSize = imageSize;
    if (sourceSize == null || start == null || end == null) return;
    Offset displayPoint(Offset point) => Offset(
          fittedRect.left + point.dx / sourceSize.width * fittedRect.width,
          fittedRect.top + point.dy / sourceSize.height * fittedRect.height,
        );
    final a = displayPoint(start!);
    final b = displayPoint(end!);
    final paint = Paint()
      ..color = const Color(0xFF2563EB)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(a, b, paint);
    canvas.drawCircle(a, 5, paint);
    canvas.drawCircle(b, 5, paint);
  }

  @override
  bool shouldRepaint(covariant _ReferenceLinePainter oldDelegate) =>
      fittedRect != oldDelegate.fittedRect ||
      imageSize != oldDelegate.imageSize ||
      start != oldDelegate.start ||
      end != oldDelegate.end;
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
      return 'Không kết nối được backend hoặc worker xử lý quá lâu. Kiểm tra server, Wi-Fi và Python dependencies.';
    }
  }
  return 'Xử lý ảnh thất bại. Kiểm tra backend, MongoDB và Python worker.';
}

double _asDouble(dynamic value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
