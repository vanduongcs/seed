import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../grain/providers/grain_runs_provider.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runsState = ref.watch(grainRunsProvider);

    return runsState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _DashboardContent(
        stats: const _DashboardStats.empty(),
        error: 'Không tải được thống kê: $error',
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
              'Web import ảnh hoặc lấy frame camera, backend chạy worker Python, sau đó lưu run để web và mobile cùng đọc lịch sử.',
              style: TextStyle(color: AppTheme.textSecondary, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
