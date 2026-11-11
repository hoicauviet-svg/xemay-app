import '../models/repositories/database_settings_repository.dart';
import '../models/settings/database_settings.dart';

/// Writes one backup of the database in use, then repeats every five days.
class MongoBackupSchedule {
  const MongoBackupSchedule(this.repository);
  final DatabaseSettingsRepository repository;
  static const interval = Duration(days: 5);

  static bool isDue(DatabaseSettings settings, DateTime now) {
    if (settings.backupDirectory.trim().isEmpty) return false;
    final last = settings.lastBackupAt;
    if (last == null) return false;
    return !now.toUtc().isBefore(last.toUtc().add(interval));
  }

  Future<bool> runIfDue({DateTime? now}) async {
    final time = now ?? DateTime.now();
    final settings = await repository.load();
    if (!isDue(settings, time)) return false;
    await repository.backupMongo(
      mongoUri: settings.mongoUri,
      directory: settings.backupDirectory.trim(),
      now: time,
    );
    final current = await repository.load();
    if (current.backupDirectory.trim() != settings.backupDirectory.trim()) {
      return true;
    }
    await repository.save(current.copyWith(lastBackupAt: time));
    return true;
  }
}
