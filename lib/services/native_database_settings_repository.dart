import 'mongo_connection_uri.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import '../core/config/database_config.dart';
import '../models/repositories/database_settings_repository.dart';
import '../models/settings/database_settings.dart';

class NativeDatabaseSettingsRepository implements DatabaseSettingsRepository {
  static const _channel = MethodChannel('xemay/database_settings');
  static final _asset = Platform.isWindows
      ? 'assets/database_helper/xemay_database_helper_windows.zip'
      : 'assets/database_helper/xemay_database_helper';
  Future<String>? _executable;
  Future<void>? _cloudCompatibility;

  Future<void> _ensureCloudSupport() =>
      _cloudCompatibility ??= _checkCloudSupport().catchError((Object error) {
        _cloudCompatibility = null;
        throw error;
      });

  Future<void> _checkCloudSupport() async {
    const guidance =
        'Công cụ dữ liệu đi kèm ứng dụng đã cũ, chưa hỗ trợ đồng bộ cloud. Hãy đóng ứng dụng và chạy lại bằng run.command hoặc cài bản ứng dụng mới.';
    try {
      final info = await _run({'command': 'capabilities'});
      final commands = info['commands'];
      if (info['protocolVersion'] != 3 ||
          commands is! List ||
          !commands.contains('compareCloud') ||
          !commands.contains('syncCloud')) {
        throw const DatabaseSettingsException(guidance);
      }
    } on DatabaseSettingsException catch (error) {
      if (error.message.contains('Yêu cầu không được hỗ trợ')) {
        throw const DatabaseSettingsException(guidance);
      }
      rethrow;
    }
  }

  @override
  Future<DatabaseSettings> load() async {
    final value = await _channel.invokeMethod<String>('load');
    final json = value == null
        ? <String, dynamic>{}
        : jsonDecode(value) as Map<String, dynamic>;
    return DatabaseSettings(
      mongoUri:
          json['mongoUri'] as String? ?? DatabaseConfig.configuredMongoUri,
      sqlConnection: json['sqlConnection'] as String? ?? '',
      cloudUri: json['cloudUri'] as String? ?? '',
      lastSyncAt: DateTime.tryParse(json['lastSyncAt'] as String? ?? ''),
      syncReminderStartedAt: DateTime.tryParse(
        json['syncReminderStartedAt'] as String? ?? '',
      ),
      syncHistory: (json['syncHistory'] as List? ?? [])
          .map(
            (entry) => SyncHistoryEntry.fromJson(
              Map<String, dynamic>.from(entry as Map),
            ),
          )
          .toList(),
      databaseVersion: json['databaseVersion'] is Map
          ? DatabaseVersion.fromJson(
              Map<String, dynamic>.from(json['databaseVersion'] as Map),
            )
          : null,
      cloudVersion: json['cloudVersion'] is Map
          ? DatabaseVersion.fromJson(
              Map<String, dynamic>.from(json['cloudVersion'] as Map),
            )
          : null,
    );
  }

  @override
  Future<void> save(DatabaseSettings settings) async {
    final runtimeUri = settings.mongoUri == DatabaseConfig.configuredMongoUri
        ? DatabaseConfig.mongoUri
        : await MongoConnectionUri.resolve(settings.mongoUri);
    await _channel.invokeMethod<void>('save', {
      'value': jsonEncode(settings.toJson()),
    });
    DatabaseConfig.useMongo(settings.mongoUri, runtimeUri: runtimeUri);
  }

  static Future<void> activate(DatabaseSettings settings) async {
    final runtimeUri = await MongoConnectionUri.resolve(settings.mongoUri);
    DatabaseConfig.useMongo(settings.mongoUri, runtimeUri: runtimeUri);
  }

