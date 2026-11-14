import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/services/cloud_sync_reminder.dart';
import 'package:xemay_app/views/settings/cloud_sync_reminder_dialog.dart';
import 'package:xemay_app/controllers/database_settings_controller.dart';
import 'package:xemay_app/models/settings/database_settings.dart';
import 'support/fake_database_settings_repository.dart';

void main() {
  final now = DateTime.utc(2026, 11, 10, 10);
  test('first day reminds to configure cloud and backup once', () async {
    final repo = FakeDatabaseSettingsRepository();
    final reminder = CloudSyncReminder(repo);
    final first = await reminder.check(now: now);
    expect(first?.kinds, [
      DailyReminderKind.cloudConnection,
      DailyReminderKind.backupDirectory,
    ]);
    expect(first?.settingsTab, 2);
    expect(repo.settings.syncReminderStartedAt, now);
    expect(repo.settings.dailyReminderAt, now);
    expect(
      await reminder.check(now: now.add(const Duration(hours: 5))),
      isNull,
    );
    final nextDay = await reminder.check(now: now.add(const Duration(days: 1)));
    expect(nextDay?.kinds, contains(DailyReminderKind.cloudConnection));
    expect(nextDay?.kinds, contains(DailyReminderKind.backupDirectory));
    expect(nextDay?.kinds, isNot(contains(DailyReminderKind.sync)));
  });

  test('configured databases remind to sync on the next local day', () async {
    final repo = FakeDatabaseSettingsRepository()
      ..settings = DatabaseSettings(
        mongoUri: 'mongodb://local/XM',
        cloudUri: 'mongodb://cloud/XM',
        backupDirectory: '/tmp/sao-luu',
      );
    final reminder = CloudSyncReminder(repo);
    expect(await reminder.check(now: now), isNull);
    expect(repo.settings.syncReminderStartedAt, now);
    final due = await reminder.check(now: now.add(const Duration(days: 1)));
    expect(due?.kinds, [DailyReminderKind.sync]);
    expect(due?.settingsTab, 2);
  });

  test('backup-only reminder opens the local MongoDB tab', () async {
    final repo = FakeDatabaseSettingsRepository()
      ..settings = DatabaseSettings(
        mongoUri: 'mongodb://local/XM',
        cloudUri: 'mongodb://cloud/XM',
        lastSyncAt: now,
      );
    final due = await CloudSyncReminder(repo).check(now: now);
    expect(due?.kinds, [DailyReminderKind.backupDirectory]);
    expect(due?.settingsTab, 0);
  });

  test(
    'successful sync aligns both versions, records history and resets reminder',
    () async {
      final repo = FakeDatabaseSettingsRepository()
        ..settings = DatabaseSettings(
          mongoUri: 'mongodb://local/XM',
          cloudUri: 'mongodb://cloud/XM',
          backupDirectory: '/tmp/sao-luu',
          syncReminderStartedAt: now.subtract(const Duration(days: 2)),
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
      expect(CloudSyncReminder.isDue(controller.settings, now), isFalse);
      expect(
        CloudSyncReminder.isDue(
          controller.settings,
          now.add(const Duration(days: 1)),
        ),
        isTrue,
      );
    },
  );
  test(
    'failed sync is recorded but does not reset last successful sync',
    () async {
      final previous = now.subtract(const Duration(days: 2));
      final repo = FakeDatabaseSettingsRepository()
        ..settings = DatabaseSettings(
          mongoUri: 'mongodb://local/XM',
          cloudUri: 'mongodb://cloud/XM',
          backupDirectory: '/tmp/sao-luu',
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

  testWidgets('daily reminder lists the outstanding setup and sync tasks', (
    tester,
  ) async {
    final repo = FakeDatabaseSettingsRepository()
      ..settings = DatabaseSettings(
        mongoUri: 'mongodb://local/XM',
        syncReminderStartedAt: now.subtract(const Duration(days: 1)),
      );
    var openedTab = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => checkForCloudSyncReminder(
                context,
                repository: repo,
                onOpenSettings: (tab) => openedTab = tab,
              ),
              child: const Text('Mở nhắc'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mở nhắc'));
    await tester.pumpAndSettle();
    expect(find.text('Nhắc việc hằng ngày'), findsOneWidget);
    expect(find.text('Cài đặt chuỗi kết nối MongoDB Cloud.'), findsOneWidget);
    expect(find.text('Cài đặt thư mục backup trên máy.'), findsOneWidget);
    expect(
      find.text(
        'Đồng bộ dữ liệu với MongoDB Cloud. Chưa có lần đồng bộ thành công.',
      ),
      findsNothing,
    );
    await tester.tap(find.text('Mở cài đặt'));
    await tester.pumpAndSettle();
    expect(openedTab, 2);
  });
}
