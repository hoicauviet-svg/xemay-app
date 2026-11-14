import '../models/pawn/pawn_models.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'mongo_sync_journal.dart';
import '../models/maintenance/record_maintenance.dart';
import '../core/config/database_config.dart';
import '../models/finance/cash_category.dart';
import 'cost_delete_repair.dart';

/// A durable per-parent change plan. Every write is an absolute, replayable update.
/// Original documents are backed up individually to keep attachments out of plans.
class MongoRecordMaintenance implements RecordMaintenance {
  MongoRecordMaintenance(this.db, this.connect, {this.checkpoint});
  factory MongoRecordMaintenance.local() {
    final db = SyncTrackedDb(DatabaseConfig.mongoUri);
    var repairing = false;
    return MongoRecordMaintenance(db, () async {
      if (!db.isConnected) await db.open(writeConcern: WriteConcern.journaled);
      if (repairing) return;
      repairing = true;
      try {
        await repairStuckCostDeletes(db);
      } finally {
        repairing = false;
      }
    });
  }
  @override
  Future<void> close() async {
    if (db.isConnected) await db.close();
  }

  final Db db;
  final Future<void> Function() connect;
  final Future<void> Function(String)? checkpoint;
  static const specs = {
    RecordKind.cash: ('ThuChiKhac', 'ThuChiId', '_none', 'Parent', '', '', ''),
    RecordKind.vehicleProduct: ('Xe', 'IdXe', '_none', 'Parent', '', '', ''),
    RecordKind.partProduct: (
      'SanPham',
      'IdSanPham',
      '_none',
      'Parent',
      '',
      '',
      '',
    ),
    RecordKind.order: (
      'HoaDonBan',
      'IdHoaDon',
      'TraNo',
      'IdSoNo',
      'SotienTra',
      'LaiThu',
      'SoCoNo',
    ),
    RecordKind.batch: (
      'NhapHang',
      'IdNhapHang',
      'TraNoNhapHang',
      'IdNhapHang',
      'SoTienTra',
      '',
      'SoCoNo',
    ),
    RecordKind.pawn: (
      'CamDo',
      'IdCamDo',
      'TraNoCamDo',
      'IdCamDo',
      'TienGoc',
      'SoTienLai',
      '',
    ),
    RecordKind.funding: (
      'VayVon',
      'IdVayVon',
      'TraNoVayVon',
      'IdVayVon',
      'SoTienTraGoc',
      'SoTienTraLai',
      'ConNoGoc',
    ),
    RecordKind.openingDebt: (
      'NoCu',
      'Id',
      'TraNoCu',
      'IdNoCu',
      'SoTienTra',
      'LaiThu',
      'ConNo',
    ),
  };
  Never fail(String text) => throw RecordChangeException(text);
  bool _sameId(dynamic value, int id) =>
      value == id || (value is num && value.toDouble() == id.toDouble());
  bool _sameCost(Map<String, dynamic> stored, Map<String, dynamic> requested) {
    final requestKey = requested['MaYeuCau'];
    if (requestKey != null && stored['MaYeuCau'] == requestKey) return true;
    final storedAmount = stored['SoTien'];
    final requestedAmount = requested['SoTien'];
    final sameAmount =
        storedAmount == requestedAmount ||
        (storedAmount is num &&
            requestedAmount is num &&
            storedAmount.toDouble() == requestedAmount.toDouble());
    return sameAmount &&
        _sameTime(stored['Ngay'], requested['Ngay']) &&
        '${stored['GhiChu'] ?? ''}'.trim() ==
            '${requested['GhiChu'] ?? ''}'.trim();
  }

  bool _sameTime(dynamic stored, dynamic requested) {
    if (stored is DateTime && requested is DateTime) {
      final left = stored.toUtc();
      final right = requested.toUtc();
      return left.millisecondsSinceEpoch == right.millisecondsSinceEpoch;
    }
    return stored == requested;
  }

  int _costIndex(
    List<Map<String, dynamic>> entries,
    Map<String, dynamic> cost,
  ) {
    final hinted = cost['_CostIndex'];
    if (hinted is int &&
        hinted >= 0 &&
        hinted < entries.length &&
        entries[hinted]['DaXoa'] != true &&
        _sameCost(entries[hinted], cost)) {
      return hinted;
    }
    for (var i = 0; i < entries.length; i++) {
      if (entries[i]['DaXoa'] != true && _sameCost(entries[i], cost)) return i;
    }
    return -1;
  }

  num number(dynamic value) {
    if (value is! num || !value.isFinite || value < 0 || value > 1e15) {
      fail('Số tiền hoặc số lượng chưa hợp lệ, cần đối soát dữ liệu.');
    }
    return value;
  }

  bool _costSchemaStep(
    Map<String, dynamic> step,
    Map<String, dynamic> fields,
  ) =>
      costCollections.contains(step['Collection']) &&
      (fields.containsKey('ChiPhi') || fields.containsKey('TongChiPhi'));

  Future<void> checked(Future<dynamic> action) async {
    final result = await action;
    if (!result.isSuccess || result.hasWriteErrors) {
      fail('Chưa xác nhận ghi dữ liệu. Vui lòng thử lại cùng yêu cầu.');
    }
  }

