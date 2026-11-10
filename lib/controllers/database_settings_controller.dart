import '../services/mongo_connection_uri.dart';
import 'package:flutter/foundation.dart';
import '../core/config/database_config.dart';
import '../models/repositories/database_settings_repository.dart';
import '../models/settings/database_settings.dart';
import 'cart_controller.dart';

class DatabaseSettingsController extends ChangeNotifier {
  DatabaseSettingsController(this.repository);
  final DatabaseSettingsRepository repository;
  DatabaseSettings settings = DatabaseSettings(
    mongoUri: DatabaseConfig.mongoUri,
  );
  MongoInstallationStatus? mongo, cloud;
  DatabaseCloneResult? cloneResult;
  bool busy = false, loaded = false, _disposed = false;
  String? error, message;
  final List<String> progress = [];
  String _cloneConnection = '';

  Future<void> _perform(Future<void> Function() work) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    message = null;
    notifyListeners();
    try {
      await work();
    } on DatabaseSettingsException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Chưa hoàn tất thao tác. Kiểm tra kết nối và thử lại.';
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> load() => _perform(() async {
    settings = await repository.load();
    loaded = true;
    mongo = await repository.checkMongo(settings.mongoUri);
  });
  void _validateMongo(String uri) => MongoConnectionUri.validate(uri.trim());
  void _checkSwitch(String uri) {
    if (uri != DatabaseConfig.configuredMongoUri &&
        (CartController.shared.count > 0 || CartController.shared.locked)) {
      throw const DatabaseSettingsException(
        'Hãy hoàn tất hoặc bỏ đơn bán hàng đang nhập trước khi đổi dữ liệu.',
      );
    }
  }

  Future<void> checkMongo(String uri) => _perform(() async {
    _validateMongo(uri);
    mongo = await repository.checkMongo(uri.trim());
    message = mongo!.connected ? 'Kết nối MongoDB thành công.' : null;
  });
  Future<void> saveMongo(String uri) => _perform(() async {
    uri = uri.trim();
    _validateMongo(uri);
    _checkSwitch(uri);
    mongo = await repository.checkMongo(uri);
    if (!mongo!.connected) {
      throw const DatabaseSettingsException(
        'Chưa kết nối được MongoDB. Kiểm tra dịch vụ và chuỗi kết nối trước khi lưu.',
      );
    }
    final next = DatabaseSettings(
      mongoUri: uri,
      sqlConnection: settings.sqlConnection,
      cloudUri: settings.cloudUri,
    );
    await repository.save(next);
    settings = next;
    message = 'Đã lưu kết nối MongoDB.';
  });
  Future<void> checkSql(
    String connection, {
    bool save = false,
  }) => _perform(() async {
    if (connection.trim().isEmpty) {
      throw const DatabaseSettingsException('Nhập chuỗi kết nối SQL Server.');
    }
    final count = await repository.checkSql(connection.trim());
    if (save) {
      final next = DatabaseSettings(
        mongoUri: settings.mongoUri,
        sqlConnection: connection.trim(),
        cloudUri: settings.cloudUri,
      );
      await repository.save(next);
      settings = next;
    }
    message =
        '${save ? 'Đã lưu. ' : ''}Kết nối database xm thành công: $count bảng.';
  });
  Future<void> clone(String connection) => _perform(() async {
    if (connection.trim().isEmpty) {
      throw const DatabaseSettingsException('Nhập chuỗi kết nối SQL Server.');
    }
    _validateMongo(settings.mongoUri);
    progress.clear();
    cloneResult = null;
    _cloneConnection = connection.trim();
    cloneResult = await repository.clone(
      mongoUri: settings.mongoUri,
      sqlConnection: connection.trim(),
      progress: (line) {
        if (_disposed) return;
        progress.add(line);
        if (progress.length > 150) progress.removeAt(0);
        notifyListeners();
      },
    );
    message =
        'Sao chép thành công ${cloneResult!.rows} dòng; đã kiểm tra và sửa cấu trúc dữ liệu.';
  });
  Future<void> useClone() => _perform(() async {
    final result = cloneResult;
    if (result == null) return;
    _checkSwitch(result.mongoUri);
    mongo = await repository.checkMongo(result.mongoUri);
    if (!mongo!.connected) {
      throw const DatabaseSettingsException(
        'Chưa kết nối được bản sao. Hãy kiểm tra MongoDB trước khi chuyển dữ liệu.',
      );
    }
    final next = DatabaseSettings(
      mongoUri: result.mongoUri,
      sqlConnection: _cloneConnection,
      cloudUri: settings.cloudUri,
    );
    await repository.save(next);
    settings = next;
    message = 'Đã chuyển sang sử dụng dữ liệu vừa sao chép.';
  });
  Future<void> checkCloud(
    String uri, {
    bool save = false,
  }) => _perform(() async {
    uri = uri.trim();
    _validateMongo(uri);
    cloud = await repository.checkMongo(uri);
    if (!cloud!.connected) {
      throw const DatabaseSettingsException(
        'Chưa kết nối được MongoDB Cloud. Kiểm tra tài khoản, mạng và IP được phép truy cập.',
      );
    }
    if (save) {
      final next = DatabaseSettings(
        mongoUri: settings.mongoUri,
        sqlConnection: settings.sqlConnection,
        cloudUri: uri,
      );
      await repository.save(next);
      settings = next;
    }
    message = save
        ? 'Đã lưu kết nối MongoDB Cloud.'
        : 'Kết nối MongoDB Cloud thành công.';
  });

  Future<void> syncCloud({required bool upload}) => _perform(() async {
    if (CartController.shared.count > 0 || CartController.shared.locked) {
      throw const DatabaseSettingsException(
        'Hãy hoàn tất hoặc bỏ đơn bán hàng đang nhập trước khi đồng bộ.',
      );
    }
    if (settings.cloudUri.isEmpty) {
      throw const DatabaseSettingsException(
        'Lưu kết nối MongoDB Cloud trước khi đồng bộ.',
      );
    }
    if (settings.cloudUri == settings.mongoUri) {
      throw const DatabaseSettingsException(
        'Nguồn và đích đồng bộ phải là hai kết nối khác nhau.',
      );
    }
    _validateMongo(settings.mongoUri);
    _validateMongo(settings.cloudUri);
    progress.clear();
    final result = await repository.syncCloud(
      sourceUri: upload ? settings.mongoUri : settings.cloudUri,
      targetUri: upload ? settings.cloudUri : settings.mongoUri,
      progress: (line) {
        if (_disposed) return;
        progress.add(line);
        if (progress.length > 150) progress.removeAt(0);
        notifyListeners();
      },
    );
    final next = DatabaseSettings(
      mongoUri: upload ? settings.mongoUri : result.mongoUri,
      sqlConnection: settings.sqlConnection,
      cloudUri: upload ? result.mongoUri : settings.cloudUri,
    );
    await repository.save(next);
    settings = next;
    message =
        '${upload ? 'Đã đồng bộ lên cloud' : 'Đã tải về và sử dụng dữ liệu trên máy'}: ${result.collections} bảng, ${result.rows} dòng. Bản dữ liệu trước vẫn được giữ lại.';
  });

  Future<void> openInstallation() => _perform(repository.openMongoInstallation);
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
