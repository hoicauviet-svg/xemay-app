import 'package:flutter/material.dart';
import '../../models/repositories/database_settings_repository.dart';
import '../../services/cloud_sync_reminder.dart';

Future<void> checkForCloudSyncReminder(
  BuildContext context, {
  required DatabaseSettingsRepository repository,
  required VoidCallback onOpenSettings,
}) async {
  try {
    final settings = await CloudSyncReminder(repository).check();
    if (!context.mounted || settings == null) return;
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đã đến lúc đồng bộ dữ liệu'),
        content: Text(
          settings.lastSyncAt == null
              ? 'Bạn đã dùng ứng dụng ít nhất 30 ngày nhưng chưa đồng bộ dữ liệu. Hãy đồng bộ với MongoDB Cloud để lưu một bản dữ liệu mới.'
              : 'Đã ít nhất 30 ngày kể từ lần đồng bộ thành công gần nhất. Hãy kiểm tra và đồng bộ dữ liệu với MongoDB Cloud.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Để sau'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Mở đồng bộ cloud'),
          ),
        ],
      ),
    );
    if (open == true && context.mounted) onOpenSettings();
  } catch (_) {
    // A local settings read failure must not prevent opening the application.
  }
}
