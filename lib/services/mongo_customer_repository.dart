import 'customer_address_migration.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'mongo_sync_journal.dart';
import '../core/config/database_config.dart';
import '../models/customers/customer_models.dart';
import '../models/repositories/customer_repository.dart';

class MongoCustomerRepository implements CustomerRepository {
  MongoCustomerRepository({String? uri})
    : _db = SyncTrackedDb(uri ?? DatabaseConfig.mongoUri);
  final Db _db;
  bool _addressesReady = false;
  Future<void>? _opening;
  Future<void> _connect() => _opening ??= _open().whenComplete(() {
    _opening = null;
  });
  Future<void> _open() async {
    if (!_db.isConnected) await _db.open();
    if (!_addressesReady) {
      await migrateCustomerAddresses(_db);
      _addressesReady = true;
    }
  }

  @override
  Future<CustomerPage> fetch({
    String search = '',
    String phoneFilter = 'all',
    int page = 0,
  }) async {
    await _connect();
    final filter = <String, dynamic>{
      'DaXoa': {r'$ne': true},
      'AnKhoiDanhSachKhachHang': {r'$ne': true},
    };
    final term = search.trim();
    if (term.isNotEmpty) {
      final regex = {r'$regex': RegExp.escape(term), r'$options': 'i'};
      filter[r'$or'] = [
        for (final f in [
          'TenKhachHang',
          'SoDienThoai',
          'DiaChiChiTiet',
          'SoCCCD',
          'SoCMND',
        ])
          {f: regex},
        if (int.tryParse(term) != null) {'IdKH': int.parse(term)},
      ];
    }
    if (phoneFilter != 'all') {
      filter['SoDienThoai'] = phoneFilter == 'with_phone'
          ? {r'$regex': r'\S'}
          : {
              r'$not': {r'$regex': r'\S'},
            };
    }
    final c = _db.collection('KhachHang');
    final total = await c.count(filter);
    final rows = await c
        .modernFind(
          filter: filter,
          sort: {'IdKH': -1},
          skip: page == 0 ? null : page * 30,
          limit: 30,
        )
        .toList();
    for (final row in rows) {
      row['DiaChiHienThi'] = row['DiaChiChiTiet'] ?? '';
    }
    return CustomerPage(rows, total);
  }

  @override
  Future<Map<String, dynamic>?> findById(int customerId) async {
    await _connect();
    final row = await _db.collection('KhachHang').findOne({
      'IdKH': customerId,
      'DaXoa': {r'$ne': true},
      'AnKhoiDanhSachKhachHang': {r'$ne': true},
    });
    if (row == null) return null;
    row['DiaChiHienThi'] = row['DiaChiChiTiet'] ?? '';
    return row;
  }

