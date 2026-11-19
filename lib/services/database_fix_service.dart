import 'dart:convert';

import 'package:mongo_dart/mongo_dart.dart';

import '../core/config/database_config.dart';
import 'mongo_sync_journal.dart';

/// Raised when a repair script cannot be parsed or points at the wrong data.
class DatabaseFixFormatException implements Exception {
  const DatabaseFixFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

enum DatabaseFixAction { update, delete, insert }

class DatabaseFixOperation {
  const DatabaseFixOperation({
    required this.number,
    required this.collection,
    required this.action,
    required this.filter,
    this.update,
    this.insert,
    this.many = false,
    this.upsert = false,
    this.note,
  });
  final int number;
  final String collection;
  final DatabaseFixAction action;
  final Map<String, dynamic> filter;
  final Map<String, dynamic>? update;
  final Map<String, dynamic>? insert;
  final bool many, upsert;
  final String? note;
}

class DatabaseFixPlan {
  const DatabaseFixPlan({
    required this.operations,
    this.description,
    this.command,
  });
  final List<DatabaseFixOperation> operations;
  final String? description;

  /// Built-in command name, e.g. `stuck-orders`. A command plan has no
  /// operations; the tab runs the matching scanner/repair instead.
  final String? command;

  bool get isStuckOrders => command == 'stuck-orders';
}

class DatabaseFixPreviewStep {
  const DatabaseFixPreviewStep({
    required this.index,
    required this.collection,
    required this.action,
    required this.matched,
    this.sample,
    this.warning,
    this.note,
  });
  final int index;
  final String collection;
  final DatabaseFixAction action;
  final int matched;
  final String? sample, warning, note;
}

class DatabaseFixPreview {
  const DatabaseFixPreview({
    required this.steps,
    this.description,
    this.warning,
  });
  final List<DatabaseFixPreviewStep> steps;
  final String? description, warning;
}

class DatabaseFixStepResult {
  const DatabaseFixStepResult({
    required this.index,
    required this.collection,
    required this.action,
    required this.ok,
    this.matched = 0,
    this.modified = 0,
    this.upserted = 0,
    this.inserted = 0,
    this.removed = 0,
    this.error,
    this.note,
  });
  final int index;
  final String collection;
  final DatabaseFixAction action;
  final bool ok;
  final int matched, modified, upserted, inserted, removed;
  final String? error, note;

  bool get changed => modified + upserted + inserted + removed > 0;
}

class DatabaseFixRun {
  const DatabaseFixRun({
    required this.ok,
    required this.steps,
    required this.duration,
    this.failedStep,
    this.historyError,
    this.wrote = false,
  });
  final bool ok;
  final List<DatabaseFixStepResult> steps;
  final Duration duration;
  final int? failedStep;
  final String? historyError;
  final bool wrote;
}

abstract class DatabaseFixRunner {
  Future<DatabaseFixPreview> preview(DatabaseFixPlan plan);
  Future<DatabaseFixRun> execute(
    DatabaseFixPlan plan, {
    required String script,
  });
  Future<void> close();
}

/// Runs JSON repair scripts against the active MongoDB database.
///
/// Supported script shape (a single operation object is accepted too):
/// ```json
/// [
///   {
///     "collection": "HoaDonBan",
///     "filter": {"IdHoaDon": 142},
///     "update": {"$set": {"SoTienKhachDua": 0}},
///     "many": false,
///     "note": "Sửa tiền khách đưa"
///   }
/// ]
/// ```
/// Use `delete: true` to remove and `insert: {...}` to add a document.
/// `{"$date": "2026-11-19T00:00:00Z"}` and `{"$oid": "..."}` are accepted.
class DatabaseFixService implements DatabaseFixRunner {
  DatabaseFixService(this.db, this.connect);
  factory DatabaseFixService.local() {
    final db = SyncTrackedDb(DatabaseConfig.mongoUri);
    return DatabaseFixService(db, () async {
      if (!db.isConnected) await db.open(writeConcern: WriteConcern.journaled);
    });
  }

