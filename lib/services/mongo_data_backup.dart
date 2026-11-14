import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'package:mongo_dart/mongo_dart.dart';

import '../models/settings/database_settings.dart';

/// Full copy of the database the app is using, stored as a zip of BSON documents.
class MongoDataBackup {
  static const _format = 1;
  static const _optionKeys = [
    'validator',
    'validationLevel',
    'validationAction',
    'viewOn',
    'pipeline',
    'capped',
    'size',
    'max',
  ];

  static Future<MongoBackupResult> exportToFile({
    required String mongoUri,
    required String path,
    void Function(String)? progress,
  }) async {
    final db = await _open(mongoUri);
    try {
      final entries = await _readDatabase(db, progress);
      _writeArchive(path, db.databaseName ?? '', entries);
      return MongoBackupResult(
        database: db.databaseName ?? '',
        collections: entries.length,
        rows: entries.fold<int>(
          0,
          (sum, entry) => sum + entry.documents.length,
        ),
      );
    } on DatabaseSettingsException {
      rethrow;
    } catch (_) {
      throw const DatabaseSettingsException(
        'Chưa sao lưu được dữ liệu. Kiểm tra MongoDB và thử lại.',
      );
    } finally {
      await db.close();
    }
  }

  static Future<MongoBackupResult> exportToDirectory({
    required String mongoUri,
    required String directory,
    DateTime? now,
    void Function(String)? progress,
  }) async {
    final folder = Directory(directory.trim());
    if (directory.trim().isEmpty || !await folder.exists()) {
      throw const DatabaseSettingsException(
        'Không tìm thấy thư mục lưu bản sao lưu.',
      );
    }
    final stamp = DateFormat('yyyyMMdd_HHmm').format(now ?? DateTime.now());
    final path = _join(folder.path, 'SaoLuu_$stamp.zip');
    final result = await exportToFile(
      mongoUri: mongoUri,
      path: path,
      progress: progress,
    );
    _deleteOlderBackups(folder.path, path);
    return result;
  }

  static String _join(String directory, String name) {
    final separator = Platform.pathSeparator;
    final root =
        directory.endsWith('/') ||
            directory.endsWith('\\') ||
            directory.endsWith(separator)
        ? directory.substring(0, directory.length - 1)
        : directory;
    return '$root$separator$name';
  }

