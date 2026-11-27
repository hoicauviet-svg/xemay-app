import 'package:mongo_dart/mongo_dart.dart';

import '../core/config/database_config.dart';
import '../models/repositories/change_history_repository.dart';
import 'change_history.dart';
import 'mongo_sync_journal.dart';

class MongoChangeHistoryRepository implements ChangeHistoryRepository {
  MongoChangeHistoryRepository({String? uri})
    : _db = SyncTrackedDb(uri ?? DatabaseConfig.mongoUri);
  final Db _db;
  Future<void>? _opening;

  Future<void> _connect() =>
      _opening ??= _open().whenComplete(() => _opening = null);
  Future<void> _open() async {
    if (!_db.isConnected) await _db.open();
  }

  @override
  Future<List<Map<String, dynamic>>> fetch({
    String search = '',
    int limit = 100,
  }) async {
    await _connect();
    final term = search.trim();
    final filter = <String, dynamic>{
      if (term.isNotEmpty)
        r'$or': [
          {
            'Summary': {r'$regex': RegExp.escape(term), r'$options': 'i'},
          },
          {
            'RequestId': {r'$regex': RegExp.escape(term), r'$options': 'i'},
          },
          {
            'Machine': {r'$regex': RegExp.escape(term), r'$options': 'i'},
          },
          if (int.tryParse(term) != null) {'ParentId': int.parse(term)},
        ],
    };
    return _db
        .collection(ChangeHistory.collection)
        .modernFind(
          filter: filter,
          sort: {'At': -1},
          limit: limit.clamp(1, 500),
        )
        .toList();
  }

  @override
  Future<void> close() async {
    try {
      await _opening;
    } catch (_) {
      /* The screen reports connection errors. */
    }
    if (_db.isConnected) await _db.close();
  }
}
