import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        Text(
          'Tổng quan mẫu hạt',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 6),
        Text(
          'Theo dõi lượt sử dụng và dữ liệu đo đạc chính.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        SizedBox(height: 22),
        Row(
          children: [
            Expanded(child: _StatTile(label: 'Tháng này', value: '128')),
            SizedBox(width: 12),
            Expanded(child: _StatTile(label: 'Tổng lượt', value: '3.918')),
          ],
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _StatTile(label: 'Hạt đã đo', value: '18.240')),
            SizedBox(width: 12),
            Expanded(child: _StatTile(label: 'Dài TB', value: '7,42 mm')),
          ],
        ),
        SizedBox(height: 18),
        _ProcessCard(),
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
                    'Xử lý ảnh đo đạc',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Website hỗ trợ kết nối camera hoặc import ảnh để nhận dạng, segment và xuất kết quả đo. Mobile hiển thị nhanh thống kê và lịch sử xử lý.',
              style: TextStyle(color: AppTheme.textSecondary, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