  Future<String> _prepare() =>
      _executable ??= _extract().catchError((Object error) {
        _executable = null;
        throw error;
      });
  Future<String> _extract() async {
    final path = await _channel.invokeMethod<String>('supportDirectory');
    if (path == null) {
      throw const DatabaseSettingsException(
        'Chưa mở được thư mục dữ liệu ứng dụng.',
      );
    }
    if (Platform.isWindows) return _extractWindows(path);
    final file = File('$path/database_helper');
    final bytes = await rootBundle.load(_asset);
    final payload = bytes.buffer.asUint8List(
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    // Always compare the packaged helper so application upgrades use the same migrations.
    bool same = false;
    if (await file.exists() && await file.length() == payload.length) {
      final existing = await file.readAsBytes();
      same = true;
      for (var i = 0; i < existing.length; i++) {
        if (existing[i] != payload[i]) {
          same = false;
          break;
        }
      }
    }
    if (!same) {
      final temporary = File('${file.path}.new');
      await temporary.writeAsBytes(payload, flush: true);
      await temporary.rename(file.path);
    }
    final permission = await Process.run('/bin/chmod', ['700', file.path]);
    if (permission.exitCode != 0) {
      throw const DatabaseSettingsException(
        'Chưa chuẩn bị được công cụ kết nối dữ liệu.',
      );
    }
    return file.path;
  }

  Future<String> _extractWindows(String path) async {
    final bytes = await rootBundle.load(_asset);
    final payload = bytes.buffer.asUint8List(
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    final digest = sha256.convert(payload).toString();
    final folder = Directory('$path\\database_helper_windows');
    final stamp = File('$path\\database_helper_windows.sha256');
    final current = await stamp.exists()
        ? (await stamp.readAsString()).trim()
        : '';
    final executable = File(
      '${folder.path}\\xemay_database_helper_windows.exe',
    );
    if (current != digest || !await executable.exists()) {
      if (await folder.exists()) await folder.delete(recursive: true);
      await folder.create(recursive: true);
      for (final entry in ZipDecoder().decodeBytes(payload)) {
        final name = entry.name.replaceAll('\\', '/');
        if (name.isEmpty || name.contains('..')) continue;
        final out = File('${folder.path}\\${name.replaceAll('/', '\\')}');
        if (!entry.isFile) {
          await Directory(out.path).create(recursive: true);
          continue;
        }
        await out.parent.create(recursive: true);
        final content = entry.content;
        await out.writeAsBytes(content, flush: true);
      }
      if (!await executable.exists()) {
        throw const DatabaseSettingsException(
          'Bộ công cụ Windows thiếu file chạy. Kiểm tra lại bản cài đặt.',
        );
      }
      await stamp.writeAsString('$digest\n', flush: true);
    }
    return executable.path;
  }

  Future<Map<String, dynamic>> _run(
    Map<String, dynamic> request, {
    void Function(String)? progress,
    Duration timeout = const Duration(seconds: 40),
  }) async {
    Process? process;
    StreamSubscription<String>? output;
    StreamSubscription<List<int>>? errors;
    File? requestFile;
    final response = Completer<Map<String, dynamic>>();
    try {
      final executable = await _prepare();
      if (Platform.isWindows) {
        requestFile = File(
          '${Directory.systemTemp.path}\\xemay-db-${DateTime.now().microsecondsSinceEpoch}.json',
        );
        await requestFile.writeAsString(jsonEncode(request), flush: true);
      }
      process = await Process.start(
        executable,
        requestFile == null ? const [] : [requestFile.path],
        workingDirectory: Platform.isWindows
            ? File(executable).parent.path
            : null,
        runInShell: false,
      );
      output = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              try {
                final item = jsonDecode(line) as Map<String, dynamic>;
                if (item['event'] == 'progress') {
                  progress?.call(item['message'] as String);
                } else if (item['event'] == 'result' && !response.isCompleted) {
                  response.complete(
                    Map<String, dynamic>.from(item['data'] as Map),
                  );
                } else if (item['event'] == 'error' && !response.isCompleted) {
                  final logFile = item['logFile'];
                  response.complete({
                    '__error':
                        '${item['message']}'
                        '${logFile is String ? '\nChi tiết lỗi: $logFile' : ''}',
                  });
                }
              } catch (_) {
                if (!response.isCompleted) {
                  response.complete({
                    '__error': 'Phản hồi từ công cụ dữ liệu không hợp lệ.',
                  });
                }
              }
            },
            onDone: () async {
              final exitCode = await process!.exitCode;
              if (!response.isCompleted) {
                response.complete({
                  '__error':
                      'Công cụ dữ liệu đã dừng (mã $exitCode). '
                      'Kiểm tra hoặc cập nhật bản cài đặt. Dữ liệu đang dùng được giữ nguyên.',
                });
              }
            },
            onError: (Object error) {
              if (!response.isCompleted) {
                response.complete({
                  '__error':
                      'Không đọc được phản hồi từ công cụ dữ liệu. '
                      'Kiểm tra hoặc cập nhật bản cài đặt.',
                });
              }
            },
          );
      // Do not expose native driver output: it may contain connection details.
      errors = process.stderr.listen((_) {});
      if (requestFile == null) {
        process.stdin.writeln(jsonEncode(request));
      }
      await process.stdin.close();
      final result = await response.future.timeout(timeout);
      if (result['__error'] is String) {
        throw DatabaseSettingsException(result['__error'] as String);
      }
      return result;
    } on DatabaseSettingsException {
      rethrow;
    } on TimeoutException {
      throw const DatabaseSettingsException(
        'Quá thời gian kết nối hoặc sao chép. Dữ liệu đang dùng được giữ nguyên.',
      );
    } catch (_) {
      throw const DatabaseSettingsException(
        'Chưa chạy được công cụ kết nối. Kiểm tra lại bản cài đặt ứng dụng.',
      );
    } finally {
      if (requestFile != null) {
        try {
          if (await requestFile.exists()) await requestFile.delete();
        } catch (_) {}
      }
      await output?.cancel();
      await errors?.cancel();
      process?.kill();
    }
  }

