import 'package:mongo_dart/mongo_dart.dart';
import 'mongo_sync_journal.dart';
import '../core/config/database_config.dart';
import '../models/services/service_models.dart';
import '../models/repositories/service_repository.dart';

class MongoServiceRepository implements ServiceRepository {
  MongoServiceRepository({String? uri})
    : _db = SyncTrackedDb(uri ?? DatabaseConfig.mongoUri);
  final Db _db;
  Future<void>? _opening;
  Future<void> _connect() => _opening ??= _open().whenComplete(() {
    _opening = null;
  });
  Future<void> _open() async {
    if (!_db.isConnected) await _db.open();
  }

  @override
  Future<ServicePage> fetch({String search = ''}) async {
    await _connect();
    final term = search.trim();
    final filter = <String, dynamic>{
      'DaXoa': {r'$ne': true},
      if (term.isNotEmpty)
        r'$or': [
          for (final field in ['TenDichVu', 'MoTa'])
            {
              field: {r'$regex': RegExp.escape(term), r'$options': 'i'},
            },
        ],
    };
    final collection = _db.collection('DichVu');
    final total = await collection.count(filter);
    final rows = await collection
        .modernFind(filter: filter, sort: {'TenDichVu': 1, '_id': 1})
        .toList();
    return ServicePage(rows.map(ServiceItem.fromMap).toList(), total);
  }

  @override
  Future<ServiceItem> create(ServiceDraft draft) async {
    if (draft.name.trim().isEmpty) {
      throw const ServiceException('Vui lòng nhập tên dịch vụ.');
    }
    if (draft.priceError != null) throw ServiceException(draft.priceError!);
    if (draft.costError != null) throw ServiceException(draft.costError!);
    await _connect();
    final row = <String, dynamic>{
      '_id': ObjectId().oid,
      'TenDichVu': draft.name.trim(),
      'MoTa': draft.description.trim(),
      'GiaTien': draft.parsedPrice!,
      'GiaVon': draft.parsedCost!,
    };
    final result = await _db.collection('DichVu').insertOne(row);
    if (!result.isSuccess || result.hasWriteErrors) {
      throw const ServiceException('Không lưu được dịch vụ.');
    }
    return ServiceItem.fromMap(row);
  }

  @override
  Future<ServiceItem> update(String id, ServiceDraft draft) async {
    if (draft.name.trim().isEmpty ||
        draft.priceError != null ||
        draft.costError != null) {
      throw const ServiceException('Tên hoặc giá dịch vụ không hợp lệ.');
    }
    await _connect();
    final row = await _db
        .collection('DichVu')
        .findAndModify(
          query: {
            '_id': id,
            'DaXoa': {r'$ne': true},
          },
          update: {
            r'$set': {
              'TenDichVu': draft.name.trim(),
              'MoTa': draft.description.trim(),
              'GiaTien': draft.parsedPrice!,
              'GiaVon': draft.parsedCost!,
              'NgayCapNhat': DateTime.now().toUtc(),
            },
          },
          returnNew: true,
        );
    if (row == null) throw const ServiceException('Dịch vụ không còn tồn tại.');
    return ServiceItem.fromMap(row);
  }

  @override
  Future<void> delete(String id) async {
    await _connect();
    final r = await _db
        .collection('DichVu')
        .updateOne(
          {
            '_id': id,
            'DaXoa': {r'$ne': true},
          },
          {
            r'$set': {'DaXoa': true, 'NgayXoa': DateTime.now().toUtc()},
          },
        );
    if (!r.isSuccess || r.hasWriteErrors || r.nMatched != 1) {
      throw const ServiceException('Không xóa được dịch vụ.');
    }
  }

  @override
  Future<void> close() async {
    try {
      await _opening;
    } catch (_) {
      /* Screen reports connection errors. */
    }
    if (_db.isConnected) await _db.close();
  }
}