  @override
  Future<CustomerOrderPage> orders(int customerId, {int page = 0}) async {
    await _connect();
    const idField = 'IdHoaDon';
    const dateField = 'NgayMua';
    final collection = _db.collection('HoaDonBan');
    final filter = {
      'IdKH': customerId,
      'TrangThaiLuu': {r'$ne': 'dang_luu'},
    };
    final total = await collection.count(filter);
    final rows = await collection
        .modernFind(
          filter: filter,
          sort: {dateField: -1, idField: -1},
          skip: page == 0 ? null : page * 30,
          limit: 30,
        )
        .toList();
    if (rows.isEmpty) return CustomerOrderPage(rows, total);
    final lines = await _db.collection('ChiTietHoaDonBan').find({
      idField: {r'$in': rows.map((r) => r[idField]).toList()},
    }).toList();
    final productIds = lines
        .map((r) => r['IdSanPham'])
        .where((v) => v != null)
        .toSet()
        .toList();
    final products = productIds.isEmpty
        ? <Map<String, dynamic>>[]
        : await _db.collection('SanPham').find({
            'IdSanPham': {r'$in': productIds},
          }).toList();
    final names = {for (final p in products) p['IdSanPham']: p['TenSanPham']};
    for (final row in rows) {
      final items = lines.where((l) => l[idField] == row[idField]).toList();
      row['MaDonHang'] = row[idField];
      row['NgayDonHang'] = row[dateField];
      row['SanPhamHienThi'] = items
          .map(
            (l) =>
                '${l['TenSanPham'] ?? names[l['IdSanPham']] ?? 'Sản phẩm #${l['IdSanPham']}'}${l['IdXe'] == null ? '' : ' (#${l['IdXe']})'}',
          )
          .join(', ');
      row['TongSoLuong'] =
          items.isEmpty || items.any((l) => l['SoLuong'] is! num)
          ? null
          : items.fold<num>(0, (sum, l) => sum + (l['SoLuong'] as num));
      // Historical source prices were flagged for reconciliation during migration.
      // Only actual line prices may contribute to an order total.
      row['TongTien'] = row['TongThanhToan'] is num
          ? row['TongThanhToan']
          : items.isEmpty ||
                items.any((l) => l['DonGia'] is! num || l['SoLuong'] is! num)
          ? null
          : items.fold<num>(
              0,
              (sum, l) => sum + (l['DonGia'] as num) * (l['SoLuong'] as num),
            );
    }
    return CustomerOrderPage(rows, total);
  }

  @override
  Future<Map<String, dynamic>> create(CustomerDraft draft) async {
    if (draft.name.trim().isEmpty) {
      throw const CustomerException('Vui lòng nhập tên khách hàng.');
    }
    final identity = draft.identityFields();
    await _connect();
    final last = await _db
        .collection('KhachHang')
        .modernFind(sort: {'IdKH': -1}, limit: 1)
        .toList();
    final highest = last.isEmpty ? 0 : last.first['IdKH'] as int;
    final counters = _db.collection('_app_counters');
    await counters.findAndModify(
      query: {'_id': 'KhachHang'},
      update: {
        r'$max': {'value': highest},
      },
      upsert: true,
    );
    final sequence = await counters.findAndModify(
      query: {'_id': 'KhachHang'},
      update: {
        r'$inc': {'value': 1},
      },
      returnNew: true,
    );
    final row = <String, dynamic>{
      '_id': ObjectId().oid,
      'IdKH': sequence!['value'],
      'TenKhachHang': draft.name.trim(),
      'SoDienThoai': draft.phone.trim(),
      'DiaChiChiTiet': draft.address.trim(),
      ...identity,
      'NgayTao': DateTime.now().toUtc(),
    };
    final result = await _db.collection('KhachHang').insertOne(row);
    if (!result.isSuccess || result.hasWriteErrors) {
      throw const CustomerException('Không lưu được khách hàng.');
    }
    return {...row, 'DiaChiHienThi': draft.address.trim()};
  }

  @override
  Future<Map<String, dynamic>> update(int id, CustomerDraft draft) async {
    if (draft.name.trim().isEmpty) {
      throw const CustomerException('Vui lòng nhập tên khách hàng.');
    }
    final identity = draft.identityFields();
    await _connect();
    final row = await _db
        .collection('KhachHang')
        .findAndModify(
          query: {
            'IdKH': id,
            'KhoaGop': {r'$exists': false},
            'DaXoa': {r'$ne': true},
          },
          update: {
            r'$set': {
              'TenKhachHang': draft.name.trim(),
              'SoDienThoai': draft.phone.trim(),
              'DiaChiChiTiet': draft.address.trim(),
              ...identity,
              'NgayCapNhat': DateTime.now().toUtc(),
            },
            r'$unset': {'IdXa': ''},
          },
          returnNew: true,
        );
    if (row == null) {
      throw const CustomerException('Khách hàng không còn tồn tại.');
    }
    return {...row, 'DiaChiHienThi': draft.address.trim()};
  }

