import 'package:flutter/material.dart';
import '../../models/repositories/database_settings_repository.dart';
import '../../models/settings/database_settings.dart';
import '../../services/cloud_sync_reminder.dart';

Future<void> checkForCloudSyncReminder(
  BuildContext context, {
  required DatabaseSettingsRepository repository,
  required void Function(int settingsTab) onOpenSettings,
}) async {
  try {
    final reminder = await CloudSyncReminder(repository).check();
    if (!context.mounted || reminder == null) return;
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nhắc việc hằng ngày'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final kind in reminder.kinds)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_message(kind, reminder.settings)),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Để sau'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Mở cài đặt'),
          ),
        ],
      ),
    );
    if (open == true && context.mounted) onOpenSettings(reminder.settingsTab);
  } catch (_) {
    // A local settings read failure must not prevent opening the application.
  }
}

String _message(DailyReminderKind kind, DatabaseSettings settings) {
  switch (kind) {
    case DailyReminderKind.cloudConnection:
      return 'Cài đặt chuỗi kết nối MongoDB Cloud.';
    case DailyReminderKind.backupDirectory:
      return 'Cài đặt thư mục backup trên máy.';
    case DailyReminderKind.sync:
      return settings.lastSyncAt == null
          ? 'Đồng bộ dữ liệu với MongoDB Cloud. Chưa có lần đồng bộ thành công.'
          : 'Đồng bộ dữ liệu với MongoDB Cloud. Lần đồng bộ thành công gần nhất không còn trong hôm nay.';
  }
}
