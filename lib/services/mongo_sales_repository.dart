import 'dart:convert';
import 'dart:async';
import 'package:mongo_dart/mongo_dart.dart';
import 'mongo_sync_journal.dart';
import '../core/config/database_config.dart';
import '../models/repositories/sales_repository.dart';
import '../models/sales/sale_models.dart';

/// Durable, idempotent write journal for the local standalone MongoDB.
/// Reserve atomically, then either release before commit or roll forward after it.
class MongoSalesRepository implements SalesRepository {
  MongoSalesRepository({String? uri, this.checkpoint})
    : _db = SyncTrackedDb(uri ?? DatabaseConfig.mongoUri);
  final Db _db;
  final Future<void> Function(String)? checkpoint;
  final String _owner = ObjectId().oid;
  Future<void>? _opening;
  Future<void> _tail = Future.value();
  Future<T> _serial<T>(Future<T> Function() action) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      return await action();
    } finally {
      done.complete();
    }
  }

  Future<void> _connect() => _opening ??= _open().whenComplete(() {
    _opening = null;
  });
  Future<void> _open() async {
    if (!_db.isConnected) await _db.open(writeConcern: WriteConcern.journaled);
    if (await _db.collection('_sql_metadata').findOne({
          '_id': 'sales_schema_v3',
        }) ==
        null) {
      throw const SaleSaveException(
        'Cần cập nhật cấu trúc dữ liệu bán hàng trước khi lưu.',
      );
    }
  }

  DbCollection get _journal => _db.collection('GiaoDichBanHang');
  Future<void> _point(String point) async {
    if (checkpoint != null) await checkpoint!(point);
  }

  String _canonical(dynamic value) {
    dynamic sorted(dynamic v) {
      if (v is Map) {
        final keys = v.keys.map((k) => k.toString()).toList()..sort();
        return {for (final k in keys) k: sorted(v[k])};
      }
      if (v is List) return v.map(sorted).toList();
      return v;
    }

    return jsonEncode(sorted(value));
  }

  Future<int> _next(String name, String field) async {
    final last = await _db
        .collection(name)
        .modernFind(sort: {field: -1}, limit: 1)
        .toList();
    final highest = last.isEmpty ? 0 : last.first[field] as int;
    final counter = _db.collection('_app_counters');
    await counter.findAndModify(
      query: {'_id': name},
      update: {
        r'$max': {'value': highest},
      },
      upsert: true,
    );
    final row = await counter.findAndModify(
      query: {'_id': name},
      update: {
        r'$inc': {'value': 1},
      },
      returnNew: true,
    );
    return row!['value'] as int;
  }

  @override
  Future<SaleSaveResult> save(SaleDraft draft, String requestId) =>
      _serial(() => _save(draft, requestId));
  Future<SaleSaveResult> _save(SaleDraft draft, String requestId) async {
    if (draft.error != null) throw SaleSaveException(draft.error!);
    if (!RegExp(r'^[a-f0-9]{24}$').hasMatch(requestId)) {
      throw const SaleSaveException('Mã yêu cầu lưu không hợp lệ.');
    }
    try {
      await _connect();
      var operation = await _journal.findOne({'_id': requestId});
      if (operation == null) {
        if (draft.debtDatesVersion < 1) {
          throw const SaleSaveException(
            'Vui lòng tạo lại đơn bằng biểu mẫu có thông tin ngày công nợ.',
          );
        }
        final planned = <String, dynamic>{
          '_id': requestId,
          'Payload': draft.toMap(),
          'IdHoaDon': await _next('HoaDonBan', 'IdHoaDon'),
          'IdSoNo': await _next('SoNo', 'IdSoNo'),
          'IdTraNo': await _next('TraNo', 'IdTraNo'),
          'TrangThai': 'dang_xu_ly',
          'Buoc': 'giu_hang',
          'NgayTao': DateTime.now().toUtc(),
        };
        try {
          final result = await _journal.insertOne(planned);
          if (!result.isSuccess || result.hasWriteErrors) {
            throw StateError('Journal insert failed');
          }
        } catch (_) {
          operation = await _journal.findOne({'_id': requestId});
          if (operation == null) rethrow;
        }
        operation ??= planned;
      }
      if (_canonical(operation['Payload']) != _canonical(draft.toMap())) {
        throw const SaleSaveException(
          'Đơn đang chờ xác nhận có nội dung khác. Vui lòng giữ nguyên và thử lại.',
          uncertain: true,
        );
      }
      return await _resume(operation);
    } on SaleSaveException {
      rethrow;
    } catch (_) {
      throw const SaleSaveException(
        'Chưa xác nhận được kết quả lưu. Giữ nguyên đơn và bấm Thử lưu lại để tránh tạo trùng.',
        uncertain: true,
      );
    }
  }

  Future<void> _state(String id, Map<String, dynamic> fields) async {
    final updated = await _journal.findAndModify(
      query: {'_id': id, 'ChuKhoa': _owner, 'TrangThai': 'dang_xu_ly'},
      update: {
        r'$set': {
          ...fields,
          'KhoaDen': DateTime.now().toUtc().add(const Duration(seconds: 60)),
        },
      },
      returnNew: true,
    );
    if (updated == null) {
      throw const SaleSaveException(
        'Đơn đang được xử lý, vui lòng thử lưu lại.',
        uncertain: true,
      );
    }
  }

  Future<SaleSaveResult> _resume(Map<String, dynamic> op) async {
    final id = op['_id'] as String;
    if (op['TrangThai'] == 'hoan_tat') {
      return SaleSaveResult(op['IdHoaDon'] as int, requestId: id);
    }
    if (op['TrangThai'] == 'da_huy') {
      throw SaleSaveException(
        op['Loi'] as String? ??
            'Đơn chưa được lưu. Vui lòng kiểm tra hàng và thử lại.',
      );
    }
    final now = DateTime.now().toUtc();
    final acquired = await _journal.findAndModify(
      query: {
        '_id': id,
        'TrangThai': 'dang_xu_ly',
        r'$or': [
          {'ChuKhoa': _owner},
          {
            'KhoaDen': {r'$lte': now},
          },
          {
            'KhoaDen': {r'$exists': false},
          },
        ],
      },
      update: {
        r'$set': {
          'ChuKhoa': _owner,
          'KhoaDen': now.add(const Duration(seconds: 60)),
        },
      },
      returnNew: true,
    );
    if (acquired == null) {
      throw const SaleSaveException(
        'Đơn đang được xử lý, vui lòng thử lưu lại.',
        uncertain: true,
      );
    }
    op = acquired;
    final draft = SaleDraft.fromMap(
      Map<String, dynamic>.from(op['Payload'] as Map),
    );
    if (op['Buoc'] == 'hoan_tra') {
      await _rollback(id, draft);
      await _state(id, {'TrangThai': 'da_huy', 'Buoc': 'da_huy'});
      throw SaleSaveException(op['Loi'] as String? ?? 'Đơn chưa được lưu.');
    }
    if (op['Buoc'] == 'giu_hang') {
      try {
        await _reserveCustomer(id, draft);
        for (final line in draft.lines) {
          await _state(id, {});
          await _reserve(id, line);
          await _point('afterReserve');
        }
      } on SaleSaveException catch (e) {
        if (e.uncertain) rethrow;
        await _state(id, {'Buoc': 'hoan_tra', 'Loi': e.message});
        await _rollback(id, draft);
        await _state(id, {'TrangThai': 'da_huy', 'Buoc': 'da_huy'});
        rethrow;
      }
      await _state(id, {'Buoc': 'ghi_don'});
    }
    await _commit(id, op, draft);
    return SaleSaveResult(op['IdHoaDon'] as int, requestId: id);
  }

  Future<void> _reserveCustomer(String id, SaleDraft draft) async {
    if (draft.customerId == null) return;
    final customer = await _db
        .collection('KhachHang')
        .findAndModify(
          query: {
            'IdKH': draft.customerId,
            'KhoaGop': {r'$exists': false},
            'DaXoa': {r'$ne': true},
            'AnKhoiDanhSachKhachHang': {r'$ne': true},
          },
          update: {
            r'$set': {'GiuChoDonBan.$id': true},
          },
          returnNew: true,
        );
    if (customer == null) {
      throw const SaleSaveException(
        'Khách hàng không còn hợp lệ. Vui lòng chọn lại.',
      );
    }
  }

  Future<void> _reserve(String id, SaleLine line) async {
    if (line.kind == 'dich_vu') {
      if (await _db.collection('DichVu').findOne({
            '_id': line.serviceId,
            'DaXoa': {r'$ne': true},
          }) ==
          null) {
        throw SaleSaveException('Dịch vụ "${line.name}" không còn tồn tại.');
      }
      return;
    }
    final catalog = await _db.collection('SanPham').findOne({
      'IdSanPham': line.productId,
      'DaXoa': {r'$ne': true},
      'LoaiSanPham': line.kind == 'xe' ? 'xe' : 'phu_tung',
    });
    if (catalog == null) {
      throw SaleSaveException('Sản phẩm "${line.name}" không còn hợp lệ.');
    }
    if (line.kind == 'xe') {
      final collection = _db.collection('Xe');
      final existing = await collection.findOne({'IdXe': line.vehicleId});
      if (existing?['GiuChoBanHang'] == id &&
          existing?['IdSanPham'] == line.productId) {
        return;
      }
      final held = await collection.findAndModify(
        query: {
          'IdXe': line.vehicleId,
          'IdSanPham': line.productId,
          'TinhTrang': true,
          'SuaXoaDangLuu': null,
          'DaXoa': {r'$ne': true},
          r'$or': [
            {
              'GiuChoBanHang': {r'$exists': false},
            },
            {'GiuChoBanHang': null},
          ],
        },
        update: {
          r'$set': {'GiuChoBanHang': id},
        },
        returnNew: true,
      );
      if (held == null) {
        throw SaleSaveException(
          'Xe "${line.name}" đã bán hoặc đang được giữ cho đơn khác.',
        );
      }
    } else {
      final collection = _db.collection('TonKhoPhuTung');
      final existing = await collection.findOne({'IdSanPham': line.productId});
      if ((existing?['GiuChoBanHang'] as Map?)?[id] == line.quantity) return;
      final held = await collection.findAndModify(
        query: {
          'IdSanPham': line.productId,
          'SuaXoaDangLuu': null,
          'SoLuongTon': {r'$gte': line.quantity},
          'GiuChoBanHang.$id': {r'$exists': false},
        },
        update: {
          r'$inc': {'SoLuongTon': -line.quantity},
          r'$set': {'GiuChoBanHang.$id': line.quantity},
        },
        returnNew: true,
      );
      if (held == null) {
        throw SaleSaveException('Phụ tùng "${line.name}" không đủ tồn kho.');
      }
    }
  }

  Future<void> _releaseCustomer(String id, SaleDraft draft) async {
    if (draft.customerId == null) return;
    await _db
        .collection('KhachHang')
        .updateOne(
          {'IdKH': draft.customerId},
          {
            r'$unset': {'GiuChoDonBan.$id': ''},
          },
        );
    await _db
        .collection('KhachHang')
        .updateOne(
          {'IdKH': draft.customerId, 'GiuChoDonBan': {}},
          {
            r'$unset': {'GiuChoDonBan': ''},
          },
        );
  }

  Future<void> _rollback(String id, SaleDraft draft) async {
    for (final line in draft.lines) {
      if (line.kind == 'xe') {
        await _db
            .collection('Xe')
            .updateOne(
              {'IdXe': line.vehicleId, 'GiuChoBanHang': id},
              {
                r'$unset': {'GiuChoBanHang': ''},
              },
            );
      } else if (line.kind == 'phu_tung') {
        await _db
            .collection('TonKhoPhuTung')
            .findAndModify(
              query: {
                'IdSanPham': line.productId,
                'GiuChoBanHang.$id': line.quantity,
              },
              update: {
                r'$inc': {'SoLuongTon': line.quantity},
                r'$unset': {'GiuChoBanHang.$id': ''},
              },
              returnNew: true,
            );
      }
    }
    await _releaseCustomer(id, draft);
  }

  Future<void> _insertOnce(String collection, Map<String, dynamic> row) async {
    final result = await _db
        .collection(collection)
        .updateOne({'_id': row['_id']}, {r'$setOnInsert': row}, upsert: true);
    if (!result.isSuccess || result.hasWriteErrors) {
      throw StateError('Projection write failed');
    }
  }

  Future<void> _commit(
    String id,
    Map<String, dynamic> op,
    SaleDraft draft,
  ) async {
    await _state(id, {});
    final invoice = op['IdHoaDon'] as int,
        debt = op['IdSoNo'] as int,
        payment = op['IdTraNo'] as int;
    // Keep the cost used for a new sale in the journal before writing its lines.
    // A retry must not pick up a later incoming receipt's reference price.
    var purchaseCosts = op['GiaNhapCacDong'] as List?;
    if (purchaseCosts == null) {
      purchaseCosts = <num?>[];
      for (final line in draft.lines) {
        if (line.kind == 'dich_vu') {
          final service = line.serviceId == null
              ? null
              : await _db.collection('DichVu').findOne({'_id': line.serviceId});
          final value = service?['GiaVon'];
          purchaseCosts.add(
            value is num && value.isFinite && value >= 0 ? value : 0,
          );
          continue;
        }
        final source = await _db
            .collection(line.kind == 'xe' ? 'Xe' : 'TonKhoPhuTung')
            .findOne({
              line.kind == 'xe' ? 'IdXe' : 'IdSanPham': line.kind == 'xe'
                  ? line.vehicleId
                  : line.productId,
            });
        final value = source?[line.kind == 'xe' ? 'GiaNhap' : 'GiaVonThamKhao'];
        purchaseCosts.add(
          value is num && value.isFinite && value >= 0 ? value : null,
        );
      }
      await _state(id, {'GiaNhapCacDong': purchaseCosts});
      await _point('afterPurchaseCosts');
    }
    final single = draft.lines.length == 1 ? draft.lines.single : null;
    await _insertOnce('HoaDonBan', {
      '_id': 'sale:$id',
      'IdHoaDon': invoice,
      'IdKH': draft.customerId,
      'NgayMua': draft.storedDate,
      'NgayHen': draft.storedDueDate,
      'NgayTinhLai': draft.storedInterestDate,
      if (draft.debtDatesVersion >= 1)
        'PhienBanNgayCongNo': draft.debtDatesVersion,
      'GhiChu': draft.notes,
      'IdXe': single?.vehicleId,
      'IdSanPham': single?.productId,
      'TongTienHang': draft.subtotal,
      'GiamGia': draft.discount,
      'TongThanhToan': draft.total,
      'SoTienKhachDua': draft.paid,
      'SoTienDaTra': draft.collected,
      'SoTienConNo': draft.due,
      'TienThua': draft.change,
      'PhienBanBanHang': 3,
      'MaYeuCauLuu': id,
      'TrangThaiLuu': 'dang_luu',
    });
    await _point('afterHeader');
    for (var index = 0; index < draft.lines.length; index++) {
      final line = draft.lines[index];
      await _insertOnce('ChiTietHoaDonBan', {
        '_id': 'sale:$id:$index',
        'IdHoaDon': invoice,
        ...line.toMap(),
        'DongSo': index + 1,
        // A missing service cost stays zero, including an older journal entry.
        'GiaNhap': line.kind == 'dich_vu'
            ? (purchaseCosts[index] is num && (purchaseCosts[index] as num) >= 0
                  ? purchaseCosts[index]
                  : 0)
            : purchaseCosts[index],
        'NguonGiaNhap': line.kind == 'phu_tung'
            ? 'TonKhoPhuTung.GiaVonThamKhao'
            : line.kind == 'xe'
            ? 'Xe.GiaNhap'
            : 'DichVu.GiaVon',
        'ThanhTien': line.total,
        'TrangThaiGia': 'xac_nhan',
        'PhienBanBanHang': 3,
      });
      await _point('afterLine');
    }
    await _insertOnce('SoNo', {
      '_id': 'sale:$id:debt',
      'IdSoNo': debt,
      'IdHoaDon': invoice,
      'SoTienDaTra': draft.collected,
      'SoTienConNo': draft.due,
      'PhienBanBanHang': 3,
    });
    if (draft.collected > 0) {
      await _insertOnce('TraNo', {
        '_id': 'sale:$id:payment',
        'IdTraNo': payment,
        'IdSoNo': debt,
        'SotienTra': draft.collected,
        'NgayTra': draft.storedDate,
        'SoNgayQuaHan': 0,
        'SoTienLai': 0,
        'LoaiTraNo': null,
        'LoaiThu': 'thanh_toan_ban_hang',
        'SoCoNo': draft.due,
        'LaiThu': 0,
        'GhiChu': 'Thanh toán khi lập đơn',
        'PhienBanBanHang': 3,
      });
    }
    for (final line in draft.lines) {
      await _state(id, {});
      if (line.kind == 'xe') {
        final sold = await _db
            .collection('Xe')
            .findAndModify(
              query: {
                'IdXe': line.vehicleId,
                'GiuChoBanHang': id,
                'TinhTrang': true,
                'DaXoa': {r'$ne': true},
              },
              update: {
                r'$set': {
                  'TinhTrang': false,
                  'GiaBan': line.price,
                  'IdHoaDonBan': invoice,
                },
                r'$unset': {'GiuChoBanHang': ''},
              },
              returnNew: true,
            );
        if (sold == null) {
          final existing = await _db.collection('Xe').findOne({
            'IdXe': line.vehicleId,
            'TinhTrang': false,
            'IdHoaDonBan': invoice,
          });
          if (existing == null) {
            throw StateError('Vehicle reservation changed during commit');
          }
        }
      } else if (line.kind == 'phu_tung') {
        await _db
            .collection('TonKhoPhuTung')
            .updateOne(
              {'IdSanPham': line.productId},
              {
                r'$unset': {'GiuChoBanHang.$id': ''},
              },
            );
      }
    }
    await _point('beforeComplete');
    await _db
        .collection('HoaDonBan')
        .updateOne(
          {'MaYeuCauLuu': id},
          {
            r'$set': {'TrangThaiLuu': 'da_luu'},
          },
        );
    await _releaseCustomer(id, draft);
    await _state(id, {
      'TrangThai': 'hoan_tat',
      'Buoc': 'hoan_tat',
      'NgayHoanTat': DateTime.now().toUtc(),
    });
    await _point('afterComplete');
  }

  @override
  Future<List<SaleSaveResult>> recoverPending() => _serial(_recoverPending);
  Future<List<SaleSaveResult>> _recoverPending() async {
    await _connect();
    final rows = await _journal.find({'TrangThai': 'dang_xu_ly'}).toList();
    final results = <SaleSaveResult>[];
    for (final op in rows) {
      try {
        results.add(await _resume(op));
      } on SaleSaveException catch (e) {
        if (e.uncertain) rethrow;
      }
    }
    return results;
  }

  @override
  Future<void> close() async {
    try {
      await _opening;
    } catch (_) {
      /* Caller reports errors. */
    }
    if (_db.isConnected) await _db.close();
  }
}
