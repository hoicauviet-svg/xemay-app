import '../settings/database_settings.dart';

abstract class DatabaseSettingsRepository {
  Future<DatabaseSettings> load();
  Future<void> save(DatabaseSettings settings);
  Future<MongoInstallationStatus> checkMongo(String uri);
  Future<int> checkSql(String connection);
  Future<DatabaseCloneResult> clone({
    required String mongoUri,
    required String sqlConnection,
    required void Function(String) progress,
  });
  Future<CloudComparison> compareCloud({
    required String sourceUri,
    required String targetUri,
    void Function(String)? progress,
  });
  Future<CloudSyncResult> syncCloud({
    required String sourceUri,
    required String targetUri,
    required String expectedSourceVersion,
    required String expectedTargetVersion,
    required String conflictPolicy,
    required void Function(String) progress,
  });
  Future<MongoBackupResult> backupMongo({
    required String mongoUri,
    required String directory,
    DateTime? now,
    void Function(String)? progress,
  });
  Future<MongoBackupResult> restoreMongo({
    required String mongoUri,
    required String path,
    void Function(String)? progress,
  });
  Future<void> openBackupDirectory(String path);
  Future<void> openMongoInstallation();
}
