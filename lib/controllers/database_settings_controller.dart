import '../services/mongo_connection_uri.dart';
import 'package:flutter/foundation.dart';
import '../core/config/database_config.dart';
import '../models/repositories/database_settings_repository.dart';
import '../models/settings/database_settings.dart';
import 'cart_controller.dart';

enum SettingsSection { mongo, sql, cloud }

class DatabaseSettingsController extends ChangeNotifier {
  DatabaseSettingsController(this.repository, {DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  final DatabaseSettingsRepository repository;
  DatabaseSettings settings = DatabaseSettings(
    mongoUri: DatabaseConfig.mongoUri,
  );
  MongoInstallationStatus? mongo, cloud;
  CloudComparison? comparison;
  bool? _comparisonUpload;
  DatabaseCloneResult? cloneResult;
  bool busy = false, loaded = false, _disposed = false;
  SettingsSection _operationSection = SettingsSection.mongo;
  final Map<SettingsSection, String> _errors = {}, _messages = {};
  final Map<SettingsSection, List<String>> _progress = {};
  String? errorFor(SettingsSection section) => _errors[section];
  String? messageFor(SettingsSection section) => _messages[section];
  bool busyFor(SettingsSection section) => busy && _operationSection == section;
  String? get error => errorFor(_operationSection);
  set error(String? value) {
    if (value == null) {
      _errors.remove(_operationSection);
    } else {
      _errors[_operationSection] = value;
    }
  }

  String? get message => messageFor(_operationSection);
  set message(String? value) {
    if (value == null) {
      _messages.remove(_operationSection);
    } else {
      _messages[_operationSection] = value;
    }
  }

  List<String> progressFor(SettingsSection section) =>
      _progress.putIfAbsent(section, () => []);
  List<String> get progress => progressFor(_operationSection);
  String _cloneConnection = '';

  Future<void> _perform(
    SettingsSection section,
    Future<void> Function() work,
  ) async {
    if (busy || _disposed) return;
    busy = true;
    _operationSection = section;
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

  Future<void> load() => _perform(SettingsSection.mongo, () async {
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

  Future<void> checkMongo(String uri) =>
      _perform(SettingsSection.mongo, () async {
        _validateMongo(uri);
        mongo = await repository.checkMongo(uri.trim());
        message = mongo!.connected ? 'Kết nối MongoDB thành công.' : null;
      });
  Future<void> saveMongo(
    String uri,
  ) => _perform(SettingsSection.mongo, () async {
    uri = uri.trim();
    _validateMongo(uri);
    _checkSwitch(uri);
    mongo = await repository.checkMongo(uri);
    if (!mongo!.connected) {
      throw const DatabaseSettingsException(
        'Chưa kết nối được MongoDB. Kiểm tra dịch vụ và chuỗi kết nối trước khi lưu.',
      );
    }
    final next = settings.copyWith(mongoUri: uri);
    await repository.save(next);
    settings = next;
    comparison = null;
    message = 'Đã lưu kết nối MongoDB.';
  });
  Future<void> checkSql(
    String connection, {
    bool save = false,
  }) => _perform(SettingsSection.sql, () async {
    if (connection.trim().isEmpty) {
      throw const DatabaseSettingsException('Nhập chuỗi kết nối SQL Server.');
    }
    final count = await repository.checkSql(connection.trim());
    if (save) {
      final next = settings.copyWith(sqlConnection: connection.trim());
      await repository.save(next);
      settings = next;
    }
    message =
        '${save ? 'Đã lưu. ' : ''}Kết nối database xm thành công: $count bảng.';
  });
  Future<void> clone(
    String connection,
  ) => _perform(SettingsSection.sql, () async {
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
  Future<void> useClone() => _perform(SettingsSection.sql, () async {
    final result = cloneResult;
    if (result == null) return;
    _checkSwitch(result.mongoUri);
    mongo = await repository.checkMongo(result.mongoUri);
    if (!mongo!.connected) {
      throw const DatabaseSettingsException(
        'Chưa kết nối được bản sao. Hãy kiểm tra MongoDB trước khi chuyển dữ liệu.',
      );
    }
    final next = settings.copyWith(
      mongoUri: result.mongoUri,
      sqlConnection: _cloneConnection,
    );
    await repository.save(next);
    settings = next;
    message = 'Đã chuyển sang sử dụng dữ liệu vừa sao chép.';
  });
  Future<void> checkCloud(
    String uri, {
    bool save = false,
  }) => _perform(SettingsSection.cloud, () async {
    uri = uri.trim();
    _validateMongo(uri);
    cloud = await repository.checkMongo(uri);
    if (!cloud!.connected) {
      throw const DatabaseSettingsException(
        'Chưa kết nối được MongoDB Cloud. Kiểm tra tài khoản, mạng và IP được phép truy cập.',
      );
    }
    if (save) {
      final next = settings.copyWith(cloudUri: uri);
      await repository.save(next);
      settings = next;
      comparison = null;
    }
    message = save
        ? 'Đã lưu kết nối MongoDB Cloud.'
        : 'Kết nối MongoDB Cloud thành công.';
  });

  void _validateSync() {
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
  }

  Future<void> compareCloud({required bool upload}) =>
      _perform(SettingsSection.cloud, () async {
        comparison = null;
        _comparisonUpload = null;
        progress.clear();
        _validateSync();
        final result = await repository.compareCloud(
          sourceUri: upload ? settings.mongoUri : settings.cloudUri,
          targetUri: upload ? settings.cloudUri : settings.mongoUri,
          progress: (line) {
            if (_disposed) return;
            progress.add(line);
            if (progress.length > 150) progress.removeAt(0);
            notifyListeners();
          },
        );
        final next = settings.copyWith(
          databaseVersion: upload ? result.sourceVersion : result.targetVersion,
          cloudVersion: upload ? result.targetVersion : result.sourceVersion,
        );
        await repository.save(next);
        settings = next;
        comparison = result;
        _comparisonUpload = upload;
        message = result.sourceVersion.version == result.targetVersion.version
            ? 'Hai database có cùng nội dung.'
            : 'Đã so sánh phiên bản. Kiểm tra cảnh báo trước khi gộp.';
      });

  Future<void> syncCloud({
    required bool upload,
    String conflictPolicy = 'abort',
  }) => _perform(SettingsSection.cloud, () async {
    _validateSync();
    final preview = comparison;
    if (preview == null || _comparisonUpload != upload) {
      throw const DatabaseSettingsException(
        'So sánh phiên bản trước khi đồng bộ.',
      );
    }
    if (!['abort', 'source', 'target'].contains(conflictPolicy) ||
        (preview.hasConflicts && conflictPolicy == 'abort')) {
      throw const DatabaseSettingsException(
        'Có xung đột. Hãy chọn bên ưu tiên hoặc hủy thao tác.',
      );
    }
    progress.clear();
    // Consume the preview: a failed transfer must be compared again.
    comparison = null;
    _comparisonUpload = null;
    late CloudSyncResult result;
    try {
      result = await repository.syncCloud(
        sourceUri: upload ? settings.mongoUri : settings.cloudUri,
        targetUri: upload ? settings.cloudUri : settings.mongoUri,
        expectedSourceVersion: preview.sourceVersion.version,
        expectedTargetVersion: preview.targetVersion.version,
        conflictPolicy: conflictPolicy,
        progress: (line) {
          if (_disposed) return;
          progress.add(line);
          if (progress.length > 150) progress.removeAt(0);
          notifyListeners();
        },
      );
      if (result.sourceMongoUri == null || result.version == null) {
        throw const DatabaseSettingsException(
          'Công cụ dữ liệu chưa hỗ trợ đồng bộ hai phía. Hãy cập nhật công cụ và thử lại.',
        );
      }
    } catch (_) {
      final failed = settings.copyWith(
        syncHistory: [
          SyncHistoryEntry(
            at: _now(),
            upload: upload,
            success: false,
            conflictPolicy: conflictPolicy,
          ),
          ...settings.syncHistory,
        ].take(50).toList(),
      );
      try {
        await repository.save(failed);
        settings = failed;
      } catch (_) {}
      rethrow;
    }
    final completedAt = _now();
    final next = settings.copyWith(
      mongoUri: upload ? result.sourceMongoUri : result.mongoUri,
      cloudUri: upload ? result.mongoUri : result.sourceMongoUri,
      databaseVersion: result.version,
      cloudVersion: result.version,
      lastSyncAt: completedAt,
      syncReminderStartedAt: settings.syncReminderStartedAt ?? completedAt,
      syncHistory: [
        SyncHistoryEntry(
          at: completedAt,
          upload: upload,
          success: true,
          version: result.version,
          rows: result.rows,
          collections: result.collections,
          conflictPolicy: conflictPolicy,
        ),
        ...settings.syncHistory,
      ].take(50).toList(),
    );
    await repository.save(next);
    settings = next;
    message =
        '${upload ? 'Đã đồng bộ lên cloud' : 'Đã tải về và sử dụng dữ liệu trên máy'}: ${result.collections} bảng, ${result.rows} dòng. Bản dữ liệu trước vẫn được giữ lại.';
  });

  void _note(String line) {
    if (_disposed) return;
    progress.add(line);
    if (progress.length > 150) progress.removeAt(0);
    notifyListeners();
  }

  void _checkRestore() {
    if (CartController.shared.count > 0 || CartController.shared.locked) {
      throw const DatabaseSettingsException(
        'Hãy hoàn tất hoặc bỏ đơn bán hàng đang nhập trước khi khôi phục dữ liệu.',
      );
    }
  }

  Future<MongoBackupResult> _writeBackup(DatabaseSettings current) async {
    final time = _now();
    final result = await repository.backupMongo(
      mongoUri: current.mongoUri,
      directory: current.backupDirectory.trim(),
      now: time,
      progress: _note,
    );
    final stamped = current.copyWith(lastBackupAt: time);
    await repository.save(stamped);
    settings = stamped;
    return result;
  }

  Future<void> saveBackupDirectory(String directory) => _perform(
    SettingsSection.mongo,
    () async {
      final path = directory.trim();
      if (path.isEmpty) {
        throw const DatabaseSettingsException('Chọn thư mục lưu bản sao lưu.');
      }
      final next = settings.copyWith(backupDirectory: path);
      await repository.save(next);
      settings = next;
      message = 'Đã lưu thư mục sao lưu.';
    },
  );

  Future<void> openBackupDirectory() =>
      _perform(SettingsSection.mongo, () async {
        final path = settings.backupDirectory.trim();
        if (path.isEmpty) {
          throw const DatabaseSettingsException(
            'Chọn thư mục lưu bản sao lưu trước.',
          );
        }
        await repository.openBackupDirectory(path);
      });

  Future<void> backupNow() => _perform(SettingsSection.mongo, () async {
    if (settings.backupDirectory.trim().isEmpty) {
      throw const DatabaseSettingsException(
        'Chọn thư mục lưu bản sao lưu trước.',
      );
    }
    _validateMongo(settings.mongoUri);
    progress.clear();
    final result = await _writeBackup(settings);
    message = 'Đã sao lưu ${result.collections} bảng, ${result.rows} dòng.';
  });

  Future<void> restoreMongo(
    String path,
  ) => _perform(SettingsSection.mongo, () async {
    if (path.trim().isEmpty) {
      throw const DatabaseSettingsException('Chọn file sao lưu để khôi phục.');
    }
    _validateMongo(settings.mongoUri);
    _checkRestore();
    progress.clear();
    final result = await repository.restoreMongo(
      mongoUri: settings.mongoUri,
      path: path,
      progress: _note,
    );
    message =
        'Đã khôi phục ${result.collections} bảng, ${result.rows} dòng. Mở lại các màn hình để xem dữ liệu mới.';
  });

  Future<void> openInstallation() =>
      _perform(SettingsSection.mongo, repository.openMongoInstallation);
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
