import '../models/repositories/database_settings_repository.dart';
import '../models/settings/database_settings.dart';

enum DailyReminderKind { cloudConnection, backupDirectory, sync }

class DailyReminder {
  const DailyReminder(this.kinds, this.settings);
  final List<DailyReminderKind> kinds;
  final DatabaseSettings settings;

  int get settingsTab =>
      kinds.contains(DailyReminderKind.backupDirectory) &&
          !kinds.contains(DailyReminderKind.cloudConnection) &&
          !kinds.contains(DailyReminderKind.sync)
      ? 0
      : 2;
}

/// One reminder per local calendar day. Setup gaps show immediately; sync
/// becomes due on the next day after the last successful sync.
class CloudSyncReminder {
  const CloudSyncReminder(this.repository);
  final DatabaseSettingsRepository repository;

  static DateTime _localDate(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  static bool _sameLocalDay(DateTime? value, DateTime now) =>
      value != null && _localDate(value) == _localDate(now);

  static bool isDue(DatabaseSettings settings, DateTime now) =>
      dueKinds(settings, now).contains(DailyReminderKind.sync);

  static List<DailyReminderKind> dueKinds(
    DatabaseSettings settings,
    DateTime now,
  ) {
    final kinds = <DailyReminderKind>[];
    if (settings.cloudUri.trim().isEmpty) {
      kinds.add(DailyReminderKind.cloudConnection);
    }
    if (settings.backupDirectory.trim().isEmpty) {
      kinds.add(DailyReminderKind.backupDirectory);
    }
    final baseline = settings.lastSyncAt ?? settings.syncReminderStartedAt;
    if (settings.cloudUri.trim().isNotEmpty &&
        baseline != null &&
        _localDate(baseline).isBefore(_localDate(now))) {
      kinds.add(DailyReminderKind.sync);
    }
    return kinds;
  }

  Future<DailyReminder?> check({DateTime? now}) async {
    final time = now ?? DateTime.now();
    var settings = await repository.load();
    final started = settings.syncReminderStartedAt;
    if (settings.lastSyncAt == null && started == null) {
      settings = settings.copyWith(syncReminderStartedAt: time);
    }
    final kinds = dueKinds(settings, time);
    if (kinds.isEmpty || _sameLocalDay(settings.dailyReminderAt, time)) {
      if (settings.syncReminderStartedAt != started) {
        await repository.save(settings);
      }
      return null;
    }
    settings = settings.copyWith(dailyReminderAt: time);
    await repository.save(settings);
    return DailyReminder(kinds, settings);
  }
}
