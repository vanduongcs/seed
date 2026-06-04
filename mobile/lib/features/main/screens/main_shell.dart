import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_language.dart';
import '../../../core/theme/app_theme.dart';
import '../../account/screens/account_screen.dart';
import '../../auth/providers/auth_provider.dart';
import '../../dashboard/screens/dashboard_screen.dart';
import '../../storage/screens/storage_screen.dart';

class MainShell extends ConsumerStatefulWidget {
  final int initialIndex;

  const MainShell({super.key, required this.initialIndex});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  @override
  void didUpdateWidget(covariant MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIndex != widget.initialIndex) {
      _currentIndex = widget.initialIndex;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isGuest = ref.watch(guestModeProvider).value ?? false;
    final language = ref.watch(appLanguageProvider);
    final titles = [
      appText(language, 'Trang chủ', 'Home'),
      appText(language, 'Lưu trữ', 'Storage'),
      appText(language, 'Tài khoản', 'Account'),
    ];
    const pages = [
      DashboardScreen(),
      StorageScreen(),
      AccountScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _ShellTopBar(
          title: titles[_currentIndex],
          isGuest: isGuest,
          language: language,
          onLanguageChanged: (nextLanguage) =>
              ref.read(appLanguageProvider.notifier).setLanguage(nextLanguage),
          onLogin: () => context.go('/login'),
          onRegister: () => context.go('/register'),
          onLogout: () async {
            await ref.read(authProvider.notifier).logout();
            if (context.mounted) context.go('/login');
          },
        ),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.dashboard_outlined),
            activeIcon: const Icon(Icons.dashboard),
            label: appText(language, 'Trang chủ', 'Home'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.inventory_2_outlined),
            activeIcon: const Icon(Icons.inventory_2),
            label: appText(language, 'Lưu trữ', 'Storage'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.account_circle_outlined),
            activeIcon: const Icon(Icons.account_circle),
            label: appText(language, 'Tài khoản', 'Account'),
          ),
        ],
      ),
    );
  }
}

class _ShellTopBar extends StatelessWidget {
  final String title;
  final bool isGuest;
  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;
  final VoidCallback onLogin;
  final VoidCallback onRegister;
  final Future<void> Function() onLogout;

  const _ShellTopBar({
    required this.title,
    required this.isGuest,
    required this.language,
    required this.onLanguageChanged,
    required this.onLogin,
    required this.onRegister,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).appBarTheme.titleTextStyle ??
        Theme.of(context).textTheme.titleLarge;

    return SizedBox(
      height: kToolbarHeight,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: titleStyle,
            ),
          ),
          Positioned(
            right: 4,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LanguageMenu(
                  language: language,
                  onChanged: onLanguageChanged,
                ),
                if (isGuest) ...[
                  _AuthNavButton(
                    label: appText(language, 'Đăng nhập', 'Log in'),
                    onPressed: onLogin,
                  ),
                  _AuthNavButton(
                    label: appText(language, 'Đăng ký', 'Sign up'),
                    onPressed: onRegister,
                  ),
                ] else
                  IconButton(
                    tooltip: appText(language, 'Đăng xuất', 'Log out'),
                    icon: const Icon(Icons.logout),
                    onPressed: onLogout,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageMenu extends StatelessWidget {
  final AppLanguage language;
  final ValueChanged<AppLanguage> onChanged;

  const _LanguageMenu({
    required this.language,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<AppLanguage>(
      tooltip: appText(language, 'Ngôn ngữ', 'Language'),
      initialValue: language,
      onSelected: onChanged,
      itemBuilder: (context) => AppLanguage.values
          .map(
            (item) => PopupMenuItem<AppLanguage>(
              value: item,
              child: Row(
                children: [
                  if (item == language)
                    const Icon(Icons.check, size: 18)
                  else
                    const SizedBox(width: 18),
                  const SizedBox(width: 8),
                  Text(item.label),
                ],
              ),
            ),
          )
          .toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(
          language.code.toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        ),
      ),
    );
  }
}

class _AuthNavButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _AuthNavButton({
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: AppTheme.primary,
        minimumSize: const Size(58, 36),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Text(label),
    );
  }
}