  static const maxOperations = 500;
  static const maxScriptLength = 1024 * 1024;
  static const _blocked = {
    '_sync_changes',
    '_sync_state',
    '_app_sync_meta',
    '_fix_history',
  };
  static const _updateOperators = {r'$set', r'$unset', r'$inc'};

  final Db db;
  final Future<void> Function() connect;

  @override
  Future<void> close() async {
    if (db.isConnected) await db.close();
  }

  static DatabaseFixPlan parse(String script) {
    if (script.trim().isEmpty) {
      throw const DatabaseFixFormatException('Chưa có lệnh nào để chạy.');
    }
    if (script.length > maxScriptLength) {
      throw const DatabaseFixFormatException('Tệp lệnh quá lớn (tối đa 1 MB).');
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(script);
    } on FormatException catch (error) {
      final (line, column) = _position(script, error.offset);
      throw DatabaseFixFormatException(
        'JSON không hợp lệ tại dòng $line, cột $column: ${error.message}',
      );
    }
    String? description;
    dynamic rawOperations;
    if (decoded is List && decoded.length == 1 && decoded.first is Map) {
      final command = _command(decoded.first as Map);
      if (command != null) {
        return DatabaseFixPlan(
          operations: const [],
          description: _description(decoded.first as Map),
          command: command,
        );
      }
    }
    if (decoded is List) {
      rawOperations = decoded;
    } else if (decoded is Map) {
      final command = _command(decoded);
      if (command != null) {
        return DatabaseFixPlan(
          operations: const [],
          description: _description(decoded),
          command: command,
        );
      }
      if (decoded.containsKey('operations')) {
        rawOperations = decoded['operations'];
        final rawDescription = decoded['description'];
        if (rawDescription is String && rawDescription.trim().isNotEmpty) {
          description = rawDescription.trim();
          if (description.length > 500) {
            throw const DatabaseFixFormatException(
              '"description" quá dài (tối đa 500 ký tự).',
            );
          }
        }
      } else {
        rawOperations = [decoded];
      }
    } else {
      throw const DatabaseFixFormatException(
        'Nội dung phải là một mảng lệnh hoặc một lệnh đơn lẻ.',
      );
    }
    if (rawOperations is! List) {
      throw const DatabaseFixFormatException('"operations" phải là một mảng.');
    }
    if (rawOperations.isEmpty) {
      throw const DatabaseFixFormatException('Chưa có lệnh nào để chạy.');
    }
    if (rawOperations.length > maxOperations) {
      throw const DatabaseFixFormatException(
        'Chỉ chạy tối đa $maxOperations lệnh mỗi lần.',
      );
    }
    final operations = <DatabaseFixOperation>[
      for (var index = 0; index < rawOperations.length; index++)
        _operation(rawOperations[index], index + 1),
    ];
    return DatabaseFixPlan(operations: operations, description: description);
  }

  /// Recognizes the scan/repair command file:
  /// `{"select": {"command": "stuck-orders"},
  ///   "apply": {"command": "repair-stuck-orders"}}`
  static String? _command(Map raw) {
    String? name(dynamic value) => value is Map && value['command'] is String
        ? value['command'] as String
        : null;
    final direct = raw['command'];
    final select = name(raw['select']);
    final apply = name(raw['apply']);
    if (direct != null && direct != 'stuck-orders') {
      throw DatabaseFixFormatException(
        'Lệnh "$direct" không được hỗ trợ (chỉ có stuck-orders).',
      );
    }
    if (select != null && select != 'stuck-orders') {
      throw DatabaseFixFormatException(
        'Lệnh select "$select" không được hỗ trợ (chỉ có stuck-orders).',
      );
    }
    if (apply != null &&
        apply != 'repair-stuck-orders' &&
        apply != 'stuck-orders') {
      throw DatabaseFixFormatException(
        'Lệnh apply "$apply" không được hỗ trợ (chỉ có repair-stuck-orders).',
      );
    }
    if (direct == 'stuck-orders' ||
        select == 'stuck-orders' ||
        apply == 'repair-stuck-orders' ||
        apply == 'stuck-orders') {
      return 'stuck-orders';
    }
    if (raw.containsKey('select') || raw.containsKey('apply')) {
      throw const DatabaseFixFormatException(
        'Cần "select.command": "stuck-orders" và/hoặc '
        '"apply.command": "repair-stuck-orders".',
      );
    }
    return null;
  }

