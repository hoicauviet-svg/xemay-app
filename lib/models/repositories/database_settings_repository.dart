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
  Future<CloudSyncResult> syncCloud({
    required String sourceUri,
    required String targetUri,
    required void Function(String) progress,
  });
  Future<void> openMongoInstallation();
}