  @override
  Future<MongoInstallationStatus> checkMongo(String uri) async {
    final data = await _run({'command': 'probeMongo', 'mongoUri': uri});
    return MongoInstallationStatus(
      installed: data['installed'] == true,
      connected: data['connected'] == true,
      database: data['database'] as String?,
    );
  }

  @override
  Future<int> checkSql(String connection) async {
    final data = await _run({
      'command': 'probeSql',
      'sqlConnection': connection,
    });
    return (data['tables'] as num).toInt();
  }

  @override
  Future<DatabaseCloneResult> clone({
    required String mongoUri,
    required String sqlConnection,
    required void Function(String) progress,
  }) async {
    final path = await _channel.invokeMethod<String>('supportDirectory');
    final data = await _run(
      {
        'command': 'clone',
        'mongoUri': mongoUri,
        'sqlConnection': sqlConnection,
        'backupRoot': '$path/migration_backups',
      },
      progress: progress,
      timeout: const Duration(hours: 2),
    );
    final report = Map<String, dynamic>.from(data['report'] as Map);
    return DatabaseCloneResult(
      mongoUri: data['mongoUri'] as String,
      database: data['database'] as String,
      rows: (report['total_rows'] as num).toInt(),
      orphans: (report['orphan_count'] as num).toInt(),
      purchases: (report['purchases_merged'] as num).toInt(),
    );
  }

  @override
  Future<CloudComparison> compareCloud({
    required String sourceUri,
    required String targetUri,
    void Function(String)? progress,
  }) async {
    await _ensureCloudSupport();
    return CloudComparison.fromJson(
      await _run(
        {
          'command': 'compareCloud',
          'sourceUri': sourceUri,
          'targetUri': targetUri,
        },
        progress: progress,
        timeout: const Duration(seconds: 195),
      ),
    );
  }

  @override
  Future<CloudSyncResult> syncCloud({
    required String sourceUri,
    required String targetUri,
    required String expectedSourceVersion,
    required String expectedTargetVersion,
    required String conflictPolicy,
    required void Function(String) progress,
  }) async {
    await _ensureCloudSupport();
    final data = await _run(
      {
        'command': 'syncCloud',
        'sourceUri': sourceUri,
        'targetUri': targetUri,
        'expectedSourceVersion': expectedSourceVersion,
        'expectedTargetVersion': expectedTargetVersion,
        'conflictPolicy': conflictPolicy,
      },
      progress: progress,
      timeout: const Duration(hours: 2),
    );
    return CloudSyncResult(
      mongoUri: data['mongoUri'] as String,
      database: data['database'] as String,
      sourceMongoUri: data['sourceMongoUri'] as String?,
      rows: (data['rows'] as num).toInt(),
      collections: (data['collections'] as num).toInt(),
      version: data['version'] is Map
          ? DatabaseVersion.fromJson(
              Map<String, dynamic>.from(data['version'] as Map),
            )
          : null,
    );
  }

  @override
  Future<void> openMongoInstallation() =>
      _channel.invokeMethod<void>('openMongoInstallation');
}