  static String? _description(Map raw) {
    final value = raw['description'];
    if (value is String && value.trim().isNotEmpty) {
      if (value.trim().length > 500) {
        throw const DatabaseFixFormatException(
          '"description" quá dài (tối đa 500 ký tự).',
        );
      }
      return value.trim();
    }
    return null;
  }

  static (int, int) _position(String source, int? offset) {
    if (offset == null) return (1, 1);
    var line = 1, column = 1;
    for (var index = 0; index < offset && index < source.length; index++) {
      if (source.codeUnitAt(index) == 10) {
        line++;
        column = 1;
      } else {
        column++;
      }
    }
    return (line, column);
  }

  static DatabaseFixOperation _operation(dynamic raw, int number) {
    final label = 'Lệnh #$number: ';
    String prefix(String message) => '$label$message';
    if (raw is! Map) {
      throw DatabaseFixFormatException(prefix('mỗi lệnh phải là một object.'));
    }
    final collection = raw['collection'];
    if (collection is! String || collection.trim().isEmpty) {
      throw DatabaseFixFormatException(prefix('thiếu "collection".'));
    }
    final name = collection.trim();
    if (name.contains('.') ||
        name.contains(r'$') ||
        name.startsWith('system.') ||
        _blocked.contains(name)) {
      throw DatabaseFixFormatException(
        prefix('collection "$name" không được phép sửa.'),
      );
    }
    bool flag(String key) {
      final value = raw[key];
      if (value == null) return false;
      if (value is! bool) {
        throw DatabaseFixFormatException(prefix('"$key" phải là true/false.'));
      }
      return value;
    }

    final many = flag('many'), upsert = flag('upsert');
    final hasInsert = raw.containsKey('insert');
    final hasUpdate = raw.containsKey('update');
    final delete = raw['delete'];
    if (delete != null && delete is! bool) {
      throw DatabaseFixFormatException(prefix('"delete" phải là true/false.'));
    }
    final modes = [hasInsert, hasUpdate, delete == true].where((e) => e).length;
    if (modes != 1) {
      throw DatabaseFixFormatException(
        prefix('cần đúng một trong "update", "delete", "insert".'),
      );
    }
    final filterValues = raw['filter'] ?? const <String, dynamic>{};
    if (filterValues is! Map) {
      throw DatabaseFixFormatException(prefix('"filter" phải là một object.'));
    }
    final filter = _convertMap(filterValues, label);
    final note = raw['note'];
    if (note != null && note is! String) {
      throw DatabaseFixFormatException(prefix('"note" phải là chuỗi.'));
    }
    final normalizedNote = note is String && note.trim().isNotEmpty
        ? (note.trim().length > 200
              ? note.trim().substring(0, 200)
              : note.trim())
        : null;
    if (hasInsert) {
      if (filter.isNotEmpty) {
        throw DatabaseFixFormatException(
          prefix('lệnh "insert" không dùng "filter".'),
        );
      }
      if (many || upsert) {
        throw DatabaseFixFormatException(
          prefix('lệnh "insert" không dùng "many"/"upsert".'),
        );
      }
      final document = raw['insert'];
      if (document is! Map || document.isEmpty) {
        throw DatabaseFixFormatException(
          prefix('"insert" phải là một document không rỗng.'),
        );
      }
      return DatabaseFixOperation(
        number: number,
        collection: name,
        action: DatabaseFixAction.insert,
        filter: const {},
        insert: _convertMap(document, label),
        note: normalizedNote,
      );
    }
    if (filter.isEmpty) {
      throw DatabaseFixFormatException(
        prefix(
          'cần "filter" cụ thể; không cho phép sửa/xóa toàn bộ collection.',
        ),
      );
    }
    if (delete == true) {
      if (upsert) {
        throw DatabaseFixFormatException(
          prefix('lệnh "delete" không dùng "upsert".'),
        );
      }
      return DatabaseFixOperation(
        number: number,
        collection: name,
        action: DatabaseFixAction.delete,
        filter: filter,
        many: many,
        note: normalizedNote,
      );
    }
    final updateValues = raw['update'];
    if (updateValues is! Map || updateValues.isEmpty) {
      throw DatabaseFixFormatException(
        prefix('"update" phải là object chứa \$set, \$unset hoặc \$inc.'),
      );
    }
    final update = <String, dynamic>{};
    for (final entry in updateValues.entries) {
      final operator = entry.key;
      if (!_updateOperators.contains(operator)) {
        throw DatabaseFixFormatException(
          prefix(
            'toán tử "$operator" không được hỗ trợ (chỉ \$set, \$unset, \$inc).',
          ),
        );
      }
      final values = entry.value;
      if (values is! Map || values.isEmpty) {
        throw DatabaseFixFormatException(
          prefix('"$operator" phải là object không rỗng.'),
        );
      }
      final fields = _convertMap(values, label);
      for (final field in fields.keys) {
        if (field.isEmpty || field == '_id' || field.startsWith(r'$')) {
          throw DatabaseFixFormatException(
            prefix('tên trường "$field" không được sửa.'),
          );
        }
        if (operator == r'$inc' && fields[field] is! num) {
          throw DatabaseFixFormatException(
            prefix('"\$inc.$field" phải là số.'),
          );
        }
      }
      update[operator] = fields;
    }
    return DatabaseFixOperation(
      number: number,
      collection: name,
      action: DatabaseFixAction.update,
      filter: filter,
      update: update,
      many: many,
      upsert: upsert,
      note: normalizedNote,
    );
  }

