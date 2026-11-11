import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/models/settings/database_settings.dart';
import 'package:xemay_app/services/mongo_backup_schedule.dart';
import 'support/fake_database_settings_repository.dart';

void main() {
  test('automatic backup runs every five days', () async {
    final repo = FakeDatabaseSettingsRepository();
    final schedule = MongoBackupSchedule(repo);
    final now = DateTime.utc(2026, 11, 11);
    expect(MongoBackupSchedule.isDue(repo.settings, now), isFalse);
    repo.settings = repo.settings.copyWith(backupDirectory: '/tmp/sao-luu');
    expect(await schedule.runIfDue(now: now), isFalse);
    expect(repo.backups, 0);
    repo.settings = repo.settings.copyWith(
      lastBackupAt: now.subtract(const Duration(days: 5)),
    );
    expect(await schedule.runIfDue(now: now), isTrue);
    expect(repo.backups, 1);
    expect(repo.backupDirectory, '/tmp/sao-luu');
    expect(repo.backupNow, now);
    expect(repo.settings.lastBackupAt, now);
    expect(
      MongoBackupSchedule.isDue(
        repo.settings,
        now.add(const Duration(days: 4, hours: 23)),
      ),
      isFalse,
    );
    expect(
      await schedule.runIfDue(now: now.add(const Duration(days: 4))),
      isFalse,
    );
    expect(repo.backups, 1);
    expect(
      MongoBackupSchedule.isDue(
        repo.settings,
        now.add(const Duration(days: 5)),
      ),
      isTrue,
    );
    repo.failBackup = true;
    expect(
      () => schedule.runIfDue(now: now.add(const Duration(days: 5))),
      throwsA(isA<DatabaseSettingsException>()),
    );
    expect(repo.settings.lastBackupAt, now);
  });
}
