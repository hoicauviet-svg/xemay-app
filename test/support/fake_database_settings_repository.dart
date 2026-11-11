import 'package:xemay_app/models/settings/database_settings.dart';
import 'package:xemay_app/models/repositories/database_settings_repository.dart';

class FakeDatabaseSettingsRepository implements DatabaseSettingsRepository {
  DatabaseSettings settings = const DatabaseSettings(
    mongoUri: 'mongodb://127.0.0.1:27017/XM',
    sqlConnection: 'Server=test;Database=xm;UID=user;PWD=example;',
  );
  MongoInstallationStatus status = const MongoInstallationStatus(
    installed: false,
    connected: false,
  );
  int saves = 0, clones = 0, backups = 0, restores = 0;
  String? backupDirectory, restorePath, backupUri, restoreUri;
  String? openedBackupDirectory;
  bool failBackup = false;
  DateTime? backupNow;
  bool installOpened = false, failSql = false;
  @override
  Future<DatabaseSettings> load() async => settings;
  @override
  Future<void> save(DatabaseSettings value) async {
    settings = value;
    saves++;
  }

  @override
  Future<MongoInstallationStatus> checkMongo(String uri) async => status;
  @override
  Future<int> checkSql(String connection) async {
    if (failSql) {
      throw const DatabaseSettingsException('Không kết nối được SQL Server.');
    }
    return 20;
  }

  @override
  Future<DatabaseCloneResult> clone({
    required String mongoUri,
    required String sqlConnection,
    required void Function(String) progress,
  }) async {
    clones++;
    progress('Đã kiểm tra dữ liệu');
    return const DatabaseCloneResult(
      mongoUri: 'mongodb://127.0.0.1:27017/XM_import_test',
      database: 'XM_import_test',
      rows: 150000,
      orphans: 123,
      purchases: 1922,
    );
  }

  int syncs = 0;
  String? syncSource, syncTarget;
  bool failSync = false;
  static const localVersion = DatabaseVersion(
    version: 'local-hash',
    revision: 1,
    observedAt: '2026-11-10T10:00:00Z',
    rows: 42,
    collections: 3,
  );
  static const remoteVersion = DatabaseVersion(
    version: 'cloud-hash',
    revision: 2,
    observedAt: '2026-11-10T10:00:00Z',
    rows: 40,
    collections: 3,
  );
  int conflicts = 0;
  String? policy;
  @override
  Future<CloudComparison> compareCloud({
    required String sourceUri,
    required String targetUri,
    void Function(String)? progress,
  }) async => CloudComparison(
    sourceVersion: localVersion,
    targetVersion: remoteVersion,
    sourceOnly: 3,
    targetOnly: 2,
    conflicts: conflicts,
    schemaConflicts: 0,
    identical: 38,
  );
  @override
  Future<CloudSyncResult> syncCloud({
    required String sourceUri,
    required String targetUri,
    required String expectedSourceVersion,
    required String expectedTargetVersion,
    required String conflictPolicy,
    required void Function(String) progress,
  }) async {
    policy = conflictPolicy;
    syncs++;
    syncSource = sourceUri;
    syncTarget = targetUri;
    if (failSync) throw const DatabaseSettingsException('Đồng bộ thất bại.');
    progress('Đã đối chiếu dữ liệu');
    return CloudSyncResult(
      mongoUri: '$targetUri-sync',
      sourceMongoUri: '$sourceUri-sync',
      database: 'XM_sync',
      version: remoteVersion,
      rows: 42,
      collections: 3,
    );
  }

  @override
  Future<MongoBackupResult> backupMongo({
    required String mongoUri,
    required String directory,
    DateTime? now,
    void Function(String)? progress,
  }) async {
    backups++;
    backupUri = mongoUri;
    backupDirectory = directory;
    backupNow = now;
    if (failBackup) {
      throw const DatabaseSettingsException('Chưa sao lưu được dữ liệu.');
    }
    progress?.call('Đang sao lưu Xe');
    return const MongoBackupResult(database: 'XM', collections: 2, rows: 5);
  }

  @override
  Future<MongoBackupResult> restoreMongo({
    required String mongoUri,
    required String path,
    void Function(String)? progress,
  }) async {
    restores++;
    restoreUri = mongoUri;
    restorePath = path;
    progress?.call('Đang khôi phục Xe');
    return const MongoBackupResult(database: 'XM', collections: 2, rows: 5);
  }

  @override
  Future<void> openBackupDirectory(String path) async {
    openedBackupDirectory = path;
  }

  @override
  Future<void> openMongoInstallation() async {
    installOpened = true;
  }
}