  static Map<String, dynamic> _convertMap(Map raw, String prefix) => {
    for (final entry in raw.entries)
      '${entry.key}': _convertValue(entry.value, prefix, '${entry.key}'),
  };

  static dynamic _convertValue(dynamic value, String prefix, String path) {
    if (value is Map) {
      if (value.length == 1 && value.containsKey(r'$date')) {
        final raw = value[r'$date'];
        if (raw is num) {
          final milliseconds = raw.toInt();
          if (milliseconds.abs() > 8640000000000000) {
            throw DatabaseFixFormatException(
              '$prefix"$path" có \$date ngoài phạm vi cho phép.',
            );
          }
          return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
        }
        final parsed = raw is String ? DateTime.tryParse(raw) : null;
        if (parsed == null) {
          throw DatabaseFixFormatException(
            '$prefix"$path" có \$date không hợp lệ (dùng ISO 8601 hoặc số ms).',
          );
        }
        return parsed.toUtc();
      }
      if (value.length == 1 && value.containsKey(r'$oid')) {
        final raw = value[r'$oid'];
        final id = raw is String ? ObjectId.tryParse(raw) : null;
        if (id == null) {
          throw DatabaseFixFormatException(
            '$prefix"$path" có \$oid không hợp lệ (cần 24 ký tự hex).',
          );
        }
        return id;
      }
      return {
        for (final entry in value.entries)
          '${entry.key}': _convertValue(
            entry.value,
            prefix,
            '$path.${entry.key}',
          ),
      };
    }
    if (value is List) {
      return [
        for (var index = 0; index < value.length; index++)
          _convertValue(value[index], prefix, '$path[$index]'),
      ];
    }
    return value;
  }