  static String _baseName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    return slash < 0 ? normalized : normalized.substring(slash + 1);
  }

  static void _deleteOlderBackups(String directory, String keepPath) {
    final keep = File(keepPath).absolute.path;
    final List<FileSystemEntity> entries;
    try {
      entries = Directory(directory).listSync(followLinks: false);
    } catch (_) {
      return;
    }
    for (final entity in entries) {
      if (entity is! File) continue;
      final name = _baseName(entity.path);
      final backup =
          name.startsWith('SaoLuu_') &&
          (name.toLowerCase().endsWith('.zip') ||
              name.toLowerCase().endsWith('.zip.part'));
      if (!backup || entity.absolute.path == keep) continue;
      try {
        entity.deleteSync();
      } catch (_) {}
    }
  }

  static Future<MongoBackupResult> importFromFile({
    required String mongoUri,
    required String path,
    void Function(String)? progress,
  }) async {
    final entries = _readArchive(path);
    final db = await _open(mongoUri);
    var started = false;
    try {
      await db.collection('_sync_state').updateOne(
        {'_id': 'journal'},
        {
          r'$set': {'needsFullScan': true},
        },
        upsert: true,
      );
      await _replace(db, entries, progress, () => started = true);
      return MongoBackupResult(
        database: db.databaseName ?? '',
        collections: entries.length,
        rows: entries.fold<int>(
          0,
          (sum, entry) => sum + entry.documents.length,
        ),
      );
    } on DatabaseSettingsException {
      rethrow;
    } catch (_) {
      throw DatabaseSettingsException(
        started
            ? 'Khôi phục chưa xong. Hãy chạy lại từ bản sao lưu.'
            : 'Chưa khôi phục được dữ liệu. Kiểm tra MongoDB và thử lại.',
      );
    } finally {
      await db.close();
    }
  }

  static Future<Db> _open(String uri) async {
    try {
      final db = await Db.create(uri);
      await db.open();
      return db;
    } catch (_) {
      throw const DatabaseSettingsException(
        'Chưa kết nối được MongoDB. Kiểm tra dịch vụ và chuỗi kết nối.',
      );
    }
  }

  static Future<List<_Entry>> _readDatabase(
    Db db,
    void Function(String)? progress,
  ) async {
    final infos = await db.getCollectionInfos();
    final entries = <_Entry>[];
    final names = <String>{};
    for (final info in infos) {
      final name = info['name'];
      final type = info['type'] == 'view' ? 'view' : 'collection';
      if (name is! String || name.startsWith('system.') || !names.add(name)) {
        continue;
      }
      progress?.call('Đang sao lưu $name');
      final rawOptions = info['options'];
      final options = <String, dynamic>{};
      if (rawOptions is Map) {
        for (final key in _optionKeys) {
          if (rawOptions[key] != null) options[key] = rawOptions[key];
        }
      }
      final indexes = <Map<String, dynamic>>[];
      if (type != 'view') {
        for (final index in await db.collection(name).getIndexes()) {
          if (index['name'] == '_id_') continue;
          final spec = <String, dynamic>{};
          index.forEach((key, value) {
            if (key == 'v' || key == 'ns' || value == null) return;
            spec[key] = value;
          });
          if (spec['key'] is Map && spec['name'] is String) indexes.add(spec);
        }
      }
      final documents = type == 'view'
          ? <Map<String, dynamic>>[]
          : await _documents(db, name);
      entries.add(
        _Entry(
          name: name,
          type: type,
          options: options,
          indexes: indexes,
          documents: documents,
        ),
      );
    }
    entries.sort(
      (a, b) => (a.type == 'view' ? 1 : 0).compareTo(b.type == 'view' ? 1 : 0),
    );
    return entries;
  }

  static Future<List<Map<String, dynamic>>> _documents(
    Db db,
    String name,
  ) async {
    final documents = <Map<String, dynamic>>[];
    await for (final document in db.collection(name).find()) {
      documents.add(Map<String, dynamic>.from(document));
    }
    return documents;
  }

  static void _writeArchive(
    String path,
    String database,
    List<_Entry> entries,
  ) {
    final archive = Archive();
    archive.addFile(
      ArchiveFile.string(
        'manifest.json',
        jsonEncode({
          'format': _format,
          'database': database,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'count': entries.length,
        }),
      ),
    );
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      archive.addFile(
        ArchiveFile.bytes(
          'entries/$i.meta.bson',
          _encodeOne({
            'name': entry.name,
            'type': entry.type,
            'options': entry.options,
            'indexes': entry.indexes,
          }),
        ),
      );
      archive.addFile(
        ArchiveFile.bytes('entries/$i.bson', _encodeMany(entry.documents)),
      );
    }
    final part = File('$path.part');
    try {
      part.parent.createSync(recursive: true);
      part.writeAsBytesSync(ZipEncoder().encode(archive), flush: true);
      final target = File(path);
      if (target.existsSync()) target.deleteSync();
      part.renameSync(target.path);
    } on DatabaseSettingsException {
      rethrow;
    } catch (_) {
      if (part.existsSync()) part.deleteSync();
      throw const DatabaseSettingsException('Không ghi được file sao lưu.');
    }
  }

  static List<_Entry> _readArchive(String path) {
    Uint8List bytes;
    try {
      bytes = File(path).readAsBytesSync();
    } catch (_) {
      throw const DatabaseSettingsException('Không đọc được file sao lưu.');
    }
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const DatabaseSettingsException(
        'File không phải bản sao lưu dữ liệu của ứng dụng.',
      );
    }
    final manifestFile = archive.findFile('manifest.json');
    if (manifestFile == null) {
      throw const DatabaseSettingsException(
        'File không phải bản sao lưu dữ liệu của ứng dụng.',
      );
    }
    final Object? manifest;
    try {
      manifest = jsonDecode(utf8.decode(manifestFile.content));
    } catch (_) {
      throw const DatabaseSettingsException('Bản sao lưu bị hỏng.');
    }
    if (manifest is! Map || manifest['format'] != _format) {
      throw const DatabaseSettingsException(
        'File không phải bản sao lưu dữ liệu của ứng dụng.',
      );
    }
    final count = manifest['count'];
    if (count is! int || count < 0) {
      throw const DatabaseSettingsException('Bản sao lưu bị hỏng.');
    }
    final entries = <_Entry>[];
    final names = <String>{};
    for (var i = 0; i < count; i++) {
      final metaFile = archive.findFile('entries/$i.meta.bson');
      final dataFile = archive.findFile('entries/$i.bson');
      if (metaFile == null || dataFile == null) {
        throw const DatabaseSettingsException('Bản sao lưu bị hỏng.');
      }
      final meta = _decodeOne(metaFile.content);
      final name = meta['name'];
      final type = meta['type'] == 'view' ? 'view' : 'collection';
      if (name is! String ||
          name.isEmpty ||
          name.startsWith('system.') ||
          !names.add(name)) {
        throw const DatabaseSettingsException('Bản sao lưu bị hỏng.');
      }
      final options = meta['options'] is Map
          ? Map<String, dynamic>.from(meta['options'] as Map)
          : <String, dynamic>{};
      final indexes = <Map<String, dynamic>>[];
      if (meta['indexes'] is List) {
        for (final index in meta['indexes'] as List) {
          if (index is! Map ||
              index['name'] == '_id_' ||
              index['key'] is! Map) {
            continue;
          }
          indexes.add(Map<String, dynamic>.from(index));
        }
      }
      entries.add(
        _Entry(
          name: name,
          type: type,
          options: options,
          indexes: indexes,
          documents: type == 'view' ? const [] : _decodeAll(dataFile.content),
        ),
      );
    }
    return entries;
  }

  static Future<void> _replace(
    Db db,
    List<_Entry> entries,
    void Function(String)? progress,
    void Function() onMutate,
  ) async {
    final existing = <Map<String, dynamic>>[];
    for (final info in await db.getCollectionInfos()) {
      final name = info['name'];
      if (name is! String || name.startsWith('system.')) continue;
      existing.add(info);
    }
    existing.sort(
      (a, b) =>
          (a['type'] == 'view' ? 0 : 1).compareTo(b['type'] == 'view' ? 0 : 1),
    );
    for (final info in existing) {
      onMutate();
      final dropped = await db.dropCollection(info['name'] as String);
      if (!dropped) {
        throw DatabaseSettingsException(
          'Không xóa được dữ liệu cũ của ${info['name']}.',
        );
      }
    }
    for (final entry in entries.where((entry) => entry.type != 'view')) {
      onMutate();
      progress?.call('Đang khôi phục ${entry.name}');
      await _create(db, entry);
      await _insert(db, entry);
      for (final index in entry.indexes) {
        await _createIndex(db, entry.name, index);
      }
    }
    for (final entry in entries.where((entry) => entry.type == 'view')) {
      onMutate();
      progress?.call('Đang khôi phục ${entry.name}');
      await _create(db, entry);
    }
  }

  static Future<void> _create(Db db, _Entry entry) async {
    if (entry.type == 'view') {
      final source = entry.options['viewOn'];
      final pipeline = entry.options['pipeline'];
      if (source is! String || pipeline is! List) {
        throw const DatabaseSettingsException('Bản sao lưu bị hỏng.');
      }
      _checkOk(
        await db.createView(entry.name, source, pipeline),
        'Không tạo lại được ${entry.name}.',
      );
      return;
    }
    final options = entry.options;
    final capped = options['capped'] == true && options['size'] is num;
    _checkOk(
      await db.createCollection(
        entry.name,
        createCollectionOptions: CreateCollectionOptions(
          validator: options['validator'] is Map
              ? Map<String, dynamic>.from(options['validator'] as Map)
              : null,
          validationLevel: options['validationLevel'] is String
              ? options['validationLevel'] as String
              : null,
          validationAction: options['validationAction'] is String
              ? options['validationAction'] as String
              : null,
          capped: capped,
          size: capped ? (options['size'] as num).toInt() : null,
          max: options['max'] is num ? (options['max'] as num).toInt() : null,
        ),
      ),
      'Không tạo lại được ${entry.name}.',
    );
  }

  static Future<void> _insert(Db db, _Entry entry) async {
    const batchSize = 200;
    final collection = db.collection(entry.name);
    for (var start = 0; start < entry.documents.length; start += batchSize) {
      final end = start + batchSize > entry.documents.length
          ? entry.documents.length
          : start + batchSize;
      await collection.insertMany(
        entry.documents.sublist(start, end),
        bypassDocumentValidation: true,
      );
    }
  }

  static Future<void> _createIndex(
    Db db,
    String collection,
    Map<String, dynamic> spec,
  ) async {
    final index = <String, Object>{};
    spec.forEach((key, value) {
      if (value != null) index[key] = value as Object;
    });
    _checkOk(
      await db.runCommand(<String, Object>{
        'createIndexes': collection,
        'indexes': <Object>[index],
      }),
      'Không tạo lại được chỉ mục ${spec['name']}.',
    );
  }

  static void _checkOk(Map<String, dynamic> result, String message) {
    final ok = result['ok'];
    if (ok != 1 && ok != 1.0) throw DatabaseSettingsException(message);
  }

  static Uint8List _encodeMany(List<Map<String, dynamic>> documents) {
    final parts = documents.map(_encodeOne).toList();
    final out = Uint8List(parts.fold<int>(0, (sum, part) => sum + part.length));
    var offset = 0;
    for (final part in parts) {
      out.setRange(offset, offset + part.length, part);
      offset += part.length;
    }
    return out;
  }

  static Uint8List _encodeOne(Map<String, dynamic> document) =>
      Uint8List.fromList(BsonCodec.serialize(document).byteList);

  static List<Map<String, dynamic>> _decodeAll(Uint8List bytes) {
    final documents = <Map<String, dynamic>>[];
    final data = ByteData.sublistView(bytes);
    var offset = 0;
    while (offset < bytes.length) {
      if (bytes.length - offset < 5) {
        throw const DatabaseSettingsException('Bản sao lưu bị hỏng.');
      }
      final length = data.getInt32(offset, Endian.little);
      if (length < 5 || offset + length > bytes.length) {
        throw const DatabaseSettingsException('Bản sao lưu bị hỏng.');
      }
      documents.add(
        _decodeOne(Uint8List.sublistView(bytes, offset, offset + length)),
      );
      offset += length;
    }
    return documents;
  }

  static Map<String, dynamic> _decodeOne(Uint8List bytes) {
    try {
      return BsonCodec.deserialize(BsonBinary.from(bytes));
    } catch (_) {
      throw const DatabaseSettingsException('Bản sao lưu bị hỏng.');
    }
  }
}

class _Entry {
  const _Entry({
    required this.name,
    required this.type,
    required this.options,
    required this.indexes,
    required this.documents,
  });
  final String name, type;
  final Map<String, dynamic> options;
  final List<Map<String, dynamic>> indexes, documents;
}
