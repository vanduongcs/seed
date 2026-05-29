import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontalPadding = screenWidth < 360 ? 12.0 : 20.0;

    return ListView(
      padding: EdgeInsets.all(horizontalPadding),
      children: [
        if (historyError != null) ...[
          Text(historyError!, style: TextStyle(color: Colors.red.shade700)),
          const SizedBox(height: 14),
        ],
        _BackendAnalysisCard(onResultChanged: onSessionResultChanged),
        if (sessionResult case final result?) ...[
          const SizedBox(height: 18),
          _StatTile(label: 'Tổng số hạt', value: '${result.count}'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: 'Số hạt chắc chắn',
                  value: '${result.qcInlierCount}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  label: 'Số hạt nghi ngờ',
                  value: '${result.qcSuspectCount}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Giá trị trung bình',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: 'Chiều dài trung bình',
                  value: _formatMeasureStat(
                    result.meanLengthMm,
                    'mm',
                    result.meanLengthPx,
                    'px',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  label: 'Chiều rộng trung bình',
                  value: _formatMeasureStat(
                    result.meanWidthMm,
                    'mm',
                    result.meanWidthPx,
                    'px',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _StatTile(
            label: 'Diện tích trung bình',
            value: _formatMeasureStat(
              result.meanAreaMm2,
              'mm2',
              result.meanAreaPx,
              'px2',
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Độ lệch chuẩn',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: 'ĐLC chiều dài',
                  value: _formatMeasureStat(
                    result.qcStdLengthMm,
                    'mm',
                    result.qcStdLengthPx,
                    'px',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  label: 'ĐLC chiều rộng',
                  value: _formatMeasureStat(
                    result.qcStdWidthMm,
                    'mm',
                    result.qcStdWidthPx,
                    'px',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _StatTile(
            label: 'ĐLC diện tích',
            value: _formatMeasureStat(
              result.qcStdAreaMm2,
              'mm2',
              result.qcStdAreaPx,
              'px2',
            ),
          ),
        ],
      ],
    );
  }
}

String _formatMeasureStat(double? primary, String primaryUnit, double? fallback,
    String fallbackUnit) {
  if (primary != null && primary > 0) {
    return '${primary.toStringAsFixed(primaryUnit == 'mm2' ? 3 : 2)} $primaryUnit';
  }
  if (fallback != null) {
    return '${fallback.toStringAsFixed(1)} $fallbackUnit';
  }
  return '_';
}

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
  String _previewMode = 'overlay';
  bool _qcEditMode = false;
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
        if (_progress < 82) _progress = (_progress + 2).clamp(0, 82);
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
      _previewMode = 'overlay';
      _qcEditMode = false;
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
      _qcEditMode = false;
    });
    _setProgress(5, 'Chuẩn bị ảnh');
    try {
      _setProgress(
        20,
        'Khởi chạy mô hình cục bộ',
      );
      _setProgress(
        50,
        'Phân tích trực tiếp trên thiết bị',
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
        onProgress: (value, phase) {
          if (mounted) _setProgress(value, phase);
        },
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
    await Share.shareXFiles([XFile(file.path)],
        text: 'SeedVision measurements CSV');
  }

  Future<void> _sharePng() async {
    final base64 = _result?.previewBase64('samMask').isNotEmpty == true
        ? _result?.previewBase64('samMask')
        : _result?.previewBase64('overlay');
    if (base64 == null || base64.isEmpty) return;
    final file = await _writeTempFile(
        '${_safeStem(_fileName)}_segmentation.png', base64Decode(base64));
    await Share.shareXFiles([XFile(file.path)],
        text: 'SeedVision segmentation PNG');
  }

  void _toggleMeasurementQc(int measurementId) {
    final current = _result;
    if (current == null) return;
    final next = current.withToggledQc(measurementId);
    setState(() => _result = next);
    widget.onResultChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final previewBase64 = result?.previewWithFallback(_previewMode) ?? '';
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardPadding = screenWidth < 360 ? 12.0 : 18.0;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(cardPadding),
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
              ],
            ),
            const SizedBox(height: 14),
            _ReferenceImageSelector(
              bytes: _selectedBytes,
              imageSize: _selectedImageSize,
              start: _referenceStart,
              end: _referenceEnd,
              enabled: !_busy && _selectedBytes != null,
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
                onPressed: _busy || _referenceStart == null
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
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _busy || _selectedBytes == null ? null : _analyze,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_motion_outlined),
                label: Text(_busy ? 'Đang xử lý' : 'Xử lý'),
              ),
            ),
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
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4E5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFF2C078)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.fact_check_outlined,
                          size: 20,
                          color: Color(0xFF9A3412),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Kiểm tra chất lượng hạt (QC)',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF7C2D12),
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Hạt màu đỏ là vùng hệ thống nghi có lỗi tách mask hoặc kích thước bất thường. Đây là gợi ý để người dùng kiểm tra lại, không phải kết luận loại hạt.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'QC là gì?',
                          icon: const Icon(Icons.help_outline, size: 20),
                          color: const Color(0xFF9A3412),
                          visualDensity: VisualDensity.compact,
                          onPressed: _showQcHelp,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _QcFactCard(
                            label: 'Hạt đang nghi ngờ',
                            value: '${result.qcSuspectCount}',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _QcFactCard(
                            label: 'ID nghi ngờ',
                            value: result.qcSuspectIdsLabel.isEmpty
                                ? '-'
                                : result.qcSuspectIdsLabel,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _previewChip(mode: 'overlay', label: 'Đánh dấu'),
                  _previewChip(mode: 'mask', label: 'Hình dạng'),
                  _previewChip(mode: 'labels', label: 'Đánh số'),
                  _qcEditChip(),
                  _qcHelpChip(),
                ],
              ),
              if (_qcEditMode) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF93C5FD)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.touch_app_outlined,
                        size: 18,
                        color: Color(0xFF2563EB),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Đang chỉnh hạt nghi ngờ: chạm trực tiếp vào hạt để đổi giữa nghi ngờ và hợp lệ. Thống kê và CSV sẽ cập nhật theo lựa chọn này.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF1E3A8A),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (previewBase64.isNotEmpty)
                _QcEditablePreview(
                  result: result,
                  previewBytes: base64Decode(previewBase64),
                  editMode: _qcEditMode,
                  onToggle: _toggleMeasurementQc,
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

  Widget _qcEditChip() {
    final active = _qcEditMode;
    return FilterChip(
      avatar: Icon(
        active ? Icons.check_circle_outline : Icons.edit_outlined,
        size: 18,
        color: active ? const Color(0xFF9A3412) : AppTheme.primary,
      ),
      label: Text(active ? 'Xong chỉnh hạt' : 'Chỉnh hạt nghi ngờ'),
      selected: active,
      onSelected: (_) => setState(() => _qcEditMode = !_qcEditMode),
      selectedColor: const Color(0xFFFFEDD5),
      checkmarkColor: const Color(0xFF9A3412),
      side: BorderSide(
        color: active ? const Color(0xFFF97316) : AppTheme.border,
        width: active ? 1.4 : 1,
      ),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w700,
        color: active ? const Color(0xFF9A3412) : AppTheme.textPrimary,
      ),
    );
  }

  Widget _qcHelpChip() {
    return ActionChip(
      avatar: const Icon(Icons.help_outline, size: 18),
      label: const Text('QC là gì?'),
      onPressed: _showQcHelp,
      side: const BorderSide(color: AppTheme.border),
      labelStyle: const TextStyle(fontWeight: FontWeight.w700),
    );
  }

  void _showQcHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: AppTheme.primary),
            SizedBox(width: 8),
            Expanded(child: Text('QC là gì?')),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'QC là bước kiểm tra chất lượng kết quả sau khi AI tách từng hạt. Nó không phải một loại hạt mới.',
            ),
            SizedBox(height: 10),
            Text(
              'Mask xanh là hạt đang được tính là hợp lệ. Mask đỏ là hạt hệ thống nghi có lỗi tách dính, tách thiếu hoặc kích thước lệch bất thường.',
            ),
            SizedBox(height: 10),
            Text(
              'Nếu nhìn ảnh thấy hạt đỏ vẫn đúng, bật "Chỉnh hạt nghi ngờ" rồi chạm vào hạt đó để chuyển về hợp lệ. Nếu hạt xanh bị tách sai, chạm vào hạt đó để đánh dấu nghi ngờ.',
            ),
            SizedBox(height: 10),
            Text(
              'Sau khi chỉnh, số hạt nghi ngờ, độ lệch chuẩn báo cáo và file CSV sẽ được tính lại cho kết quả hiện tại.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Đã hiểu'),
          ),
        ],
      ),
    );
  }
}

