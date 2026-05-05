import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class StorageScreen extends StatelessWidget {
  const StorageScreen({super.key});

  static const records = [
    ('RUN-001', '05/05/2026 21:18', '124 hạt', '7,42 x 3,18 mm'),
    ('RUN-002', '04/05/2026 16:40', '96 hạt', '7,11 x 3,05 mm'),
    ('RUN-003', '03/05/2026 09:12', '143 hạt', '7,66 x 3,22 mm'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Lịch sử xử lý',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          'Output số liệu, thời gian và mẫu ảnh đã xử lý.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 18),
        ...records.map(
          (record) => Card(
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
                        record.$1.split('-').last,
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
                          record.$1,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          record.$2,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text('${record.$3} - ${record.$4}'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
