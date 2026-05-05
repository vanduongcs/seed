import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seed'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Xin chào! 👋', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Hôm nay bạn muốn làm gì?', style: TextStyle(color: AppTheme.textSecondary, fontSize: 15)),
            const SizedBox(height: 28),

            _FeatureCard(
              gradient: const LinearGradient(colors: [AppTheme.primary, Color(0xFF5B21B6)]),
              icon: Icons.chat_bubble_outline,
              title: 'AI Chat',
              desc: 'Trò chuyện với AI thông minh',
              onTap: () => context.push('/chat'),
            ),
            const SizedBox(height: 16),
            _FeatureCard(
              gradient: const LinearGradient(colors: [AppTheme.secondary, Color(0xFF0891B2)]),
              icon: Icons.trending_up,
              title: 'Phân tích',
              desc: 'Xem thống kê và lịch sử',
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final LinearGradient gradient;
  final IconData icon;
  final String title;
  final String desc;
  final VoidCallback onTap;

  const _FeatureCard({ required this.gradient, required this.icon, required this.title, required this.desc, required this.onTap });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [gradient.colors.first.withOpacity(0.15), gradient.colors.last.withOpacity(0.08)],
          ),
          border: Border.all(color: gradient.colors.first.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: gradient),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(desc, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              ],
            )),
            Icon(Icons.arrow_forward_ios, size: 16, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}
