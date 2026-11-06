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
  int saves = 0, clones = 0;
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

  @override
  Future<void> openMongoInstallation() async {
    installOpened = true;
  }
}
