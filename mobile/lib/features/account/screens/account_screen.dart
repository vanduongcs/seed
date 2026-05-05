import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  void _openSettings(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cài đặt'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
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

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Thông tin tài khoản',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          'Cập nhật thông tin người dùng và cấu hình ứng dụng.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 18),
        const TextField(
          decoration: InputDecoration(labelText: 'Họ và tên'),
        ),
        const SizedBox(height: 14),
        const TextField(
          decoration: InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 14),
        const TextField(
          decoration: InputDecoration(labelText: 'Đơn vị/Phòng ban'),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () {},
          child: const Text('Lưu thay đổi'),
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