  @override
  Future<void> delete(Map<String, dynamic> customer) async {
    await _connect();
    final id = customer['IdKH'];
    if (id == null || customer['_id'] == null) {
      throw const CustomerException('Khách hàng không hợp lệ.');
    }
    for (final reference in {
      'HoaDonBan': 'IdKH',
      'HoaDonMua': 'IdKh',
      'CamDo': 'IdKhachHang',
      'NoCu': 'IdKH',
    }.entries) {
      if (await _db.collection(reference.key).findOne({
            reference.value: {
              r'$in': [id, '$id'],
            },
          }) !=
          null) {
        throw const CustomerException(
          'Không thể xóa khách hàng đã có giao dịch hoặc công nợ.',
        );
      }
    }
    final active = await _db.collection('KhachHang').findOne({'IdKH': id});
    if ((active?['GiuChoDonBan'] as Map?)?.isNotEmpty == true) {
      throw const CustomerException(
        'Khách hàng đang có đơn bán được lưu. Vui lòng thử lại sau.',
      );
    }
    // Keep the original record recoverable; existing IDs must never be reused.
    final result = await _db
        .collection('KhachHang')
        .updateOne(
          {
            '_id': customer['_id'],
            'IdKH': id,
            'KhoaGop': {r'$exists': false},
            r'$or': [
              {
                'GiuChoDonBan': {r'$exists': false},
              },
              {'GiuChoDonBan': {}},
            ],
          },
          {
            r'$set': {'DaXoa': true, 'NgayXoa': DateTime.now().toUtc()},
          },
        );
    if (!result.isSuccess || result.hasWriteErrors || result.nMatched != 1) {
      throw const CustomerException(
        'Không xóa được khách hàng. Có thể khách đang có đơn được lưu.',
      );
    }
  }

  @override
  Future<List<Map<String, dynamic>>> mergeCandidates() async {
    await _connect();
    final rows = await _db
        .collection('KhachHang')
        .modernFind(
          filter: {
            'DaXoa': {r'$ne': true},
            'AnKhoiDanhSachKhachHang': {r'$ne': true},
          },
          projection: {
            'IdKH': 1,
            'TenKhachHang': 1,
            'SoDienThoai': 1,
            'DiaChiChiTiet': 1,
          },
        )
        .toList();
    for (final row in rows) {
      row['DiaChiHienThi'] = row['DiaChiChiTiet'] ?? '';
    }
    return rows;
  }

  @override
  Future<List<Map<String, dynamic>>> pendingMerges() async {
    await _connect();
    final locked = await _db
        .collection('KhachHang')
        .modernFind(
          filter: {
            'KhoaGop': {r'$exists': true},
          },
          projection: {'KhoaGop': 1},
        )
        .toList();
    return _db.collection('_customer_merges').find({
      r'$or': [
        {'TrangThai': 'dang_gop'},
        {
          '_id': {r'$in': locked.map((r) => r['KhoaGop']).toSet().toList()},
        },
      ],
    }).toList();
  }

