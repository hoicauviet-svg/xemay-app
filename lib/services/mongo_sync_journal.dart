import 'package:mongo_dart/mongo_dart.dart';

/// Mongo connection that records successful business writes for incremental sync.
class SyncTrackedDb extends Db {
  SyncTrackedDb(super.uriString);

  @override
  DbCollection collection(String collectionName) =>
      SyncTrackedCollection(this, collectionName);
}

class SyncTrackedCollection extends DbCollection {
  SyncTrackedCollection(super.db, super.collectionName);

  bool get _isJournal =>
      collectionName == '_sync_changes' ||
      collectionName == '_sync_state' ||
      collectionName == '_app_sync_meta' ||
      collectionName.startsWith('system.');

  String _operationId() => ObjectId().oid;

  Future<void> _begin(String operationId) async {
    await db
        .collection('_sync_state')
        .updateOne(
          {'_id': 'journal'},
          {
            r'$addToSet': {'pendingOperations': operationId},
          },
          upsert: true,
        );
  }

  Future<void> _finish(String operationId) async {
    await db
        .collection('_sync_state')
        .updateOne(
          {'_id': 'journal'},
          {
            r'$pull': {'pendingOperations': operationId},
          },
        );
  }

  String _documentKey(dynamic id) => '${id.runtimeType}:$id';

  Future<void> _append(
    String operationId,
    List<Map<String, dynamic>> before,
    List<Map<String, dynamic>> after,
  ) async {
    final beforeById = {
      for (final document in before)
        if (document['_id'] != null) _documentKey(document['_id']): document,
    };
    final afterById = {
      for (final document in after)
        if (document['_id'] != null) _documentKey(document['_id']): document,
    };
    final keys = {...beforeById.keys, ...afterById.keys}.where((key) {
      final previous = beforeById[key];
      final current = afterById[key];
      if (previous == null || current == null) return true;
      return !_sameDocument(previous, current);
    }).toList();
    if (keys.isEmpty) return;
    final state = await db
        .collection('_sync_state')
        .findAndModify(
          query: {'_id': 'journal'},
          update: {
            r'$inc': {'generation': 1},
          },
          returnNew: true,
          upsert: true,
        );
    final generation = (state?['generation'] as num?)?.toInt() ?? 1;
    final at = DateTime.now().toUtc();
    final events = <Map<String, dynamic>>[];
    var order = 0;
    for (final key in keys) {
      final previous = beforeById[key];
      final current = afterById[key];
      final source = current ?? previous!;
      events.add({
        '_id': ObjectId(),
        'eventType': 'change',
        'operationId': operationId,
        'generation': generation,
        'order': order++,
        'collection': collectionName,
        'documentId': source['_id'],
        'operation': current == null
            ? 'delete'
            : previous == null
            ? 'insert'
            : 'replace',
        'before': previous,
        'after': current,
        'changedAt': at,
        'status': 'ready',
        'synced': false,
      });
    }
    await db.collection('_sync_changes').insertMany(events, ordered: true);
  }

  bool _sameDocument(Map<String, dynamic> left, Map<String, dynamic> right) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !_sameValue(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }

