import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../account/screens/account_screen.dart';
import '../../dashboard/screens/dashboard_screen.dart';
import '../../storage/screens/storage_screen.dart';
import '../../auth/providers/auth_provider.dart';

class MainShell extends ConsumerWidget {
  final int initialIndex;

  const MainShell({super.key, required this.initialIndex});

  static const _paths = ['/dashboard', '/storage', '/account'];
  static const _titles = ['Trang chủ', 'Lưu trữ', 'Tài khoản'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGuest = ref.watch(guestModeProvider).value ?? false;
    const pages = [
      DashboardScreen(),
      StorageScreen(),
      AccountScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[initialIndex]),
        actions: isGuest
            ? [
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Đăng nhập'),
                ),
                TextButton(
                  onPressed: () => context.go('/register'),
                  child: const Text('Đăng ký'),
                ),
              ]
            : [
                IconButton(
                  tooltip: 'Đăng xuất',
                  icon: const Icon(Icons.logout),
                  onPressed: () async {
                    await ref.read(authProvider.notifier).logout();
                    if (context.mounted) context.go('/login');
                  },
                ),
              ],
      ),
      body: pages[initialIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: initialIndex,
        onTap: (index) => context.go(_paths[index]),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Trang chủ',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.inventory_2_outlined),
            activeIcon: Icon(Icons.inventory_2),
            label: 'Lưu trữ',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_circle_outlined),
            activeIcon: Icon(Icons.account_circle),
            label: 'Tài khoản',
          ),
        ],
      ),
    );
  }
}
