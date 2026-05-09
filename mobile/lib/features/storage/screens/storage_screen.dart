import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../grain/providers/grain_runs_provider.dart';

class StorageScreen extends ConsumerWidget {
  const StorageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runsState = ref.watch(grainRunsProvider);

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
            const _Header(),
            const SizedBox(height: 18),
            Text(
              'Không tải được lịch sử: $error',
              style: TextStyle(color: Colors.red.shade700),
            ),
          ],
        ),
        data: (runs) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const _Header(),
            const SizedBox(height: 18),
            if (runs.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Chưa có lịch sử. Hãy chạy phân tích ảnh trên web để tạo run đầu tiên.',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
              )
            else
              ...runs.map((run) => _RunCard(run: run)),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Lịch sử xử lý',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 6),
        Text(
          'Các lần xử lý được lưu từ backend sau khi worker Python trả kết quả.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
      ],
    );
  }
}

class _RunCard extends StatelessWidget {
  final GrainRun run;

  const _RunCard({required this.run});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
                    '${run.count} hạt - ${run.meanLengthPx.toStringAsFixed(1)} x ${run.meanWidthPx.toStringAsFixed(1)} px',
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
    );
  }
}

String _formatDate(DateTime? value) {
  if (value == null) return '-';
  return '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/'
      '${value.year} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
