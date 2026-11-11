import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/services/cloud_sync_reminder.dart';
import 'package:xemay_app/controllers/database_settings_controller.dart';
import 'package:xemay_app/models/settings/database_settings.dart';
import 'support/fake_database_settings_repository.dart';

void main() {
  final now = DateTime.utc(2026, 11, 10, 10);
  test(
    'reminder starts on first use and becomes due at exactly thirty days',
    () async {
      final repo = FakeDatabaseSettingsRepository();
      final reminder = CloudSyncReminder(repo);
      expect(await reminder.check(now: now), isNull);
      expect(repo.settings.syncReminderStartedAt, now);
      expect(
        await reminder.check(now: now.add(const Duration(days: 29, hours: 23))),
        isNull,
      );
      expect(
        await reminder.check(now: now.add(const Duration(days: 30))),
        isNotNull,
      );
      expect(repo.saves, 1);
    },
  );
  test(
    'successful sync aligns both versions, records history and resets reminder',
    () async {
      final repo = FakeDatabaseSettingsRepository()
        ..settings = DatabaseSettings(
          mongoUri: 'mongodb://local/XM',
          cloudUri: 'mongodb://cloud/XM',
          syncReminderStartedAt: now.subtract(const Duration(days: 20)),
        );
      final controller = DatabaseSettingsController(repo, now: () => now);
      addTearDown(controller.dispose);
      await controller.load();
      await controller.compareCloud(upload: true);
      await controller.syncCloud(upload: true);
      expect(controller.error, isNull);
      expect(
        controller.settings.databaseVersion?.version,
        controller.settings.cloudVersion?.version,
      );
      expect(
        controller.settings.databaseVersion?.revision,
        controller.settings.cloudVersion?.revision,
      );
      expect(controller.settings.lastSyncAt, now);
      expect(controller.settings.syncHistory.single.success, isTrue);
      expect(
        CloudSyncReminder.isDue(
          controller.settings,
          now.add(const Duration(days: 29)),
        ),
        isFalse,
      );
      expect(
        CloudSyncReminder.isDue(
          controller.settings,
          now.add(const Duration(days: 30)),
        ),
        isTrue,
      );
    },
  );
  test(
    'failed sync is recorded but does not reset last successful sync',
    () async {
      final previous = now.subtract(const Duration(days: 31));
      final repo = FakeDatabaseSettingsRepository()
        ..settings = DatabaseSettings(
          mongoUri: 'mongodb://local/XM',
          cloudUri: 'mongodb://cloud/XM',
          lastSyncAt: previous,
        )
        ..failSync = true;
      final controller = DatabaseSettingsController(repo, now: () => now);
      addTearDown(controller.dispose);
      await controller.load();
      await controller.compareCloud(upload: false);
      await controller.syncCloud(upload: false);
      expect(controller.settings.lastSyncAt, previous);
      expect(controller.settings.syncHistory.single.success, isFalse);
      expect(controller.settings.syncHistory.single.upload, isFalse);
      expect(CloudSyncReminder.isDue(controller.settings, now), isTrue);
    },
  );
}
