import '../models/repositories/database_settings_repository.dart';
import '../models/settings/database_settings.dart';

/// Uses local saved settings only, so startup never needs a cloud connection.
class CloudSyncReminder {
  const CloudSyncReminder(this.repository);
  final DatabaseSettingsRepository repository;
  static const interval = Duration(days: 30);

  static bool isDue(DatabaseSettings settings, DateTime now) {
    final baseline = settings.lastSyncAt ?? settings.syncReminderStartedAt;
    return baseline != null &&
        now.toUtc().difference(baseline.toUtc()) >= interval;
  }

  Future<DatabaseSettings?> check({DateTime? now}) async {
    final time = now ?? DateTime.now();
    final settings = await repository.load();
    if (settings.lastSyncAt == null && settings.syncReminderStartedAt == null) {
      await repository.save(settings.copyWith(syncReminderStartedAt: time));
      return null;
    }
    return isDue(settings, time) ? settings : null;
  }
}
