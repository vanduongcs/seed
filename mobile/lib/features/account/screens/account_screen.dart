import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _api = ApiClient();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _roleCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _guestMode = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _roleCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    try {
      const storage = FlutterSecureStorage();
      if (await storage.read(key: guestModeKey) == 'true') {
        if (mounted) {
          setState(() {
            _guestMode = true;
            _loading = false;
          });
        }
        return;
      }
      final response = await _api.get('/users/me');
      final user = Map<String, dynamic>.from(response.data['data'] as Map);
      _nameCtrl.text = user['name']?.toString() ?? '';
      _emailCtrl.text = user['email']?.toString() ?? '';
      _roleCtrl.text = user['role']?.toString() ?? 'user';
    } catch (error) {
      _showError('Không tải được tài khoản: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (_nameCtrl.text.trim().length < 2) {
      _showError('Họ và tên cần ít nhất 2 ký tự');
      return;
    }

    setState(() => _saving = true);
    try {
      final response = await _api.patch('/users/me', data: {
        'name': _nameCtrl.text.trim(),
      });
      final user = Map<String, dynamic>.from(response.data['data'] as Map);
      _nameCtrl.text = user['name']?.toString() ?? _nameCtrl.text;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã cập nhật tài khoản')),
        );
      }
    } catch (error) {
      _showError('Cập nhật thất bại: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openSettings(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cài đặt'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Đơn vị đo mặc định'),
              subtitle: Text('Milimét (mm)'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Tự động lưu kết quả'),
              subtitle: Text('Đang bật'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_guestMode) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Chế độ không đăng nhập',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          const Text(
            'Các bản xử lý đang được lưu trên điện thoại này. Đăng nhập hoặc đăng ký để đồng bộ chúng lên tài khoản của bạn.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => context.go('/login'),
            child: const Text('Đăng nhập để đồng bộ'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => context.go('/register'),
            child: const Text('Đăng ký tài khoản'),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Thông tin tài khoản',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          'Thông tin được đọc và cập nhật qua cùng backend API với website.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(labelText: 'Họ và tên'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _emailCtrl,
          enabled: false,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _roleCtrl,
          enabled: false,
          decoration: const InputDecoration(labelText: 'Vai trò'),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _saving ? null : _saveProfile,
          child: _saving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text('Lưu thay đổi'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => _openSettings(context),
          child: const Text('Cài đặt'),
        ),
      ],
    );
  }
}