class _QcEditablePreview extends StatelessWidget {
  final GrainAnalysisResult result;
  final Uint8List previewBytes;
  final bool editMode;
  final ValueChanged<int> onToggle;

  const _QcEditablePreview({
    required this.result,
    required this.previewBytes,
    required this.editMode,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final imageWidth = _asDouble(result.image['width']);
    final imageHeight = _asDouble(result.image['height']);
    if (imageWidth <= 0 || imageHeight <= 0) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(previewBytes),
      );
    }

    final boxes = result.measurements
        .where((measurement) =>
            (_asDouble(measurement['length_px']) > 0 &&
                _asDouble(measurement['width_px']) > 0) ||
            (_asDouble(measurement['bbox_w']) > 0 &&
                _asDouble(measurement['bbox_h']) > 0))
        .toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          final displayWidth = math.max(1.0, maxWidth);
          final displayHeight = displayWidth * imageHeight / imageWidth;
          final scaleX = displayWidth / imageWidth;
          final scaleY = displayHeight / imageHeight;

          return SizedBox(
            width: displayWidth,
            height: displayHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  previewBytes,
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                ),
                for (final measurement in boxes)
                  _QcMeasurementBox(
                    measurement: measurement,
                    editMode: editMode,
                    scaleX: scaleX,
                    scaleY: scaleY,
                    onToggle: onToggle,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _QcMeasurementBox extends StatelessWidget {
  final Map<String, dynamic> measurement;
  final bool editMode;
  final double scaleX;
  final double scaleY;
  final ValueChanged<int> onToggle;

  const _QcMeasurementBox({
    required this.measurement,
    required this.editMode,
    required this.scaleX,
    required this.scaleY,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final id = _asInt(measurement['id']);
    if (!editMode) return const SizedBox.shrink();

    final centerX = (_asDouble(measurement['centroid_x']) > 0
            ? _asDouble(measurement['centroid_x'])
            : _asDouble(measurement['bbox_x']) +
                _asDouble(measurement['bbox_w']) / 2) *
        scaleX;
    final centerY = (_asDouble(measurement['centroid_y']) > 0
            ? _asDouble(measurement['centroid_y'])
            : _asDouble(measurement['bbox_y']) +
                _asDouble(measurement['bbox_h']) / 2) *
        scaleY;
    final scale = (scaleX + scaleY) / 2;
    final visibleWidth = math.max(
      8.0,
      math.max(_asDouble(measurement['length_px']),
              _asDouble(measurement['bbox_w'])) *
          scale,
    );
    final visibleHeight = math.max(
      4.0,
      math.max(
            _asDouble(measurement['width_px']),
            math.min(
              _asDouble(measurement['bbox_w']),
              _asDouble(measurement['bbox_h']),
            ),
          ) *
          scale,
    );
    final hitWidth = math.max(visibleWidth, 26.0);
    final hitHeight = math.max(visibleHeight, 22.0);
    final angleRadians = _asDouble(measurement['angle_deg']) * math.pi / 180;

    return Positioned(
      left: centerX - hitWidth / 2,
      top: centerY - hitHeight / 2,
      width: hitWidth,
      height: hitHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: editMode ? () => onToggle(id) : null,
        child: Center(
          child: Transform.rotate(
            angle: angleRadians,
            child: Container(
              width: visibleWidth,
              height: visibleHeight,
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ),
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
              border:
                  Border(left: BorderSide(color: AppTheme.border, width: 2)),
            ),
            child: Column(
              children: [
                _FactRow(
                    label: 'Phương thức phân tích',
                    value: segmentation['execution'] == 'mobile_onnxruntime'
                        ? 'Phân đoạn instance YOLO ONNX trên thiết bị'
                        : 'Phân đoạn instance YOLO ONNX trên server'),
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
                _FactRow(
                  label: 'ĐLC dài thô / sau kiểm tra',
                  value:
                      '${_formatMeasureStat(widget.result.rawStdLengthMm, 'mm', widget.result.rawStdLengthPx, 'px')} / '
                      '${_formatMeasureStat(widget.result.qcStdLengthMm, 'mm', widget.result.qcStdLengthPx, 'px')}',
                ),
                _FactRow(
                  label: 'ĐLC rộng thô / sau kiểm tra',
                  value:
                      '${_formatMeasureStat(widget.result.rawStdWidthMm, 'mm', widget.result.rawStdWidthPx, 'px')} / '
                      '${_formatMeasureStat(widget.result.qcStdWidthMm, 'mm', widget.result.qcStdWidthPx, 'px')}',
                ),
                _FactRow(
                  label: 'Hạt nghi ngờ sau kiểm tra',
                  value: '${widget.result.qcSuspectCount}',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferenceImageSelector extends StatefulWidget {
  final Uint8List? bytes;
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
  State<_ReferenceImageSelector> createState() =>
      _ReferenceImageSelectorState();
}

class _ReferenceImageSelectorState extends State<_ReferenceImageSelector> {
  static const _handleHitRadius = 36.0;

  String? _dragTarget;
  String _selectedHandle = 'end';
  Offset? _fingerPosition;
  Offset? _activeHandlePosition;
  Offset? _activeImagePoint;
  ui.Image? _previewImage;

  @override
  void initState() {
    super.initState();
    _decodePreviewImage();
  }

  @override
  void didUpdateWidget(covariant _ReferenceImageSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) {
      _decodePreviewImage();
    }
  }

  Future<void> _decodePreviewImage() async {
    final bytes = widget.bytes;
    if (bytes == null) {
      final previous = _previewImage;
      if (mounted) setState(() => _previewImage = null);
      previous?.dispose();
      return;
    }
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    if (!mounted) {
      frame.image.dispose();
      return;
    }
    final previous = _previewImage;
    setState(() => _previewImage = frame.image);
    previous?.dispose();
  }

  @override
  void dispose() {
    _previewImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sourceSize = widget.imageSize;
    final hasLine = widget.start != null && widget.end != null;

    void nudgeSelected(Offset delta) {
      if (!widget.enabled || sourceSize == null || !hasLine) return;
      Offset clamp(Offset point) => Offset(
            point.dx.clamp(0, sourceSize.width - 1).toDouble(),
            point.dy.clamp(0, sourceSize.height - 1).toDouble(),
          );
      if (_selectedHandle == 'start') {
        widget.onChanged(clamp(widget.start! + delta), widget.end!);
      } else {
        widget.onChanged(widget.start!, clamp(widget.end! + delta));
      }
    }

    void showGuideModal() {
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (context) => const _CalibrationGuideDialog(),
      );
    }

    Widget buildFixedMagnifierBox() {
      final isMagnifierActive = _activeHandlePosition != null &&
          _activeImagePoint != null &&
          sourceSize != null &&
          _previewImage != null;

      return Container(
        width: 90,
        height: 90,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isMagnifierActive ? AppTheme.primary : AppTheme.border,
            width: isMagnifierActive ? 1.5 : 1,
          ),
          boxShadow: isMagnifierActive
              ? [
                  BoxShadow(
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                    color: Colors.black.withValues(alpha: 0.08),
                  )
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: isMagnifierActive
              ? _ReferenceMagnifier(
                  sourceImage: _previewImage!,
                  imageSize: sourceSize,
                  start: widget.start,
                  end: widget.end,
                  selectedHandle: _selectedHandle,
                  targetImagePoint: _activeImagePoint!,
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.zoom_in,
                      size: 24,
                      color: AppTheme.textSecondary.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Kính lúp',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.textSecondary.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Hướng dẫn',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(
                          Icons.help_outline,
                          color: AppTheme.primary,
                          size: 20,
                        ),
                        onPressed: showGuideModal,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Xem hướng dẫn',
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    hasLine
                        ? 'Kéo chốt A hoặc chốt B để khớp chính xác hai mép vật mốc.'
                        : 'Nhấn vào vùng bất kỳ trên ảnh để khởi tạo đoạn thẳng tham chiếu kích thước.',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            buildFixedMagnifierBox(),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, outerConstraints) {
            final availableWidth = outerConstraints.maxWidth.isFinite
                ? outerConstraints.maxWidth
                : MediaQuery.sizeOf(context).width;
            final previewHeight = availableWidth < 340
                ? 220.0
                : (availableWidth > 620 ? 360.0 : 280.0);

            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: previewHeight,
                width: double.infinity,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final canvasSize =
                        Size(constraints.maxWidth, previewHeight);
                    final fittedRect = sourceSize == null
                        ? Offset.zero & canvasSize
                        : _containedRect(canvasSize, sourceSize);

                    Offset displayPoint(Offset imagePoint) => Offset(
                          fittedRect.left +
                              imagePoint.dx /
                                  sourceSize!.width *
                                  fittedRect.width,
                          fittedRect.top +
                              imagePoint.dy /
                                  sourceSize.height *
                                  fittedRect.height,
                        );

                    Offset? imagePoint(Offset localPoint) {
                      if (sourceSize == null ||
                          !fittedRect.contains(localPoint)) {
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

                    Offset? dragImagePoint(Offset fingerPoint) {
                      final target = Offset(
                        fingerPoint.dx
                            .clamp(fittedRect.left, fittedRect.right)
                            .toDouble(),
                        fingerPoint.dy
                            .clamp(fittedRect.top, fittedRect.bottom)
                            .toDouble(),
                      );
                      final point = imagePoint(target);
                      if (point == null) return null;
                      setState(() {
                        _fingerPosition = fingerPoint;
                        _activeHandlePosition = target;
                        _activeImagePoint = point;
                      });
                      return point;
                    }

                    return GestureDetector(
                      onTapUp: widget.enabled && sourceSize != null
                          ? (details) {
                              if (widget.start != null && widget.end != null) {
                                final distStart = (details.localPosition -
                                        displayPoint(widget.start!))
                                    .distance;
                                final distEnd = (details.localPosition -
                                        displayPoint(widget.end!))
                                    .distance;
                                if (math.min(distStart, distEnd) <=
                                    _handleHitRadius) {
                                  setState(() {
                                    _selectedHandle =
                                        distStart <= distEnd ? 'start' : 'end';
                                  });
                                  return;
                                }
                              }
                              final point = imagePoint(details.localPosition);
                              if (point == null) return;

                              final halfLength =
                                  math.min(56.0, fittedRect.width * 0.2);
                              final left = Offset(
                                (details.localPosition.dx - halfLength)
                                    .clamp(fittedRect.left, fittedRect.right)
                                    .toDouble(),
                                details.localPosition.dy,
                              );
                              final right = Offset(
                                (details.localPosition.dx + halfLength)
                                    .clamp(fittedRect.left, fittedRect.right)
                                    .toDouble(),
                                details.localPosition.dy,
                              );
                              final start = imagePoint(left);
                              final end = imagePoint(right);
                              if (start != null && end != null) {
                                setState(() => _selectedHandle = 'end');
                                widget.onChanged(start, end);
                              }
                            }
                          : null,
                      onPanStart: widget.enabled
                          ? (details) {
                              final local = details.localPosition;
                              if (widget.start != null && widget.end != null) {
                                final startCanvas = displayPoint(widget.start!);
                                final endCanvas = displayPoint(widget.end!);

                                final distStart =
                                    (local - startCanvas).distance;
                                final distEnd = (local - endCanvas).distance;

                                if (distStart < _handleHitRadius &&
                                    distStart < distEnd) {
                                  setState(() => _selectedHandle = 'start');
                                  _dragTarget = _selectedHandle;
                                } else if (distEnd < _handleHitRadius) {
                                  setState(() => _selectedHandle = 'end');
                                  _dragTarget = _selectedHandle;
                                } else {
                                  _dragTarget = null;
                                }
                              } else {
                                final point = imagePoint(local);
                                if (point == null) return;
                                _dragTarget = 'new';
                                setState(() => _selectedHandle = 'end');
                                widget.onChanged(point, point);
                              }
                            }
                          : null,
                      onPanUpdate: widget.enabled
                          ? (details) {
                              final point =
                                  _dragTarget == 'start' || _dragTarget == 'end'
                                      ? dragImagePoint(details.localPosition)
                                      : imagePoint(details.localPosition);
                              if (point == null) return;

                              if (_dragTarget == 'start') {
                                if (widget.end != null) {
                                  widget.onChanged(point, widget.end!);
                                }
                              } else if (_dragTarget == 'end') {
                                if (widget.start != null) {
                                  widget.onChanged(widget.start!, point);
                                }
                              } else if (_dragTarget == 'new') {
                                if (widget.start != null) {
                                  widget.onChanged(widget.start!, point);
                                }
                              }
                            }
                          : null,
                      onPanEnd: widget.enabled
                          ? (_) => setState(() {
                                _dragTarget = null;
                                _fingerPosition = null;
                                _activeHandlePosition = null;
                                _activeImagePoint = null;
                              })
                          : null,
                      onPanCancel: widget.enabled
                          ? () => setState(() {
                                _dragTarget = null;
                                _fingerPosition = null;
                                _activeHandlePosition = null;
                                _activeImagePoint = null;
                              })
                          : null,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(
                            color: const Color(0xFFF8FAF7),
                            child: widget.bytes == null
                                ? const _ImagePlaceholder()
                                : Image.memory(widget.bytes!,
                                    fit: BoxFit.contain),
                          ),
                          CustomPaint(
                            painter: _ReferenceLinePainter(
                              fittedRect: fittedRect,
                              imageSize: sourceSize,
                              start: widget.start,
                              end: widget.end,
                              selectedHandle: _selectedHandle,
                              fingerPosition: _fingerPosition,
                              activeHandlePosition: _activeHandlePosition,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
        if (hasLine) ...[
          const SizedBox(height: 8),
          _ReferenceHandleControls(
            enabled: widget.enabled,
            selectedHandle: _selectedHandle,
            onSelectStart: () => setState(() => _selectedHandle = 'start'),
            onSelectEnd: () => setState(() => _selectedHandle = 'end'),
            onNudgeLeft: () => nudgeSelected(const Offset(-1, 0)),
            onNudgeUp: () => nudgeSelected(const Offset(0, -1)),
            onNudgeDown: () => nudgeSelected(const Offset(0, 1)),
            onNudgeRight: () => nudgeSelected(const Offset(1, 0)),
          ),
        ],
      ],
    );
  }
}

class _ReferenceHandleControls extends StatelessWidget {
  final bool enabled;
  final String selectedHandle;
  final VoidCallback onSelectStart;
  final VoidCallback onSelectEnd;
  final VoidCallback onNudgeLeft;
  final VoidCallback onNudgeUp;
  final VoidCallback onNudgeDown;
  final VoidCallback onNudgeRight;

  const _ReferenceHandleControls({
    required this.enabled,
    required this.selectedHandle,
    required this.onSelectStart,
    required this.onSelectEnd,
    required this.onNudgeLeft,
    required this.onNudgeUp,
    required this.onNudgeDown,
    required this.onNudgeRight,
  });

  @override
  Widget build(BuildContext context) {
    final chips = [
      ChoiceChip(
        label: const Text('Chốt A'),
        selected: selectedHandle == 'start',
        onSelected: enabled ? (_) => onSelectStart() : null,
      ),
      ChoiceChip(
        label: const Text('Chốt B'),
        selected: selectedHandle == 'end',
        onSelected: enabled ? (_) => onSelectEnd() : null,
      ),
    ];
    final nudges = [
      _NudgeButton(
        icon: Icons.arrow_back,
        onPressed: enabled ? onNudgeLeft : null,
      ),
      _NudgeButton(
        icon: Icons.arrow_upward,
        onPressed: enabled ? onNudgeUp : null,
      ),
      _NudgeButton(
        icon: Icons.arrow_downward,
        onPressed: enabled ? onNudgeDown : null,
      ),
      _NudgeButton(
        icon: Icons.arrow_forward,
        onPressed: enabled ? onNudgeRight : null,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(spacing: 6, runSpacing: 6, children: chips),
              const SizedBox(height: 4),
              Wrap(spacing: 4, runSpacing: 4, children: nudges),
            ],
          );
        }

        return Row(
          children: [
            ...chips.expand((chip) => [chip, const SizedBox(width: 6)]),
            const Spacer(),
            ...nudges,
          ],
        );
      },
    );
  }
}

Rect _containedRect(Size target, Size source) {
  final scale =
      math.min(target.width / source.width, target.height / source.height);
  final fitted = Size(source.width * scale, source.height * scale);
  return Rect.fromLTWH(
    (target.width - fitted.width) / 2,
    (target.height - fitted.height) / 2,
    fitted.width,
    fitted.height,
  );
}

class _NudgeButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _NudgeButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 38,
      height: 38,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        iconSize: 19,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

class _ReferenceMagnifier extends StatelessWidget {
  final ui.Image sourceImage;
  final Size imageSize;
  final Offset? start;
  final Offset? end;
  final String selectedHandle;
  final Offset targetImagePoint;

  const _ReferenceMagnifier({
    required this.sourceImage,
    required this.imageSize,
    required this.start,
    required this.end,
    required this.selectedHandle,
    required this.targetImagePoint,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CustomPaint(
          size: const Size(90, 90),
          painter: _ReferenceMagnifierPainter(
            sourceImage: sourceImage,
            imageSize: imageSize,
            start: start,
            end: end,
            target: targetImagePoint,
          ),
        ),
        const Center(child: _MagnifierCrosshair()),
        Positioned(
          top: 4,
          left: 4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              child: Text(
                selectedHandle == 'start' ? 'A' : 'B',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReferenceMagnifierPainter extends CustomPainter {
  static const _windowPixels = 72.0;

  final ui.Image sourceImage;
  final Size imageSize;
  final Offset? start;
  final Offset? end;
  final Offset target;

  const _ReferenceMagnifierPainter({
    required this.sourceImage,
    required this.imageSize,
    required this.start,
    required this.end,
    required this.target,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cropSide = math.min(
      _windowPixels,
      math.min(imageSize.width, imageSize.height),
    );
    final maxLeft = math.max(0.0, imageSize.width - cropSide);
    final maxTop = math.max(0.0, imageSize.height - cropSide);
    final cropLeft = (target.dx - cropSide / 2).clamp(0.0, maxLeft).toDouble();
    final cropTop = (target.dy - cropSide / 2).clamp(0.0, maxTop).toDouble();
    final sourceRect = Rect.fromLTWH(cropLeft, cropTop, cropSide, cropSide);
    final destination = Offset.zero & size;
    canvas.drawImageRect(sourceImage, sourceRect, destination, Paint());

    Offset magnifiedPoint(Offset point) => Offset(
          (point.dx - sourceRect.left) / sourceRect.width * size.width,
          (point.dy - sourceRect.top) / sourceRect.height * size.height,
        );
    if (start != null && end != null) {
      final linePaint = Paint()
        ..color = const Color(0xFF2563EB)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(magnifiedPoint(start!), magnifiedPoint(end!), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ReferenceMagnifierPainter oldDelegate) =>
      sourceImage != oldDelegate.sourceImage ||
      imageSize != oldDelegate.imageSize ||
      start != oldDelegate.start ||
      end != oldDelegate.end ||
      target != oldDelegate.target;
}

class _MagnifierCrosshair extends StatelessWidget {
  const _MagnifierCrosshair();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(30, 30),
      painter: _MagnifierCrosshairPainter(),
    );
  }
}

class _MagnifierCrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final inner = Paint()
      ..color = const Color(0xFFDC2626)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final paint in [outer, inner]) {
      canvas.drawCircle(center, 6, paint);
      canvas.drawLine(center.translate(-14, 0), center.translate(-8, 0), paint);
      canvas.drawLine(center.translate(8, 0), center.translate(14, 0), paint);
      canvas.drawLine(center.translate(0, -14), center.translate(0, -8), paint);
      canvas.drawLine(center.translate(0, 8), center.translate(0, 14), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ReferenceLinePainter extends CustomPainter {
  final Rect fittedRect;
  final Size? imageSize;
  final Offset? start;
  final Offset? end;
  final String selectedHandle;
  final Offset? fingerPosition;
  final Offset? activeHandlePosition;

  const _ReferenceLinePainter({
    required this.fittedRect,
    required this.imageSize,
    required this.start,
    required this.end,
    required this.selectedHandle,
    required this.fingerPosition,
    required this.activeHandlePosition,
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

    final paintLine = Paint()
      ..color = const Color(0xFF2563EB)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final paintHandleInner = Paint()
      ..color = const Color(0xFF2563EB)
      ..style = PaintingStyle.fill;

    final paintHandleOuter = Paint()
      ..color = const Color(0x242563EB)
      ..style = PaintingStyle.fill;

    final paintBorder = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final paintSelected = Paint()
      ..color = const Color(0xFF2563EB)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final paintLeader = Paint()
      ..color = const Color(0x992563EB)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(a, b, paintLine);
    final selectedPoint = selectedHandle == 'start' ? a : b;
    for (final point in [a, b]) {
      if (point == selectedPoint) {
        canvas.drawCircle(point, 11, paintHandleOuter);
      }
      canvas.drawCircle(point, 5, paintHandleInner);
      canvas.drawCircle(point, 5, paintBorder);
    }
    canvas.drawCircle(selectedPoint, 12, paintSelected);

    final finger = fingerPosition;
    final target = activeHandlePosition;
    if (finger != null && target != null) {
      canvas.drawCircle(target, 12, paintSelected);
      canvas.drawLine(
          target.translate(-10, 0), target.translate(10, 0), paintLeader);
      canvas.drawLine(
          target.translate(0, -10), target.translate(0, 10), paintLeader);
    }
  }

  @override
  bool shouldRepaint(covariant _ReferenceLinePainter oldDelegate) =>
      fittedRect != oldDelegate.fittedRect ||
      imageSize != oldDelegate.imageSize ||
      start != oldDelegate.start ||
      end != oldDelegate.end ||
      selectedHandle != oldDelegate.selectedHandle ||
      fingerPosition != oldDelegate.fingerPosition ||
      activeHandlePosition != oldDelegate.activeHandlePosition;
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.add_photo_alternate_outlined,
            size: 42,
            color: AppTheme.textSecondary.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 10),
          const Text(
            'Chưa có ảnh',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Chọn ảnh hoặc chụp ảnh để bắt đầu',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _QcFactCard extends StatelessWidget {
  final String label;
  final String value;

  const _QcFactCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 74),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF2C078)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 360 || value.length > 28;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  softWrap: true,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  softWrap: true,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Text(
                  label,
                  softWrap: true,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                flex: 4,
                child: Text(
                  value,
                  softWrap: true,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          );
        },
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
  final message = error.toString().replaceFirst('Exception: ', '').trim();
  if (message.isNotEmpty && message != 'null') {
    final firstLine = message.split('\n').first;
    return 'Xử lý trên thiết bị thất bại: $firstLine';
  }
  return 'Xử lý trên thiết bị thất bại. Vui lòng thử lại với ảnh khác.';
}

double _asDouble(dynamic value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

class _GuideSlide extends StatelessWidget {
  final String title;
  final String description;
  final Widget diagram;

  const _GuideSlide({
    required this.title,
    required this.description,
    required this.diagram,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: AppTheme.primary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Center(
              child: diagram,
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideImage extends StatelessWidget {
  final String assetPath;

  const _GuideImage(this.assetPath);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAF7),
          border: Border.all(color: AppTheme.border),
        ),
        child: Image.asset(
          assetPath,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class _CalibrationGuideDialog extends StatefulWidget {
  const _CalibrationGuideDialog();

  @override
  State<_CalibrationGuideDialog> createState() =>
      _CalibrationGuideDialogState();
}

class _CalibrationGuideDialogState extends State<_CalibrationGuideDialog> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: Colors.white,
      child: Container(
        padding: const EdgeInsets.all(16),
        width: 320,
        height: 425,
        child: Column(
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.help_center_outlined,
                        color: AppTheme.primary, size: 20),
                    SizedBox(width: 6),
                    Text(
                      'Hướng dẫn căn mốc',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const Divider(height: 20, color: AppTheme.border),
            // Slides
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (page) => setState(() => _currentPage = page),
                children: const [
                  _GuideSlide(
                    title: '1. Upload ảnh hạt và vật mốc',
                    description:
                        'Chọn hoặc chụp ảnh có cả hạt cần đo và vật mốc có kích thước thật đã biết.',
                    diagram:
                        _GuideImage('assets/images/calibration_guide_1.png'),
                  ),
                  _GuideSlide(
                    title: '2. Tạo đoạn đo bằng 2 chốt',
                    description:
                        'Chạm lên vật mốc để tạo đoạn thẳng gồm chốt A và chốt B.',
                    diagram:
                        _GuideImage('assets/images/calibration_guide_2.png'),
                  ),
                  _GuideSlide(
                    title: '3. Kéo thả chốt đo vật mốc',
                    description:
                        'Kéo từng chốt tới đúng hai mép vật mốc; có thể dùng nút mũi tên để tinh chỉnh từng pixel.',
                    diagram:
                        _GuideImage('assets/images/calibration_guide_3.png'),
                  ),
                  _GuideSlide(
                    title: '4. Nhập kích thước thật',
                    description:
                        'Nhập chiều dài thật của vật mốc vào ô Vật mốc (mm), sau đó bấm Xử lý.',
                    diagram:
                        _GuideImage('assets/images/calibration_guide_4.png'),
                  ),
                ],
              ),
            ),
            const Divider(height: 20, color: AppTheme.border),
            // Footer Control
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Indicators
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(4, (index) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: _currentPage == index ? 14 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _currentPage == index
                            ? AppTheme.primary
                            : AppTheme.border,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
                // Buttons
                Row(
                  children: [
                    if (_currentPage > 0)
                      TextButton(
                        onPressed: () {
                          _pageController.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                        child: const Text(
                          'Quay lại',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 13),
                        ),
                      ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        textStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        if (_currentPage < 3) {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        } else {
                          Navigator.of(context).pop();
                        }
                      },
                      child: Text(_currentPage == 3 ? 'Bắt đầu' : 'Tiếp theo'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