  /// A resumable journal is used because the store may run standalone MongoDB.
  /// Customer snapshots are retained; monetary records are never consolidated.
  @override
  Future<void> merge({
    required int targetId,
    required List<int> sourceIds,
  }) async {
    final sources = sourceIds.toSet().toList()..sort();
    if (sources.isEmpty || sources.contains(targetId)) {
      throw const CustomerException(
        'Chọn khách chính và ít nhất một khách trùng khác.',
      );
    }
    await _connect();
    final key = '$targetId:${sources.join(',')}';
    final journal = _db.collection('_customer_merges');
    final customers = _db.collection('KhachHang');
    final previous = await journal.findOne({'_id': key});
    if (previous?['TrangThai'] == 'hoan_tat') {
      await customers.updateMany(
        {'KhoaGop': key},
        {
          r'$unset': {'KhoaGop': ''},
        },
      );
      return;
    }
    final ids = [targetId, ...sources]..sort();
    const references = {
      'HoaDonBan': 'IdKH',
      'HoaDonMua': 'IdKh',
      'CamDo': 'IdKhachHang',
      'NoCu': 'IdKH',
    };
    final oldIds = [
      for (final id in sources) ...[id, '$id'],
    ];
    final acquired = <int>[];
    var started = previous?['TrangThai'] == 'dang_gop';
    try {
      for (final id in ids) {
        final row = await customers.findAndModify(
          query: {
            'IdKH': id,
            'AnKhoiDanhSachKhachHang': {r'$ne': true},
            r'$and': [
              {
                r'$or': [
                  {
                    'DaXoa': {r'$ne': true},
                  },
                  {'DaGopVao': targetId, 'KhoaGop': key},
                ],
              },
              {
                r'$or': [
                  {
                    'KhoaGop': {r'$exists': false},
                  },
                  {'KhoaGop': key},
                ],
              },
              {
                r'$or': [
                  {
                    'GiuChoDonBan': {r'$exists': false},
                  },
                  {'GiuChoDonBan': {}},
                ],
              },
            ],
          },
          update: {
            r'$set': {'KhoaGop': key},
          },
          returnNew: true,
        );
        if (row == null) {
          throw const CustomerException(
            'Khách hàng không còn hợp lệ hoặc đang có giao dịch được lưu. Vui lòng thử lại.',
          );
        }
        acquired.add(id);
      }
      if (!started) {
        final snapshots = await customers.find({
          'IdKH': {r'$in': ids},
        }).toList();
        final originalLinks = <String, dynamic>{};
        for (final ref in references.entries) {
          originalLinks[ref.key] = await _db
              .collection(ref.key)
              .modernFind(
                filter: {
                  ref.value: {r'$in': oldIds},
                },
                projection: {'_id': 1, ref.value: 1},
              )
              .toList();
        }
        final result = await journal.updateOne(
          {'_id': key},
          {
            r'$setOnInsert': {
              'KhachChinh': targetId,
              'KhachTrung': sources,
              'BanGoc': snapshots,
              'LienKetGoc': originalLinks,
              'NgayTao': DateTime.now().toUtc(),
              'TrangThai': 'dang_gop',
            },
          },
          upsert: true,
        );
        if (!result.isSuccess || result.hasWriteErrors) {
          throw StateError('journal');
        }
        started = true;
      }
      // Legacy IDs may be strings. Normalize references to the retained integer ID.
      for (final reference in references.entries) {
        final result = await _db
            .collection(reference.key)
            .updateMany(
              {
                reference.value: {r'$in': oldIds},
              },
              {
                r'$set': {reference.value: targetId},
              },
            );
        if (!result.isSuccess || result.hasWriteErrors) {
          throw StateError('references');
        }
      }
      final archived = await customers.updateMany(
        {
          'IdKH': {r'$in': sources},
          'KhoaGop': key,
        },
        {
          r'$set': {
            'DaXoa': true,
            'DaGopVao': targetId,
            'NgayGop': DateTime.now().toUtc(),
          },
        },
      );
      if (!archived.isSuccess ||
          archived.hasWriteErrors ||
          archived.nMatched != sources.length) {
        throw StateError('archive');
      }
      final done = await journal.updateOne(
        {'_id': key},
        {
          r'$set': {
            'TrangThai': 'hoan_tat',
            'NgayHoanTat': DateTime.now().toUtc(),
          },
        },
      );
      if (!done.isSuccess || done.hasWriteErrors) {
        throw StateError('journal completion');
      }
      started = false;
    } finally {
      // Interrupted writes retain their lock and journal so the same merge can resume.
      if (!started) {
        await customers.updateMany(
          {
            'IdKH': {r'$in': acquired},
            'KhoaGop': key,
          },
          {
            r'$unset': {'KhoaGop': ''},
          },
        );
      }
    }
  }

  @override
  Future<void> close() async {
    try {
      await _opening;
    } catch (_) {
      /* Screen reports errors. */
    }
    if (_db.isConnected) await _db.close();
  }
}
