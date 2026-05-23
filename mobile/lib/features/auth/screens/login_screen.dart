import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _showPass = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text;

    await ref.read(authProvider.notifier).login(email, password);
    final state = ref.read(authProvider);
    if (state.hasError && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(child: Text('Đăng nhập thất bại: ${state.error}')),
            ],
          ),
          backgroundColor: const Color(0xFFD92D20),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } else if (!state.hasError && mounted) {
      context.go('/dashboard');
    }
  }

  Future<void> _continueWithoutLogin() async {
    await ref.read(authProvider.notifier).continueWithoutLogin();
    if (mounted) context.go('/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authProvider);
    final isLoading = state.isLoading;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF5F7F5),
          gradient: RadialGradient(
            colors: [
              Color(0xFFFCFDFC),
              Color(0xFFE6ECE6),
            ],
            center: Alignment.center,
            radius: 1.2,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.82),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: const Color(0x282F6B4F), // rgba(47, 107, 79, 0.16)
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 30,
                          offset: const Offset(0, 15),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Organic Sprout Brand Logo
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: const Color(0x0D2F6B4F), // rgba(47, 107, 79, 0.05)
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: const Color(0x1F2F6B4F), // rgba(47, 107, 79, 0.12)
                                    width: 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0x0A2F6B4F),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.spa_rounded,
                                    size: 26,
                                    color: Color(0xFF2F6B4F),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Header - Only "Đăng nhập" as requested
                          const Text(
                            'Đăng nhập',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1B2C21),
                              letterSpacing: -0.8,
                            ),
                          ),
                          const SizedBox(height: 36),

                      // Email field label
                      const Padding(
                        padding: EdgeInsets.only(left: 2, bottom: 8),
                        child: Text(
                          'ĐỊA CHỈ EMAIL',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                            color: Color(0xFF4D5C52),
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      // Email Field
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        style: const TextStyle(fontSize: 14.5, color: Color(0xFF1B2C21)),
                        decoration: InputDecoration(
                          hintText: 'email@example.com',
                          hintStyle: const TextStyle(color: Color(0xFF6B7C72), fontSize: 14),
                          prefixIcon: const Icon(Icons.email_outlined, size: 19, color: Color(0xFF6B7C72)),
                          filled: true,
                          fillColor: const Color(0xFFF8FAF8),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0x1F2F6B4F)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0x1F2F6B4F)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFF2F6B4F), width: 1.5),
                          ),
                          errorStyle: const TextStyle(color: Color(0xFFD92D20)),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Vui lòng nhập địa chỉ email';
                          }
                          final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
                          if (!emailRegex.hasMatch(value.trim())) {
                            return 'Định dạng email không hợp lệ';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      // Password field label
                      const Padding(
                        padding: EdgeInsets.only(left: 2, bottom: 8),
                        child: Text(
                          'MẬT KHẨU',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                            color: Color(0xFF4D5C52),
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      // Password Field
                      TextFormField(
                        controller: _passCtrl,
                        obscureText: !_showPass,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _login(),
                        style: const TextStyle(fontSize: 14.5, color: Color(0xFF1B2C21)),
                        decoration: InputDecoration(
                          hintText: 'Nhập mật khẩu của bạn',
                          hintStyle: const TextStyle(color: Color(0xFF6B7C72), fontSize: 14),
                          prefixIcon: const Icon(Icons.lock_outline_rounded, size: 19, color: Color(0xFF6B7C72)),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              size: 19,
                              color: const Color(0xFF6B7C72),
                            ),
                            onPressed: () => setState(() => _showPass = !_showPass),
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAF8),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0x1F2F6B4F)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0x1F2F6B4F)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFF2F6B4F), width: 1.5),
                          ),
                          errorStyle: const TextStyle(color: Color(0xFFD92D20)),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Vui lòng nhập mật khẩu';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 28),

                      // Login button
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: isLoading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2F6B4F),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0x592F6B4F),
                            disabledForegroundColor: const Color(0x8CFFFFFF),
                            shadowColor: const Color(0x332F6B4F),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text(
                                  'Đăng nhập',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: isLoading ? null : _continueWithoutLogin,
                          icon: const Icon(Icons.phone_android_outlined),
                          label: const Text(
                            'Tiếp tục không đăng nhập',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Toggle screen
                      GestureDetector(
                        onTap: () => context.go('/register'),
                        child: const Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: 'Chưa có tài khoản? ',
                                style: TextStyle(color: Color(0xFF6B7C72), fontSize: 13.5),
                              ),
                              TextSpan(
                                text: 'Đăng ký ngay',
                                style: TextStyle(
                                  color: Color(0xFF2F6B4F),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                ),
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);
  }
}