  bool _sameValue(dynamic left, dynamic right) {
    if (left is Map && right is Map) {
      return _sameDocument(
        Map<String, dynamic>.from(left),
        Map<String, dynamic>.from(right),
      );
    }
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (var i = 0; i < left.length; i++) {
        if (!_sameValue(left[i], right[i])) return false;
      }
      return true;
    }
    return left == right;
  }

  Future<List<Map<String, dynamic>>> _read(dynamic selector) =>
      find(selector).toList();

  Future<List<Map<String, dynamic>>> _readByIds(
    List<Map<String, dynamic>> documents,
  ) async {
    final ids = documents
        .map((document) => document['_id'])
        .where((id) => id != null)
        .toList();
    if (ids.isEmpty) return const [];
    return _read({
      '_id': {r'$in': ids},
    });
  }

  Future<T> _tracked<T>(
    Future<T> Function() write,
    Future<List<Map<String, dynamic>>> Function() before,
    Future<List<Map<String, dynamic>>> Function(
      List<Map<String, dynamic>> before,
    )
    after,
  ) async {
    if (_isJournal) return write();
    final operationId = _operationId();
    await _begin(operationId);
    try {
      final oldDocuments = await before();
      final result = await write();
      final newDocuments = await after(oldDocuments);
      await _append(operationId, oldDocuments, newDocuments);
      await _finish(operationId);
      return result;
    } catch (_) {
      // A remaining pending marker forces a safe full-scan sync after a
      // partial write or journal failure.
      rethrow;
    }
  }

  @override
  Future<WriteResult> insertOne(
    Map<String, dynamic> document, {
    WriteConcern? writeConcern,
    bool? bypassDocumentValidation,
  }) async {
    document.putIfAbsent('_id', ObjectId.new);
    return _tracked(
      () => super.insertOne(
        document,
        writeConcern: writeConcern,
        bypassDocumentValidation: bypassDocumentValidation,
      ),
      () async => const [],
      (_) => _read({'_id': document['_id']}),
    );
  }

  @override
  Future<BulkWriteResult> insertMany(
    List<Map<String, dynamic>> documents, {
    WriteConcern? writeConcern,
    bool? ordered,
    bool? bypassDocumentValidation,
  }) async {
    for (final document in documents) {
      document.putIfAbsent('_id', ObjectId.new);
    }
    return _tracked(
      () => super.insertMany(
        documents,
        writeConcern: writeConcern,
        ordered: ordered,
        bypassDocumentValidation: bypassDocumentValidation,
      ),
      () async => const [],
      (_) => _readByIds(documents),
    );
  }

  @override
  Future<WriteResult> updateOne(
    dynamic selector,
    update, {
    bool? upsert,
    WriteConcern? writeConcern,
    CollationOptions? collation,
    List<dynamic>? arrayFilters,
    String? hint,
    Map<String, Object>? hintDocument,
  }) => _tracked(
    () => super.updateOne(
      selector,
      update,
      upsert: upsert,
      writeConcern: writeConcern,
      collation: collation,
      arrayFilters: arrayFilters,
      hint: hint,
      hintDocument: hintDocument,
    ),
    () async => _read(selector),
    (before) async => before.isEmpty ? _read(selector) : _readByIds(before),
  );

  @override
  Future<WriteResult> updateMany(
    dynamic selector,
    update, {
    bool? upsert,
    WriteConcern? writeConcern,
    CollationOptions? collation,
    List<dynamic>? arrayFilters,
    String? hint,
    Map<String, Object>? hintDocument,
  }) => _tracked(
    () => super.updateMany(
      selector,
      update,
      upsert: upsert,
      writeConcern: writeConcern,
      collation: collation,
      arrayFilters: arrayFilters,
      hint: hint,
      hintDocument: hintDocument,
    ),
    () async => _read(selector),
    (before) async => before.isEmpty ? _read(selector) : _readByIds(before),
  );

  @override
  Future<WriteResult> replaceOne(
    dynamic selector,
    Map<String, dynamic> update, {
    bool? upsert,
    WriteConcern? writeConcern,
    CollationOptions? collation,
    String? hint,
    Map<String, Object>? hintDocument,
  }) => _tracked(
    () => super.replaceOne(
      selector,
      update,
      upsert: upsert,
      writeConcern: writeConcern,
      collation: collation,
      hint: hint,
      hintDocument: hintDocument,
    ),
    () async => _read(selector),
    (before) async => before.isEmpty ? _read(selector) : _readByIds(before),
  );

  @override
  Future<WriteResult> deleteOne(
    dynamic selector, {
    WriteConcern? writeConcern,
    CollationOptions? collation,
    String? hint,
    Map<String, Object>? hintDocument,
  }) => _tracked(
    () => super.deleteOne(
      selector,
      writeConcern: writeConcern,
      collation: collation,
      hint: hint,
      hintDocument: hintDocument,
    ),
    () async => _read(selector),
    (_) async => const [],
  );

  @override
  Future<WriteResult> deleteMany(
    dynamic selector, {
    WriteConcern? writeConcern,
    CollationOptions? collation,
    String? hint,
    Map<String, Object>? hintDocument,
  }) => _tracked(
    () => super.deleteMany(
      selector,
      writeConcern: writeConcern,
      collation: collation,
      hint: hint,
      hintDocument: hintDocument,
    ),
    () async => _read(selector),
    (_) async => const [],
  );

  @override
  Future<Map<String, dynamic>?> findAndModify({
    dynamic query,
    sort,
    bool? remove,
    update,
    bool? returnNew,
    fields,
    bool? upsert,
  }) => _tracked(
    () => super.findAndModify(
      query: query,
      sort: sort,
      remove: remove,
      update: update,
      returnNew: returnNew,
      fields: fields,
      upsert: upsert,
    ),
    () async => query == null ? const [] : find(query).take(1).toList(),
    (before) async => remove == true
        ? const []
        : before.isEmpty
        ? (query == null ? const [] : _read(query))
        : _readByIds(before),
  );

  @override
  Future<bool> drop() async {
    if (_isJournal) return super.drop();
    final operationId = _operationId();
    await _begin(operationId);
    await db
        .collection('_sync_state')
        .updateOne(
          {'_id': 'journal'},
          {
            r'$set': {'needsFullScan': true},
          },
          upsert: true,
        );
    try {
      final result = await super.drop();
      await _finish(operationId);
      return result;
    } catch (_) {
      rethrow;
    }
  }
}