  Future<Set<String>> _collections() async {
    final names = await db.getCollectionNames();
    return {
      for (final name in names)
        if (name != null && name.isNotEmpty) name,
    };
  }

  @override
  Future<DatabaseFixPreview> preview(DatabaseFixPlan plan) async {
    await connect();
    final names = await _collections();
    final steps = <DatabaseFixPreviewStep>[];
    String? warning;
    try {
      final pending = await db.collection('_record_changes').count({
        'State': {
          r'$in': ['pending', 'preparing'],
        },
      });
      if (pending > 0) {
        warning =
            'Đang có $pending thay đổi sửa/xóa dở dang. Hãy xử lý xong trước khi chạy lệnh sửa trực tiếp.';
      }
    } catch (_) {
      // The journal collection does not exist yet.
    }
    for (final operation in plan.operations) {
      if (!names.contains(operation.collection)) {
        throw DatabaseFixFormatException(
          'Lệnh #${operation.number}: không tìm thấy collection "${operation.collection}".',
        );
      }
      final collection = db.collection(operation.collection);
      final notes = <String>[
        if (operation.collection.startsWith('_record_'))
          'Collection nội bộ của cơ chế sửa/xóa — kiểm tra kỹ.',
      ];
      if (operation.action == DatabaseFixAction.insert) {
        final document = operation.insert!;
        final id = document['_id'];
        if (id != null) {
          final exists = await collection.count({'_id': id}) > 0;
          if (exists) notes.add('Đã có bản ghi cùng _id; lệnh chèn sẽ lỗi.');
        }
        steps.add(
          DatabaseFixPreviewStep(
            index: operation.number,
            collection: operation.collection,
            action: operation.action,
            matched: 0,
            sample: _sample(document),
            warning: notes.isEmpty ? null : notes.join(' '),
            note: operation.note,
          ),
        );
        continue;
      }
      final matched = await collection.count(operation.filter);
      final documents = await collection
          .modernFind(filter: operation.filter, limit: 3)
          .toList();
      if (matched == 0) {
        notes.add('Không có bản ghi nào khớp filter.');
      } else if (!operation.many && matched > 1) {
        notes.add(
          'Chỉ áp dụng cho 1 bản ghi; đặt "many": true để áp dụng cho tất cả $matched bản ghi.',
        );
      } else if (operation.many && matched > 20) {
        notes.add('Sẽ áp dụng cho $matched bản ghi.');
      }
      steps.add(
        DatabaseFixPreviewStep(
          index: operation.number,
          collection: operation.collection,
          action: operation.action,
          matched: matched,
          sample: documents.isEmpty ? null : _sample(documents.first),
          warning: notes.isEmpty ? null : notes.join(' '),
          note: operation.note,
        ),
      );
    }
    return DatabaseFixPreview(
      steps: steps,
      description: plan.description,
      warning: warning,
    );
  }

