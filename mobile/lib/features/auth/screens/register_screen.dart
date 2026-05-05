import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _showPass = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    await ref.read(authProvider.notifier).register(
        _nameCtrl.text.trim(), _emailCtrl.text.trim(), _passCtrl.text);
    final state = ref.read(authProvider);
    if (state.hasError && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Lỗi: ${state.error}'), backgroundColor: Colors.red));
    } else if (!state.hasError && mounted) {
      context.go('/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authProvider).isLoading;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                        colors: [AppTheme.secondary, AppTheme.primary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                    boxShadow: [
                      BoxShadow(
                          color: AppTheme.secondary.withValues(alpha: 0.4),
                          blurRadius: 20)
                    ],
                  ),
                  child: const Icon(Icons.auto_awesome,
                      color: Colors.white, size: 36),
                ),
                const SizedBox(height: 24),
                const Text('Tạo tài khoản',
                    style:
                        TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('Bắt đầu hành trình với Seed AI',
                    style:
                        TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                const SizedBox(height: 32),
                TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Họ và tên',
                        prefixIcon: Icon(Icons.person_outline))),
                const SizedBox(height: 16),
                TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined))),
                const SizedBox(height: 16),
                TextField(
                  controller: _passCtrl,
                  obscureText: !_showPass,
                  decoration: InputDecoration(
                    labelText: 'Mật khẩu',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                        icon: Icon(_showPass
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () =>
                            setState(() => _showPass = !_showPass)),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : _register,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.secondary),
                    child: isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Đăng ký'),
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => context.go('/login'),
                  child: const Text.rich(TextSpan(children: [
                    TextSpan(
                        text: 'Đã có tài khoản? ',
                        style: TextStyle(color: AppTheme.textSecondary)),
                    TextSpan(
                        text: 'Đăng nhập',
                        style: TextStyle(
                            color: AppTheme.primaryLight,
                            fontWeight: FontWeight.w600)),
                  ])),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
