import 'package:mongo_dart/mongo_dart.dart';
import '../core/config/database_config.dart';
import '../models/inventory/inventory_models.dart';
import '../models/directory/directory_models.dart';
import '../models/repositories/directory_repository.dart';

class MongoDirectoryRepository implements DirectoryRepository {
  MongoDirectoryRepository({String? uri})
    : _db = Db(uri ?? DatabaseConfig.mongoUri);
  final Db _db;
  Future<void>? _opening;
  Future<void> _connect() =>
      _opening ??= _open().whenComplete(() => _opening = null);
  Future<void> _open() async {
    if (!_db.isConnected) await _db.open();
  }

  String _collection(DirectoryKind kind) =>
      kind == DirectoryKind.partner ? 'DoiTac' : 'VanChuyen';
  String _nameField(DirectoryKind kind) =>
      kind == DirectoryKind.partner ? 'TenDoiTac' : 'TenVanChuyen';
  DirectoryEntry _entry(Map<String, dynamic> row, DirectoryKind kind) =>
      DirectoryEntry(
        id: row['_id'] as String,
        kind: kind,
        name: row[_nameField(kind)]?.toString() ?? '',
        phone: row['SoDienThoai']?.toString() ?? '',
        address: row['DiaChi']?.toString() ?? '',
        taxCode: row['MaSoThue']?.toString() ?? '',
        representative: row['NguoiDaiDien']?.toString() ?? '',
        plate: row['BienSoXe']?.toString() ?? '',
        notes: row['GhiChu']?.toString() ?? '',
      );
  @override
  Future<List<DirectoryEntry>> fetch(DirectoryKind kind) async {
    await _connect();
    final rows = await _db
        .collection(_collection(kind))
        .modernFind(
          filter: {
            'DaXoa': {r'$ne': true},
          },
          sort: {_nameField(kind): 1},
        )
        .toList();
    return rows.map((r) => _entry(r, kind)).toList();
  }

  @override
  Future<DirectoryEntry> create(DirectoryEntryDraft draft) async {
    if (draft.name.trim().isEmpty) throw ArgumentError('Vui lòng nhập tên');
    await _connect();
    final row = <String, dynamic>{
      '_id': ObjectId().oid,
      _nameField(draft.kind): draft.name.trim(),
      'SoDienThoai': draft.phone.trim(),
      'GhiChu': draft.notes.trim(),
      'NgayTao': DateTime.now().toUtc(),
      if (draft.kind == DirectoryKind.partner) ...{
        'DiaChi': draft.address.trim(),
        'MaSoThue': draft.taxCode.trim(),
        'NguoiDaiDien': draft.representative.trim(),
      } else
        'BienSoXe': draft.plate.trim(),
    };
    final result = await _db.collection(_collection(draft.kind)).insertOne(row);
    if (!result.isSuccess || result.hasWriteErrors) {
      throw StateError('Không lưu được danh mục');
    }
    return _entry(row, draft.kind);
  }

  @override
  Future<DirectoryEntry> update(String id, DirectoryEntryDraft draft) async {
    if (draft.name.trim().isEmpty) throw ArgumentError('Vui lòng nhập tên');
    await _connect();
    final row = await _db
        .collection(_collection(draft.kind))
        .findAndModify(
          query: {
            '_id': id,
            'DaXoa': {r'$ne': true},
          },
          update: {
            r'$set': {
              _nameField(draft.kind): draft.name.trim(),
              'SoDienThoai': draft.phone.trim(),
              'GhiChu': draft.notes.trim(),
              'NgayCapNhat': DateTime.now().toUtc(),
              if (draft.kind == DirectoryKind.partner) ...{
                'DiaChi': draft.address.trim(),
                'MaSoThue': draft.taxCode.trim(),
                'NguoiDaiDien': draft.representative.trim(),
              } else
                'BienSoXe': draft.plate.trim(),
            },
          },
          returnNew: true,
        );
    if (row == null) {
      throw StateError('Thông tin đã bị xóa hoặc không còn tồn tại.');
    }
    return _entry(row, draft.kind);
  }

  @override
  Future<void> delete(DirectoryEntry entry) async {
    await _connect();
    final r = await _db
        .collection(_collection(entry.kind))
        .updateOne(
          {
            '_id': entry.id,
            'DaXoa': {r'$ne': true},
          },
          {
            r'$set': {'DaXoa': true, 'NgayXoa': DateTime.now().toUtc()},
          },
        );
    if (!r.isSuccess || r.hasWriteErrors || r.nMatched != 1) {
      throw StateError('Không xóa được danh bạ. Vui lòng tải lại.');
    }
  }

  @override
  Future<List<VehicleBrand>> vehicleBrands() async {
    await _connect();
    final rows = await _db
        .collection('HangXe')
        .modernFind(sort: {'TenHang': 1})
        .toList();
    return rows
        .map((r) => VehicleBrand(r['IdHangXe'] as int, '${r['TenHang'] ?? ''}'))
        .toList();
  }

  @override
  Future<void> close() async {
    try {
      await _opening;
    } catch (_) {
      /* Caller reports connection failures. */
    }
    if (_db.isConnected) await _db.close();
  }
}