  @override
  Future<DatabaseFixRun> execute(
    DatabaseFixPlan plan, {
    required String script,
  }) async {
    await connect();
    final names = await _collections();
    final clock = Stopwatch()..start();
    final steps = <DatabaseFixStepResult>[];
    int? failedStep;
    for (final operation in plan.operations) {
      if (!names.contains(operation.collection)) {
        failedStep = operation.number;
        steps.add(
          DatabaseFixStepResult(
            index: operation.number,
            collection: operation.collection,
            action: operation.action,
            ok: false,
            error: 'Không tìm thấy collection "${operation.collection}".',
            note: operation.note,
          ),
        );
        break;
      }
      try {
        final collection = db.collection(operation.collection);
        late final WriteResult result;
        switch (operation.action) {
          case DatabaseFixAction.update:
            result = operation.many
                ? await collection.updateMany(
                    operation.filter,
                    operation.update!,
                    upsert: operation.upsert,
                  )
                : await collection.updateOne(
                    operation.filter,
                    operation.update!,
                    upsert: operation.upsert,
                  );
            final error = _writeError(result);
            steps.add(
              DatabaseFixStepResult(
                index: operation.number,
                collection: operation.collection,
                action: operation.action,
                ok: error == null,
                matched: result.nMatched,
                modified: result.nModified,
                upserted: result.nUpserted,
                error: error,
                note: operation.note,
              ),
            );
          case DatabaseFixAction.delete:
            result = operation.many
                ? await collection.deleteMany(operation.filter)
                : await collection.deleteOne(operation.filter);
            final error = _writeError(result);
            steps.add(
              DatabaseFixStepResult(
                index: operation.number,
                collection: operation.collection,
                action: operation.action,
                ok: error == null,
                removed: result.nRemoved,
                error: error,
                note: operation.note,
              ),
            );
          case DatabaseFixAction.insert:
            result = await collection.insertOne(operation.insert!);
            final error = _writeError(result);
            steps.add(
              DatabaseFixStepResult(
                index: operation.number,
                collection: operation.collection,
                action: operation.action,
                ok: error == null,
                inserted: result.nInserted,
                error: error,
                note: operation.note,
              ),
            );
        }
        if (!steps.last.ok) {
          failedStep = operation.number;
          break;
        }
      } catch (error) {
        failedStep = operation.number;
        steps.add(
          DatabaseFixStepResult(
            index: operation.number,
            collection: operation.collection,
            action: operation.action,
            ok: false,
            error: '$error',
            note: operation.note,
          ),
        );
        break;
      }
    }
    clock.stop();
    final wrote = steps.any((step) => step.changed);
    final ok = failedStep == null;
    String? historyError;
    try {
      await db.collection('_fix_history').insertOne({
        '_id': ObjectId(),
        'Date': DateTime.now().toUtc(),
        'Ok': ok,
        'Description': plan.description,
        'Operations': plan.operations.length,
        'Executed': steps.length,
        'Script': script.length > 100000
            ? '${script.substring(0, 100000)}\n…'
            : script,
        'Results': [
          for (final step in steps)
            {
              'Index': step.index,
              'Collection': step.collection,
              'Action': step.action.name,
              'Ok': step.ok,
              'Matched': step.matched,
              'Modified': step.modified,
              'Upserted': step.upserted,
              'Inserted': step.inserted,
              'Removed': step.removed,
              if (step.error != null) 'Error': step.error,
            },
        ],
      });
    } catch (error) {
      historyError = '$error';
    }
    return DatabaseFixRun(
      ok: ok,
      steps: steps,
      duration: clock.elapsed,
      failedStep: failedStep,
      historyError: historyError,
      wrote: wrote,
    );
  }

  static String? _writeError(WriteResult result) {
    if (result.isSuccess && !result.hasWriteErrors) return null;
    final error = result.writeError;
    if (error != null) {
      final code = error.code == null ? '' : ' (mã ${error.code})';
      return '${error.errmsg ?? 'MongoDB từ chối lệnh ghi.'}$code';
    }
    final concern = result.writeConcernError;
    if (concern != null) {
      return concern.errmsg ?? 'MongoDB chưa xác nhận lệnh ghi.';
    }
    return 'MongoDB chưa xác nhận lệnh ghi.';
  }

  static String _sample(Map<String, dynamic> document) {
    var text = jsonEncode(_plain(document));
    if (text.length > 700) text = '${text.substring(0, 700)}…';
    return text;
  }

  static dynamic _plain(dynamic value) {
    if (value is ObjectId) return value.toString();
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Map) {
      return {
        for (final entry in value.entries) '${entry.key}': _plain(entry.value),
      };
    }
    if (value is List) return [for (final item in value) _plain(item)];
    if (value is num || value is String || value is bool || value == null) {
      return value;
    }
    return '$value';
  }
}