  DateTime day(DateTime d) => DateTime.utc(d.year, d.month, d.day);
  Future<RecordEditData> _read(RecordKind kind, int id) async {
    final s = specs[kind]!;
    final h = await db.collection(s.$1).findOne({s.$2: id});
    if (h == null) fail('Phiếu không còn tồn tại.');
    final debts = kind == RecordKind.order
        ? await db.collection('SoNo').find({'IdHoaDon': id}).toList()
        : <Map<String, dynamic>>[];
    if (kind == RecordKind.order && debts.length != 1) {
      fail('Đơn hàng cần có đúng một sổ nợ trước khi sửa/xóa.');
    }
    final payments = await db
        .collection(s.$3)
        .modernFind(
          filter: {
            s.$4: kind == RecordKind.order ? debts.single['IdSoNo'] : id,
          },
          sort: {'NgayTra': 1, '_id': 1},
        )
        .toList();
    final lines = kind == RecordKind.order || kind == RecordKind.batch
        ? await db
              .collection(
                kind == RecordKind.order
                    ? 'ChiTietHoaDonBan'
                    : 'ChiTietNhapHang',
              )
              .find({s.$2: id})
              .toList()
        : <Map<String, dynamic>>[];
    if (kind == RecordKind.batch && lines.isEmpty) {
      final ext = await db.collection('XeMoi').find({
        'IdNhapHang': id,
      }).toList();
      final vehicles = await db.collection('Xe').find({
        r'$or': [
          {'IdNhapHang': id},
          if (ext.isNotEmpty)
            {
              'IdXe': {r'$in': ext.map((e) => e['IdXe']).toList()},
            },
        ],
      }).toList();
      for (final vehicle in vehicles) {
        lines.add({
          '_id': 'legacy-receipt:${vehicle['IdXe']}',
          '_Synthetic': true,
          'IdNhapHang': id,
          'IdXe': vehicle['IdXe'],
          'IdSanPham': vehicle['IdSanPham'],
          'TenSanPham': vehicle['TenXe'],
          'SoLuong': 1,
          'GiaNhap': vehicle['GiaNhap'],
        });
      }
    }
    if (kind == RecordKind.order && lines.isEmpty && h['IdXe'] != null) {
      final vehicle = await db.collection('Xe').findOne({'IdXe': h['IdXe']});
      if (vehicle != null) {
        lines.add({
          '_id': 'legacy-edit:$id',
          '_Synthetic': true,
          'IdHoaDon': id,
          'IdXe': h['IdXe'],
          'IdSanPham': vehicle['IdSanPham'],
          'TenSanPham': vehicle['TenXe'],
          'SoLuong': 1,
          'DonGia': vehicle['GiaBan'],
        });
      }
    }
    if (kind == RecordKind.order) {
      for (final line in lines) {
        if (line['DonGia'] == null) {
          final vehicle = line['IdXe'] == null
              ? null
              : await db.collection('Xe').findOne({'IdXe': line['IdXe']});
          line['DonGia'] = line['DonGiaNguon'] ?? vehicle?['GiaBan'];
        }
      }
    }
    final customerId = kind == RecordKind.pawn ? h['IdKhachHang'] : h['IdKH'];
    final customer =
        (kind == RecordKind.order || kind == RecordKind.pawn) &&
            customerId != null
        ? await db.collection('KhachHang').findOne({'IdKH': customerId})
        : null;
    final categories = <String, CashCategory>{
      for (final c in CashCategory.defaults) c.id: c,
    };
    if (kind == RecordKind.cash) {
      for (final category
          in await db.collection('DanhMucThuChi').find().toList()) {
        if (category['HoatDong'] == false) {
          categories.remove(category['_id']);
        } else {
          categories[category['_id']] = CashCategory(
            category['_id'],
            category['TenDanhMuc'],
            category['ThuChi'] == true,
          );
        }
      }
    }
    return RecordEditData(
      {
        ...h,
        '_CustomerName': customer?['TenKhachHang'],
        if (kind == RecordKind.cash) ...{
          '_CashCategories': [for (final c in categories.values) c.toFields()],
          '_ManagedCash': _managedCash(h),
        },
        if (debts.isNotEmpty) '_SoNo': debts.single,
      },
      lines,
      payments,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> suggestions(
    String collection,
    String search,
  ) async {
    await connect();
    if (!['KhachHang', 'DoiTac', 'VanChuyen'].contains(collection)) return [];
    final name = collection == 'KhachHang'
        ? 'TenKhachHang'
        : collection == 'DoiTac'
        ? 'TenDoiTac'
        : 'TenVanChuyen';
    final term = search.trim();
    final regex = {r'$regex': RegExp.escape(term), r'$options': 'i'};
    return db
        .collection(collection)
        .modernFind(
          filter: {
            'DaXoa': {r'$ne': true},
            'AnKhoiDanhSachKhachHang': {r'$ne': true},
            if (term.isNotEmpty)
              r'$or': [
                {name: regex},
                {'SoDienThoai': regex},
                if (collection == 'KhachHang' && int.tryParse(term) != null)
                  {'IdKH': int.parse(term)},
              ],
          },
          limit: 20,
          sort: {name: 1},
        )
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> pending() async {
    await connect();
    return db
        .collection('_record_changes')
        .modernFind(
          filter: {
            r'$or': [
              {
                'State': {
                  r'$in': ['pending', 'preparing'],
                },
              },
              {
                'State': 'done',
                'Released': {r'$ne': true},
              },
            ],
          },
          projection: {'Kind': 1, 'Parent': 1, 'Date': 1, 'DeleteParent': 1},
          sort: {'Date': 1},
        )
        .toList();
  }

  @override
  Future<void> ensureReadable(RecordKind kind, int id) async {
    final plans = await pending();
    if (plans.any((p) => p['Kind'] == kind.name && p['Parent'] == id)) {
      fail(
        'Phiếu có thay đổi chưa hoàn tất. Bấm Tiếp tục xử lý để hoàn thành.',
      );
    }
  }

  @override
  Future<void> recover(RecordKind kind, int id) async {
    await connect();
    final plans = await db.collection('_record_changes').find({
      'Kind': kind.name,
      'Parent': id,
      r'$or': [
        {
          'State': {
            r'$in': ['pending', 'preparing'],
          },
        },
        {
          'State': 'done',
          'Released': {r'$ne': true},
        },
      ],
    }).toList();
    for (final plan in plans) {
      await _finish(plan['_id'] as String);
    }
  }

  @override
  Future<RecordEditData> load(RecordKind kind, int id) async {
    await ensureReadable(kind, id);
    return _read(kind, id);
  }

  Map<String, dynamic> op(
    String collection,
    dynamic id,
    Map<String, dynamic>? fields, {
    List<String> unset = const [],
  }) => {'Collection': collection, 'Id': id, 'Fields': fields, 'Unset': unset};

  Future<void> _finish(String request) async {
    final journal = db.collection('_record_changes');
    final plan = await journal.findOne({'_id': request});
    if (plan == null) fail('Không tìm thấy nhật ký sửa/xóa.');
    if (plan['State'] == 'done') {
      await _releasePlan(plan);
      return;
    }
    if (plan['State'] == 'aborted') return;
    if (plan['State'] == 'preparing') {
      if (DateTime.now()
              .toUtc()
              .difference(plan['Date'] as DateTime)
              .inSeconds <
          120) {
        fail('Phiếu đang được sửa/xóa. Vui lòng thử lại sau.');
      }
      for (final name in [
        'HoaDonBan',
        'NhapHang',
        'SoNo',
        'CamDo',
        'VayVon',
        'NoCu',
        'Xe',
        'TonKhoPhuTung',
        'SanPham',
        'ChiTietNhapHang',
        'ThuChiKhac',
      ]) {
        await checked(
          db
              .collection(name)
              .updateMany(
                {'SuaXoaDangLuu': request},
                {
                  r'$unset': {'SuaXoaDangLuu': ''},
                },
              ),
        );
      }
      await checked(
        journal.updateOne(
          {'_id': request},
          {
            r'$set': {'State': 'aborted'},
          },
        ),
      );
      return;
    }

    final executor = ObjectId().oid;
    final execution = await journal.findAndModify(
      query: {
        '_id': request,
        'State': 'pending',
        r'$or': [
          {'ExecutionUntil': null},
          {
            'ExecutionUntil': {r'$lt': DateTime.now().toUtc()},
          },
        ],
      },
      update: {
        r'$set': {
          'Executor': executor,
          'ExecutionUntil': DateTime.now().toUtc().add(
            const Duration(minutes: 2),
          ),
        },
      },
      returnNew: true,
    );
    if (execution == null) {
      fail('Thay đổi đang được xử lý. Vui lòng thử lại sau.');
    }
    try {
      var index = 0;
      for (final raw in plan['Operations'] as List) {
        final step = Map<String, dynamic>.from(raw as Map);
        final collection = db.collection(step['Collection'] as String);
        final previous = await collection.findOne({'_id': step['Id']});
        await checked(
          db
              .collection('_record_change_backups')
              .updateOne(
                {'_id': '$request:$index'},
                {
                  r'$setOnInsert': {
                    'Request': request,
                    'Collection': step['Collection'],
                    'Document': previous,
                  },
                },
                upsert: true,
              ),
        );
        if (step['Fields'] == null) {
          await checked(
            db
                .collection('_record_deleted')
                .updateOne(
                  {'_id': '${step['Collection']}:${step['Id']}'},
                  {
                    r'$setOnInsert': {
                      'Request': request,
                      'Date': DateTime.now().toUtc(),
                    },
                  },
                  upsert: true,
                ),
          );
          await checked(collection.deleteOne({'_id': step['Id']}));
        } else {
          final fields = Map<String, dynamic>.from(step['Fields'] as Map);
          final unset = (step['Unset'] as List?) ?? [];
          Future<dynamic> write() => collection.updateOne(
            {'_id': step['Id']},
            {
              if (fields.isNotEmpty) r'$set': fields,
              if (unset.isNotEmpty)
                r'$unset': {for (final key in unset) key: ''},
            },
            upsert: step['Upsert'] == true,
          );
          var result = await write();
          if ((!result.isSuccess || result.hasWriteErrors) &&
              _costSchemaStep(step, fields)) {
            await refreshCostCollectionValidators(db);
            result = await write();
          }
          await checked(Future.value(result));
        }
        index++;
        await checked(
          journal.updateOne(
            {'_id': request, 'Executor': executor},
            {
              r'$set': {
                'ExecutionUntil': DateTime.now().toUtc().add(
                  const Duration(minutes: 2),
                ),
              },
            },
          ),
        );
        if (checkpoint != null) await checkpoint!('afterStep$index');
      }
      await checked(
        journal.updateOne(
          {'_id': request},
          {
            r'$set': {'State': 'done', 'Completed': DateTime.now().toUtc()},
          },
        ),
      );
      await _releasePlan(plan);
    } finally {
      await checked(
        journal.updateOne(
          {'_id': request, 'Executor': executor},
          {
            r'$unset': {'Executor': '', 'ExecutionUntil': ''},
          },
        ),
      );
    }
  }

  Future<void> _releasePlan(Map<String, dynamic> plan) async {
    for (final raw in plan['Locks'] as List? ?? []) {
      final lock = raw as Map;
      await checked(
        db
            .collection(lock['Collection'] as String)
            .updateOne(
              {'_id': lock['Id'], 'SuaXoaDangLuu': plan['_id']},
              {
                r'$unset': {'SuaXoaDangLuu': ''},
              },
            ),
      );
    }
    await checked(
      db
          .collection('_record_changes')
          .updateOne(
            {'_id': plan['_id']},
            {
              r'$set': {'Released': true},
            },
          ),
    );
  }

  Future<void> _run(
    RecordKind kind,
    int id,
    String request,
    Future<List<Map<String, dynamic>>> Function(
      RecordEditData,
      Future<void> Function(String, Map<String, dynamic>),
    )
    make,
  ) async {
    if (!RegExp(r'^[a-f0-9]{24}$').hasMatch(request)) {
      fail('Mã yêu cầu không hợp lệ.');
    }
    await connect();
    final previous = await db.collection('_record_changes').findOne({
      '_id': request,
    });
    if (previous != null && previous['State'] != 'aborted') {
      if (previous['Kind'] != kind.name || previous['Parent'] != id) {
        fail('Mã yêu cầu đã được sử dụng.');
      }
      await _finish(request);
      return;
    }
    final s = specs[kind]!;
    final existing = await db.collection(s.$1).findOne({s.$2: id});
    if (existing?['SuaXoaDangLuu'] is String) {
      fail(
        'Phiếu có thay đổi chưa hoàn tất. Bấm Tiếp tục xử lý trước khi chỉnh tiếp.',
      );
    }
    final locks = <Map<String, dynamic>>[];
    var planned = false;
    Future<void> lock(String name, Map<String, dynamic> row) async {
      if (locks.any((l) => l['Collection'] == name && l['Id'] == row['_id'])) {
        return;
      }
      final held = await db
          .collection(name)
          .findAndModify(
            query: {
              '_id': row['_id'],
              'SuaXoaDangLuu': null,
              'ThanhToanDangLuu': null,
              if (name == 'NhapHang') 'NhapDangLuu': null,
              if (name == 'Xe') ...{
                'TinhTrang': row['TinhTrang'],
                'GiuChoBanHang': null,
                'DangNhapHang': null,
              },
              if (name == 'TonKhoPhuTung')
                r'$or': [
                  {'GiuChoBanHang': null},
                  {'GiuChoBanHang': {}},
                ],
              if (name == 'HoaDonBan') 'TrangThaiLuu': {r'$ne': 'dang_luu'},
            },
            update: {
              r'$set': {'SuaXoaDangLuu': request},
            },
            returnNew: true,
          );
      if (held == null) {
        fail('Phiếu/sản phẩm đang có giao dịch được lưu. Tải lại rồi thử lại.');
      }
      locks.add({'Collection': name, 'Id': row['_id']});
    }

    await checked(
      db
          .collection('_record_changes')
          .updateOne(
            {'_id': request},
            {
              r'$set': {
                'Kind': kind.name,
                'Parent': id,
                'State': 'preparing',
                'Date': DateTime.now().toUtc(),
              },
            },
            upsert: true,
          ),
    );
    try {
      if (existing == null) fail('Phiếu không còn tồn tại.');
      await lock(s.$1, existing);
      if (kind == RecordKind.order) {
        for (final debt in await db.collection('SoNo').find({
          'IdHoaDon': id,
        }).toList()) {
          await lock('SoNo', debt);
        }
      }
      final data = await _read(kind, id);
      final operations = await make(data, lock);
      await checked(
        db
            .collection('_record_changes')
            .updateOne(
              {'_id': request},
              {
                r'$set': {
                  'Operations': operations,
                  'DeleteParent': operations.any(
                    (step) =>
                        step['Collection'] == s.$1 &&
                        step['Id'] == data.header['_id'] &&
                        step['Fields'] == null,
                  ),
                  'Locks': locks,
                  'State': 'pending',
                },
              },
            ),
      );
      planned = true;
      await _finish(request);
    } catch (e) {
      if (planned) {
        throw RecordChangeException(
          'Chưa hoàn tất thay đổi. Bấm Thử lại để tiếp tục.',
          uncertain: true,
        );
      }
      rethrow;
    } finally {
      if (!planned) {
        await checked(
          db
              .collection('_record_changes')
              .updateOne(
                {'_id': request},
                {
                  r'$set': {'State': 'aborted'},
                },
              ),
        );
        for (final l in locks) {
          await checked(
            db
                .collection(l['Collection'] as String)
                .updateOne(
                  {'_id': l['Id'], 'SuaXoaDangLuu': request},
                  {
                    r'$unset': {'SuaXoaDangLuu': ''},
                  },
                ),
          );
        }
      }
    }
  }

  Future<List<Map<String, dynamic>>> _inventory(
    RecordEditData data,
    bool incoming,
    List<Map<String, dynamic>> edited,
    Future<void> Function(String, Map<String, dynamic>) lock, {
    bool deleting = false,
    bool removingLine = false,
  }) async {
    var original = data.lines;
    final id = data.header[incoming ? 'IdNhapHang' : 'IdHoaDon'];
    if (original.isEmpty) {
      if (!incoming && data.header['IdXe'] != null) {
        original = [
          {'IdXe': data.header['IdXe'], 'SoLuong': 1},
        ];
      } else if (incoming) {
        final extensions = await db.collection('XeMoi').find({
          'IdNhapHang': id,
        }).toList();
        final vehicles = await db.collection('Xe').find({
          r'$or': [
            {'IdNhapHang': id},
            if (extensions.isNotEmpty)
              {
                'IdXe': {r'$in': extensions.map((e) => e['IdXe']).toList()},
              },
          ],
        }).toList();
        original = [
          for (final v in vehicles)
            {'IdXe': v['IdXe'], 'IdSanPham': v['IdSanPham'], 'SoLuong': 1},
        ];
      }
      if (original.isEmpty && !deleting) return [];
      if (original.isEmpty && !incoming) {
        fail('Thiếu chi tiết sản phẩm để hoàn tồn kho.');
      }
    }
    if (incoming &&
        deleting &&
        original.any(
          (row) =>
              (row['ChiPhi'] as List? ?? []).any((c) => c['DaXoa'] != true) ||
              (row['TongChiPhi'] as num? ?? 0) > 0,
        )) {
      fail('Lô hàng còn chi phí sản phẩm. Cần xử lý chi phí trước khi xóa.');
    }
    final operations = <Map<String, dynamic>>[];
    final partDeltas = <dynamic, num>{};
    for (var index = 0; index < original.length; index++) {
      final old = original[index];
      final replacement = deleting
          ? null
          : edited.firstWhere((e) => e['_id'] == old['_id'], orElse: () => old);
      final oldQty = number(old['SoLuong']);
      final qty = replacement == null ? 0 : number(replacement['SoLuong']);
      if (old['IdXe'] != null) {
        final vehicle = await db.collection('Xe').findOne({
          'IdXe': old['IdXe'],
        });
        if (vehicle == null) fail('Không tìm thấy xe liên kết.');
        await lock('Xe', vehicle);
        if (incoming) {
          final hasSale =
              await db.collection('HoaDonBan').findOne({'IdXe': old['IdXe']}) ??
              await db.collection('ChiTietHoaDonBan').findOne({
                'IdXe': old['IdXe'],
              });
          if (hasSale != null || vehicle['TinhTrang'] != true) {
            fail('Lô có xe đã bán, không thể sửa giá nhập hoặc xóa.');
          }
          if (deleting) {
            if ((vehicle['ChiPhi'] as List? ?? []).any(
                  (c) => c['DaXoa'] != true,
                ) ||
                (vehicle['TongChiPhi'] as num? ?? 0) > 0) {
              fail('Xe còn chi phí liên quan, cần xử lý trước khi xóa lô.');
            }
            operations.add(op('Xe', vehicle['_id'], null));
            for (final name in ['XeMoi', 'XeCu']) {
              for (final ext in await db.collection(name).find({
                'IdXe': old['IdXe'],
              }).toList()) {
                operations.add(op(name, ext['_id'], null));
              }
            }
          } else {
            operations.add(
              op('Xe', vehicle['_id'], {
                'GiaNhap': number(replacement!['GiaNhap']),
              }),
            );
          }
        } else if (deleting) {
          final other =
              await db.collection('ChiTietHoaDonBan').findOne({
                'IdXe': old['IdXe'],
                'IdHoaDon': {r'$ne': id},
              }) ??
              await db.collection('HoaDonBan').findOne({
                'IdXe': old['IdXe'],
                'IdHoaDon': {r'$ne': id},
              });
          if (other != null) {
            fail('Xe đang có liên kết bán ở đơn khác, cần đối soát.');
          }
          operations.add(
            op(
              'Xe',
              vehicle['_id'],
              {'TinhTrang': true},
              unset: ['IdHoaDonBan'],
            ),
          );
        } else {
          if (replacement!['DonGia'] != vehicle['GiaBan']) {
            final other =
                await db.collection('HoaDonBan').findOne({
                  'IdXe': old['IdXe'],
                  'IdHoaDon': {r'$ne': id},
                }) ??
                await db.collection('ChiTietHoaDonBan').findOne({
                  'IdXe': old['IdXe'],
                  'IdHoaDon': {r'$ne': id},
                });
            if (other != null) {
              fail('Xe có nhiều đơn bán cũ, cần đối soát trước khi sửa giá.');
            }
          }
          operations.add(
            op('Xe', vehicle['_id'], {'GiaBan': number(replacement['DonGia'])}),
          );
        }
      } else if (old['IdDichVu'] == null && old['LoaiSanPham'] != 'dich_vu') {
        final product = old['IdSanPham'];
        if (product == null) fail('Thiếu liên kết phụ tùng.');
        partDeltas[product] =
            (partDeltas[product] ?? 0) +
            (incoming ? qty - oldQty : oldQty - qty);
      }
    }
    for (final entry in partDeltas.entries) {
      final stock = await db.collection('TonKhoPhuTung').findOne({
        'IdSanPham': entry.key,
      });
      if (stock == null) fail('Chưa có bản ghi tồn kho phụ tùng.');
      await lock('TonKhoPhuTung', stock);
      final latest = (await db.collection('TonKhoPhuTung').findOne({
        '_id': stock['_id'],
      }))!;
      final quantity = number(latest['SoLuongTon']) + entry.value;
      if (quantity < 0) fail('Không đủ tồn kho phụ tùng để sửa/xóa lô.');
      final stockChanges = <String, dynamic>{'SoLuongTon': quantity};
      if (incoming && deleting) {
        final receipts = await db.collection('ChiTietNhapHang').find({
          'IdSanPham': entry.key,
          'IdXe': null,
          if (!removingLine) 'IdNhapHang': {r'$ne': id},
          if (removingLine)
            '_id': {r'$nin': original.map((r) => r['_id']).toList()},
        }).toList();
        final headers = await db
            .collection('NhapHang')
            .modernFind(
              filter: {
                'IdNhapHang': {
                  r'$in': receipts.map((r) => r['IdNhapHang']).toList(),
                },
              },
              sort: {'NgayNhap': -1, 'IdNhapHang': -1},
            )
            .toList();
        num? cost;
        for (final header in headers) {
          final prices = receipts
              .where(
                (r) =>
                    r['IdNhapHang'] == header['IdNhapHang'] &&
                    r['GiaNhap'] is num,
              )
              .toList();
          if (prices.isNotEmpty) {
            cost = prices.last['GiaNhap'] as num;
            break;
          }
        }
        stockChanges['GiaVonThamKhao'] = cost;
      }
      operations.add(op('TonKhoPhuTung', stock['_id'], stockChanges));
    }
    return operations;
  }

  @override
  Future<void> save(
    RecordKind kind,
    int id,
    Map<String, dynamic> fields,
    List<Map<String, dynamic>> lines, {
    required String requestId,
  }) => _run(kind, id, requestId, (data, lock) async {
    if (kind == RecordKind.cash) {
      if (_managedCash(data.header))
        fail(
          'Phiếu tự sinh: sửa/xóa tại sản phẩm hoặc phiếu trả nợ gốc để đồng bộ số liệu.',
        );
      if (fields['NgayThang'] is! DateTime || fields['ThuChi'] is! bool)
        fail('Chọn ngày và loại phiếu.');
      final amount = number(fields['SoTien']);
      if (amount <= 0) fail('Số tiền phải lớn hơn 0.');
      final categories = (data.header['_CashCategories'] as List).cast<Map>();
      final matching = categories
          .where(
            (c) =>
                c['_id'] == fields['IdDanhMuc'] &&
                c['ThuChi'] == fields['ThuChi'],
          )
          .toList();
      if (matching.length != 1) fail('Chọn danh mục phù hợp với loại phiếu.');
      return [
        op('ThuChiKhac', data.header['_id'], {
          'NgayThang': day(fields['NgayThang']),
          'ThuChi': fields['ThuChi'],
          'SoTien': amount,
          'IdDanhMuc': matching.single['_id'],
          'TenDanhMuc': matching.single['TenDanhMuc'],
          'LyDo': '${fields['LyDo'] ?? ''}'.trim(),
        }),
      ];
    }
    if (kind == RecordKind.pawn) {
      final draft = PawnDraft()
        ..customerId = (fields['IdKhachHang'] as num?)?.toInt()
        ..asset = '${fields['TaiSanTheChap'] ?? ''}'
        ..amount = '${fields['SoTienVay'] ?? ''}'.replaceFirst(
          RegExp(r'\.0$'),
          '',
        )
        ..rate = '${fields['LaiSuat'] ?? ''}'
        ..notes = '${fields['GhiChu'] ?? ''}'
        ..daily = fields['NgayPhanTram'] == true
        ..closed = fields['TrangThai'] == true;
      if (fields['NgayVay'] is! DateTime ||
          fields['NgayHan'] is! DateTime ||
          fields['NgayPhanTram'] is! bool)
        fail('Chọn ngày vay, ngày hạn và kiểu lãi.');
      draft.loanDate = fields['NgayVay'];
      draft.dueDate = fields['NgayHan'];
      final error = draft.validate();
      if (error != null) fail(error);
      final customer = await db.collection('KhachHang').findOne({
        'IdKH': draft.customerId,
        'DaXoa': {r'$ne': true},
      });
      if (customer == null && draft.customerId != data.header['IdKhachHang'])
        fail('Khách hàng không còn tồn tại.');
      final principal = num.parse(draft.amount);
      final paid = data.payments.fold<num>(
        0,
        (sum, p) => sum + number(p['TienGoc']),
      );
      if (principal < paid) fail('Tiền vay không được thấp hơn gốc đã thu.');
      if (data.payments.any(
        (p) =>
            p['NgayTra'] is DateTime &&
            day(p['NgayTra']).isBefore(day(draft.loanDate)),
      ))
        fail('Ngày vay không được sau ngày đã thanh toán.');
      // Existing interest collections cannot be reinterpreted by changing their contract.
      if (data.payments.isNotEmpty &&
          (draft.customerId != data.header['IdKhachHang'] ||
              draft.daily != data.header['NgayPhanTram'] ||
              draft.interestRate != data.header['LaiSuat'] ||
              day(draft.loanDate) != day(data.header['NgayVay'])))
        fail(
          'Phiếu đã có thanh toán: giữ nguyên khách hàng, ngày vay và cách tính lãi.',
        );
      if (draft.closed && paid < principal && data.header['TrangThai'] != true)
        fail('Chưa thu đủ gốc để đánh dấu đã chuộc.');
      return [
        op('CamDo', data.header['_id'], {
          ...draft.toFields(),
          'TrangThai': paid == principal || draft.closed,
          'NgayCapNhat': DateTime.now().toUtc(),
        }),
      ];
    }
    if (kind != RecordKind.order && kind != RecordKind.batch) {
      fail('Loại phiếu chưa hỗ trợ sửa thông tin.');
    }
    final h = data.header, incoming = kind == RecordKind.batch;
    final dateKey = incoming ? 'NgayNhap' : 'NgayMua';
    final date = fields[dateKey];
    if (date is! DateTime) fail('Vui lòng nhập ngày phiếu.');
    if (data.payments.any(
      (p) => p['NgayTra'] is DateTime && day(p['NgayTra']).isBefore(day(date)),
    )) {
      fail('Ngày phiếu không được sau ngày đã thanh toán.');
    }
    final changes = <String, dynamic>{
      dateKey: day(date),
      'GhiChu': '${fields['GhiChu'] ?? ''}'.trim(),
      'NgayCapNhat': DateTime.now().toUtc(),
    };
    final operations = <Map<String, dynamic>>[];
    if (incoming) {
      for (final ref in [
        ('IdDoiTac', 'NoiNhap', 'DoiTac', 'TenDoiTac'),
        ('IdVanChuyen', 'NguoiCho', 'VanChuyen', 'TenVanChuyen'),
      ]) {
        final selected = fields.containsKey(ref.$1)
            ? fields[ref.$1]
            : h[ref.$1];
        if (selected != null && selected != '') {
          final entry = await db.collection(ref.$3).findOne({
            '_id': selected,
            'DaXoa': {r'$ne': true},
          });
          if (entry == null && selected != h[ref.$1]) {
            fail('Đối tác/vận chuyển không còn hợp lệ.');
          }
          changes[ref.$1] = selected;
          changes[ref.$2] = entry?[ref.$4] ?? h[ref.$2];
        } else {
          changes[ref.$1] = null;
          changes[ref.$2] = '';
        }
      }
      final total = number(fields['SoTien']);
      final paid = number(h['SoTienDaTra']);
      if (total < paid) fail('Tổng tiền không được thấp hơn số đã thanh toán.');
      changes.addAll({
        'SoTien': total,
        'SoTienConNo': total - paid,
        'SoLuong': number(fields['SoLuong']),
      });
    } else {
      final customerId = fields['IdKH'];
      if (customerId != null) {
        if (await db.collection('KhachHang').findOne({
              'IdKH': customerId,
              'DaXoa': {r'$ne': true},
              'KhoaGop': {r'$exists': false},
            }) ==
            null) {
          fail('Khách hàng không còn hợp lệ.');
        }
      }
      changes['IdKH'] = customerId;
      num goods = 0;
      if (data.lines.isEmpty) {
        // Legacy invoices use their linked vehicle's actual selling price.
        final vehicle = h['IdXe'] == null
            ? null
            : await db.collection('Xe').findOne({'IdXe': h['IdXe']});
        goods = number(h['TongTienHang'] ?? vehicle?['GiaBan']);
      } else {
        if (lines.length != data.lines.length ||
            lines.map((l) => l['_id']).toSet().length != lines.length ||
            lines.any(
              (l) => !data.lines.any((old) => old['_id'] == l['_id']),
            )) {
          fail('Danh sách sản phẩm đã thay đổi. Tải lại đơn hàng.');
        }
        for (final line in lines) {
          final original = data.lines.firstWhere(
            (l) => l['_id'] == line['_id'],
          );
          final qty = number(line['SoLuong']), price = number(line['DonGia']);
          if (qty <= 0 ||
              qty != qty.roundToDouble() ||
              (original['IdXe'] != null && qty != 1)) {
            fail('Số lượng phải nguyên dương; xe có số lượng 1.');
          }
          goods += qty * price;
          operations.add({
            ...op('ChiTietHoaDonBan', original['_id'], {
              if (original['_Synthetic'] == true) ...{
                'IdHoaDon': id,
                'IdXe': original['IdXe'],
                'IdSanPham': original['IdSanPham'],
                'TenSanPham': original['TenSanPham'],
              },
              'SoLuong': qty,
              'DonGia': price,
              'ThanhTien': qty * price,
            }),
            if (original['_Synthetic'] == true) 'Upsert': true,
          });
        }
        operations.addAll(await _inventory(data, false, lines, lock));
      }
      final discount = number(fields['GiamGia'] ?? 0);
      if (discount > goods) fail('Giảm giá không được vượt tiền hàng.');
      final total = goods - discount;
      final debt = Map<String, dynamic>.from(h['_SoNo'] as Map);
      final paid = number(debt['SoTienDaTra']);
      if (total < paid) {
        fail(
          'Tổng thanh toán không được thấp hơn số đã thu. Sửa phiếu thu trước.',
        );
      }
      changes.addAll({
        'TongTienHang': goods,
        'GiamGia': discount,
        'TongThanhToan': total,
        'SoTienDaTra': paid,
        'SoTienConNo': total - paid,
      });
      for (final key in ['NgayHen', 'NgayTinhLai']) {
        if (fields[key] is DateTime) changes[key] = day(fields[key]);
      }
      operations.add(op('SoNo', debt['_id'], {'SoTienConNo': total - paid}));
    }
    operations.add(op(specs[kind]!.$1, h['_id'], changes));
    // The remaining snapshots must follow the edited total, not the old total.
    final due = number(changes['SoTienConNo']);
    num cursor =
        due +
        data.payments.fold<num>(
          0,
          (sum, p) => sum + number(p[specs[kind]!.$5]),
        );
    for (final payment in data.payments) {
      cursor -= number(payment[specs[kind]!.$5]);
      operations.add(
        op(specs[kind]!.$3, payment['_id'], {specs[kind]!.$7: cursor}),
      );
    }
    return operations;
  });

  @override
  Future<void> delete(
    RecordKind kind,
    int id, {
    required String requestId,
  }) => _run(kind, id, requestId, (data, lock) async {
    if (kind == RecordKind.cash) {
      if (_managedCash(data.header))
        fail(
          'Phiếu tự sinh: xóa tại sản phẩm hoặc phiếu trả nợ gốc để đồng bộ số liệu.',
        );
      return [op('ThuChiKhac', data.header['_id'], null)];
    }
    if (kind == RecordKind.pawn) {
      return [
        for (final payment in data.payments)
          op('TraNoCamDo', payment['_id'], null),
        op('CamDo', data.header['_id'], null),
      ];
    }
    if (kind != RecordKind.order && kind != RecordKind.batch) {
      fail('Loại phiếu chưa hỗ trợ xóa.');
    }
    final incoming = kind == RecordKind.batch;
    final operations = await _inventory(
      data,
      incoming,
      [],
      lock,
      deleting: true,
    );
    for (final line in data.lines) {
      operations.add(
        op(
          incoming ? 'ChiTietNhapHang' : 'ChiTietHoaDonBan',
          line['_id'],
          null,
        ),
      );
    }
    for (final payment in data.payments) {
      operations.add(op(specs[kind]!.$3, payment['_id'], null));
      if (!incoming) operations.addAll(await _interestCash(payment, null));
    }
    if (!incoming) {
      final debt = Map<String, dynamic>.from(data.header['_SoNo'] as Map);
      operations.add(op('SoNo', debt['_id'], null));
    }
    // Converted purchase headers must not keep orphaned links to a removed lot.
    if (incoming) {
      for (final old in await db.collection('HoaDonMua').find({
        'IdNhapHang': id,
      }).toList()) {
        if (await db.collection('SoNoMua').findOne({
              'IdHoaDon': old['IdHoaDon'],
            }) !=
            null) {
          fail('Phiếu mua cũ còn sổ nợ riêng, cần đối soát trước khi xóa.');
        }
        operations.add(op('HoaDonMua', old['_id'], null));
      }
    }
    operations.add(op(specs[kind]!.$1, data.header['_id'], null));
    return operations;
  });

  bool _managedCash(Map<String, dynamic> row) =>
      row['Nguon'] != null ||
      row['IdPhieuTraNo'] != null ||
      '${row['_id']}'.startsWith('order-interest-') ||
      '${row['_id']}'.startsWith('record-interest-');

  @override
  Future<void> removeLine(
    RecordKind kind,
    int id,
    dynamic lineId, {
    required String requestId,
  }) => _run(kind, id, requestId, (data, lock) async {
    if (kind != RecordKind.order && kind != RecordKind.batch)
      fail('Loại phiếu không có sản phẩm.');
    final matches = data.lines.where((l) => l['_id'] == lineId).toList();
    if (matches.length != 1)
      fail('Sản phẩm không còn trong phiếu. Tải lại danh sách.');
    final line = matches.single, incoming = kind == RecordKind.batch;
    final remaining = data.lines.where((l) => l['_id'] != lineId).toList();
    final ops = await _inventory(
      RecordEditData(data.header, [line], data.payments),
      incoming,
      [],
      lock,
      deleting: true,
      removingLine: true,
    );
    ops.add(
      op(incoming ? 'ChiTietNhapHang' : 'ChiTietHoaDonBan', lineId, null),
    );
    final changes = <String, dynamic>{};
    num paid;
    if (incoming) {
      final total =
          number(data.header['SoTien']) -
          number(line['GiaNhap']) * number(line['SoLuong']);
      paid = number(data.header['SoTienDaTra']);
      if (total < paid)
        fail(
          'Tổng lô sau xóa thấp hơn số đã trả. Điều chỉnh phiếu thanh toán trước.',
        );
      changes.addAll({
        'SoTien': total,
        'SoTienConNo': total - paid,
        'SoLuong': (number(data.header['SoLuong']) - number(line['SoLuong']))
            .clamp(0, 1e15),
      });
    } else {
      final goods = remaining.fold<num>(
        0,
        (sum, l) => sum + number(l['DonGia']) * number(l['SoLuong']),
      );
      final discount = number(data.header['GiamGia'] ?? 0);
      if (discount > goods)
        fail(
          'Giảm giá đang vượt tiền hàng sau xóa. Điều chỉnh giảm giá trước.',
        );
      final debt = Map<String, dynamic>.from(data.header['_SoNo'] as Map);
      paid = number(debt['SoTienDaTra']);
      if (goods - discount < paid)
        fail(
          'Tổng đơn sau xóa thấp hơn số đã thu. Điều chỉnh phiếu trả nợ trước.',
        );
      changes.addAll({
        'TongTienHang': goods,
        'TongThanhToan': goods - discount,
        'SoTienConNo': goods - discount - paid,
        'IdXe': null,
        'IdSanPham': null,
      });
      ops.add(
        op('SoNo', debt['_id'], {'SoTienConNo': goods - discount - paid}),
      );
    }
    ops.add(op(specs[kind]!.$1, data.header['_id'], changes));
    num cursor =
        number(changes['SoTienConNo']) +
        data.payments.fold<num>(0, (s, p) => s + number(p[specs[kind]!.$5]));
    for (final payment in data.payments) {
      cursor -= number(payment[specs[kind]!.$5]);
      ops.add(op(specs[kind]!.$3, payment['_id'], {specs[kind]!.$7: cursor}));
    }
    return ops;
  });

  @override
  Future<void> deleteCost(
    bool vehicle,
    int productId,
    Map<String, dynamic> cost, {
    required String requestId,
  }) => _run(
    vehicle ? RecordKind.vehicleProduct : RecordKind.partProduct,
    productId,
    requestId,
    (data, lock) async {
      final source = '${cost['_CostCollection']}';
      final sourceId = cost['_CostDocument'];
      if (!['Xe', 'SanPham', 'ChiTietNhapHang'].contains(source))
        fail('Không xác định được nguồn chi phí. Tải lại sản phẩm.');
      final row = await db.collection(source).findOne({'_id': sourceId});
      final owner = row?[vehicle ? 'IdXe' : 'IdSanPham'];
      if (row == null || !_sameId(owner, productId))
        fail('Chi phí không thuộc sản phẩm này.');
      await lock(source, row);
      final entries = [
        for (final raw in row['ChiPhi'] as List? ?? [])
          Map<String, dynamic>.from(raw as Map),
      ];
      final index = _costIndex(entries, cost);
      if (index < 0) fail('Chi phí không còn tồn tại. Tải lại danh sách.');
      final selected = entries[index];
      if (selected['DaXoa'] == true) return <Map<String, dynamic>>[];
      entries[index] = {
        ...selected,
        'DaXoa': true,
        'NgayXoa': DateTime.now().toUtc(),
      };
      final total = entries
          .where((e) => e['DaXoa'] != true)
          .fold<num>(0, (s, e) => s + number(e['SoTien']));
      final key = '${selected['MaYeuCau'] ?? 'legacy-$index'}';
      final cashProductId = source == 'ChiTietNhapHang' ? sourceId : productId;
      final cashId = 'product-cost-$source-$cashProductId-$key';
      final ops = <Map<String, dynamic>>[
        op(source, sourceId, {'ChiPhi': entries, 'TongChiPhi': total}),
      ];
      if (await db.collection('ThuChiKhac').findOne({'_id': cashId}) != null)
        ops.add(op('ThuChiKhac', cashId, null));
      // Vehicle receipt snapshots mirror the source expense; keep them consistent too.
      if (vehicle && source == 'Xe') {
        for (final detail in await db.collection('ChiTietNhapHang').find({
          'IdXe': productId,
        }).toList()) {
          final mirrors = [
            for (final raw in detail['ChiPhi'] as List? ?? [])
              Map<String, dynamic>.from(raw as Map),
          ];
          final mirrorIndex = _costIndex(mirrors, selected);
          if (mirrorIndex >= 0) {
            await lock('ChiTietNhapHang', detail);
            mirrors[mirrorIndex] = {...mirrors[mirrorIndex], 'DaXoa': true};
            ops.add(
              op('ChiTietNhapHang', detail['_id'], {
                'ChiPhi': mirrors,
                'TongChiPhi': mirrors
                    .where((c) => c['DaXoa'] != true)
                    .fold<num>(0, (s, c) => s + number(c['SoTien'])),
              }),
            );
          }
        }
      }
      return ops;
    },
  );

  Future<List<Map<String, dynamic>>> _interestCash(
    Map<String, dynamic> old,
    Map<String, dynamic>? replacement,
  ) async {
    final id = '${old['_id']}';
    final cashId = id.startsWith('order-payment-')
        ? id.replaceFirst('order-payment-', 'order-interest-')
        : 'record-interest-$id';
    final cash = await db.collection('ThuChiKhac').findOne({'_id': cashId});
    final result = <Map<String, dynamic>>[];
    if (cash != null) {
      final interest = replacement == null
          ? 0
          : number(replacement['LaiThu'] ?? 0);
      result.add(
        op(
          'ThuChiKhac',
          cash['_id'],
          interest == 0
              ? null
              : {'SoTien': interest, 'NgayThang': replacement!['NgayTra']},
        ),
      );
    } else if (replacement != null && number(replacement['LaiThu'] ?? 0) > 0) {
      // Reuse the deterministic payment key; allocate a display ID through the existing counter.
      final counters = db.collection('_app_counters');
      final last = await db
          .collection('ThuChiKhac')
          .modernFind(sort: {'ThuChiId': -1}, limit: 1)
          .toList();
      await checked(
        counters.updateOne(
          {'_id': 'ThuChiKhac'},
          {
            r'$max': {'value': last.isEmpty ? 0 : last.first['ThuChiId']},
          },
          upsert: true,
        ),
      );
      final counter = await counters.findAndModify(
        query: {'_id': 'ThuChiKhac'},
        update: {
          r'$inc': {'value': 1},
        },
        returnNew: true,
      );
      result.add({
        ...op('ThuChiKhac', cashId, {
          'ThuChiId': counter!['value'],
          'SoTien': replacement['LaiThu'],
          'NgayThang': replacement['NgayTra'],
          'ThuChi': true,
          'IdDanhMuc': 'customer-interest',
          'TenDanhMuc': 'Lãi khách hàng trả nợ',
          'IdHoaDon': replacement['_OrderId'],
          'LyDo': replacement['_InterestMemo'],
        }),
        'Upsert': true,
      });
    }
    return result;
  }

  @override
  Future<void> payment(
    RecordKind kind,
    int parentId,
    dynamic paymentId,
    Map<String, dynamic>? fields, {
    required String requestId,
    DateTime? interestStart,
    DateTime? nextAppointment,
  }) => _run(kind, parentId, requestId, (data, lock) async {
    final s = specs[kind]!, h = data.header;
    final found = data.payments
        .where(
          (p) =>
              p['_id'] == paymentId ||
              p[kind == RecordKind.order
                      ? 'IdTraNo'
                      : kind == RecordKind.batch
                      ? 'IdTraNoNhapHang'
                      : kind == RecordKind.pawn
                      ? 'IdTraNoCamDo'
                      : kind == RecordKind.funding
                      ? 'IdTraNoVayVon'
                      : 'Id'] ==
                  paymentId,
        )
        .toList();
    if (found.length != 1) fail('Phiếu trả nợ không còn tồn tại.');
    final old = found.single;
    final edited = fields == null ? null : <String, dynamic>{...old};
    final allowed = [
      'NgayTra',
      s.$5,
      if (s.$6.isNotEmpty) s.$6,
      'GhiChu',
      if (kind == RecordKind.order) 'SoTienLai',
      if (kind == RecordKind.pawn) 'LaiThu',
      if (kind == RecordKind.openingDebt) 'TienLai',
      if (kind == RecordKind.order) 'NgayHenSauTra',
      if (kind == RecordKind.pawn) 'NgayHen',
    ];
    if (edited != null) {
      for (final key in allowed) {
        if (fields!.containsKey(key)) edited[key] = fields[key];
      }
      if (edited['NgayTra'] is! DateTime) fail('Vui lòng chọn ngày trả.');
      edited['NgayTra'] = day(edited['NgayTra']);
      final start =
          h[kind == RecordKind.order
              ? 'NgayMua'
              : kind == RecordKind.batch
              ? 'NgayNhap'
              : 'NgayVay'];
      if (start is DateTime &&
          (edited['NgayTra'] as DateTime).isBefore(day(start))) {
        fail('Ngày trả không được trước ngày phiếu gốc.');
      }
      for (final key in [
        s.$5,
        if (s.$6.isNotEmpty) s.$6,
        if (kind == RecordKind.order) 'SoTienLai',
        if (kind == RecordKind.pawn) 'LaiThu',
        if (kind == RecordKind.openingDebt) 'TienLai',
      ]) {
        number(edited[key] ?? 0);
      }
      if (number(edited[s.$5]) +
              (s.$6.isEmpty ? 0 : number(edited[s.$6] ?? 0)) <=
          0) {
        fail('Số tiền thanh toán phải lớn hơn 0.');
      }
      for (final key in ['NgayHen', 'NgayHenSauTra']) {
        if (edited[key] is DateTime &&
            (edited[key] as DateTime).isBefore(edited['NgayTra'])) {
          fail('Ngày hẹn không được trước ngày trả.');
        }
      }
    }
    final rows =
        [
          for (final p in data.payments)
            if (p['_id'] != old['_id']) p,
          ?edited,
        ]..sort((a, b) {
          final date = (a['NgayTra'] as DateTime).compareTo(
            b['NgayTra'] as DateTime,
          );
          return date == 0 ? '${a['_id']}'.compareTo('${b['_id']}') : date;
        });
    final delta =
        (edited == null ? 0 : number(edited[s.$5])) - number(old[s.$5]);
    final ops = <Map<String, dynamic>>[];
    final changes = <String, dynamic>{};
    num remaining;
    if (kind == RecordKind.pawn) {
      remaining =
          number(h['SoTienVay']) -
          rows.fold<num>(0, (sum, p) => sum + number(p[s.$5]));
      changes['TrangThai'] = remaining == 0;
    } else {
      final balance = kind == RecordKind.order
          ? Map<String, dynamic>.from(h['_SoNo'] as Map)
          : h;
      final dueKey = kind == RecordKind.funding
          ? 'TongConNo'
          : kind == RecordKind.openingDebt
          ? 'SoCoNo'
          : 'SoTienConNo';
      remaining = number(balance[dueKey]) - delta;
      final update = <String, dynamic>{dueKey: remaining};
      if (kind != RecordKind.funding) {
        final paid = number(balance['SoTienDaTra']) + delta;
        if (paid < 0) fail('Số đã trả sau điều chỉnh không được âm.');
        update['SoTienDaTra'] = paid;
      }
      if (kind == RecordKind.order) {
        ops.add(op('SoNo', balance['_id'], update));
        changes.addAll(update);
        if (h['PhienBanBanHang'] == 3) {
          changes['SoTienKhachDua'] =
              (update['SoTienDaTra'] as num) + (h['TienThua'] as num? ?? 0);
        }
      } else {
        changes.addAll(update);
      }
    }
    if (remaining < 0) fail('Tiền trả nợ vượt quá tổng nợ.');
    // Rebuild running principal balances without inventing missing legacy payments.
    num cursor =
        remaining + rows.fold<num>(0, (sum, p) => sum + number(p[s.$5]));
    for (final row in rows) {
      cursor -= number(row[s.$5]);
      if (cursor < 0) fail('Lịch sử trả gốc không hợp lệ.');
      if (s.$7.isNotEmpty) ops.add(op(s.$3, row['_id'], {s.$7: cursor}));
    }
    if (kind != RecordKind.batch && kind != RecordKind.pawn) {
      final oldInterest = data.payments
          .where((p) => (p[s.$6] as num? ?? 0) > 0)
          .toList();
      final interestRows = rows
          .where((p) => (p[s.$6] as num? ?? 0) > 0)
          .toList();
      final base =
          h['NgayTinhLaiGoc'] ??
          (oldInterest.isEmpty
              ? h['NgayTinhLai']
              : oldInterest.first['NgayTinhLaiTruocTra']);
      final changedInterestPeriod =
          (old[s.$6] as num? ?? 0) > 0 || (edited?[s.$6] as num? ?? 0) > 0;
      final anchor =
          interestStart ??
          (interestRows.isNotEmpty ? interestRows.last['NgayTra'] : base);
      if (changedInterestPeriod && anchor is! DateTime) {
        fail(
          'Thiếu ngày tính lãi gốc. Chọn ngày tính lãi sau điều chỉnh để tiếp tục.',
        );
      }
      if (anchor is DateTime) changes['NgayTinhLai'] = day(anchor);
      if (base is DateTime) changes['NgayTinhLaiGoc'] = day(base);
    }
    final appointmentKey = kind == RecordKind.order
        ? 'NgayHenSauTra'
        : 'NgayHen';
    if (kind == RecordKind.order || kind == RecordKind.pawn) {
      final appointments = rows
          .where((p) => p[appointmentKey] is DateTime)
          .toList();
      final originals = data.payments
          .where((p) => p[appointmentKey] is DateTime)
          .toList();
      final initial =
          h['NgayHenGoc'] ??
          (originals.isEmpty
              ? h[kind == RecordKind.pawn ? 'NgayHan' : 'NgayHen']
              : originals.first['NgayHenTruocTra']);
      final appointment =
          nextAppointment ??
          (appointments.isNotEmpty
              ? appointments.last[appointmentKey]
              : initial);
      if (old[appointmentKey] is DateTime && appointment is! DateTime) {
        fail('Thiếu ngày hẹn gốc. Chọn ngày hẹn sau điều chỉnh để tiếp tục.');
      }
      if (appointment is DateTime) {
        changes[kind == RecordKind.pawn ? 'NgayHan' : 'NgayHen'] = appointment;
      }
    }
    if (edited == null) {
      ops.add(op(s.$3, old['_id'], null));
    } else {
      final changed = <String, dynamic>{
        for (final key in allowed)
          if (fields!.containsKey(key)) key: edited[key],
      };
      if (kind == RecordKind.order) {
        final customer = await db.collection('KhachHang').findOne({
          'IdKH': h['IdKH'],
        });
        edited['_OrderId'] = parentId;
        edited['_InterestMemo'] =
            'Thu tiền lãi của khách hàng ${customer?['TenKhachHang'] ?? ''} mã đơn hàng $parentId';
      }
      ops.add(op(s.$3, old['_id'], changed));
    }
    if (kind == RecordKind.order) ops.addAll(await _interestCash(old, edited));
    ops.add(op(s.$1, h['_id'], changes));
    return ops;
  });
}
