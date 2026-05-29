import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'mobile_update_service.dart';

class MobileUpdateGate extends StatefulWidget {
  final Widget child;

  const MobileUpdateGate({super.key, required this.child});

  @override
  State<MobileUpdateGate> createState() => _MobileUpdateGateState();
}

class _MobileUpdateGateState extends State<MobileUpdateGate> {
  static const _channel = MethodChannel('vn.mekonglab.seedvision/app_update');

  final _updateService = MobileUpdateService();
  bool _checked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    try {
      final result = await _updateService.check();
      if (!mounted || result == null) return;
      await _showUpdateDialog(result);
    } catch (_) {}
  }

  Future<void> _showUpdateDialog(MobileUpdateCheckResult result) async {
    final info = result.updateInfo;
    final required = result.isRequired;
    await showDialog<void>(
      context: context,
      barrierDismissible: !required,
      builder: (context) {
        return PopScope(
          canPop: !required,
          child: AlertDialog(
            title: Text(info.title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(info.message),
                const SizedBox(height: 10),
                Text(
                  'Phiên bản mới: ${info.latestVersionName}',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            actions: [
              if (!required)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Để sau'),
                ),
              ElevatedButton.icon(
                onPressed: () => _openStore(info.playStoreUrl),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Cập nhật'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openStore(String playStoreUrl) async {
    await _channel.invokeMethod<void>('openStore', {
      'playStoreUrl': playStoreUrl,
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
