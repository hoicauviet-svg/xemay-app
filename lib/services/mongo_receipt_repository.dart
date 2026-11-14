import 'package:mongo_dart/mongo_dart.dart';
import 'mongo_sync_journal.dart';
import '../core/config/database_config.dart';
import '../models/repositories/receipt_repository.dart';
import '../models/goods_receipt/goods_receipt_models.dart';

/// Persisted import plans make retries safe on a standalone MongoDB server.
class MongoReceiptRepository implements ReceiptRepository {
  MongoReceiptRepository({String? uri, this.checkpoint})
    : _db = SyncTrackedDb(uri ?? DatabaseConfig.mongoUri);
  final Db _db;
  final Future<void> Function(String)? checkpoint;
  final String _owner = ObjectId().oid;

  Future<void> _connect() async {
    if (!_db.isConnected) await _db.open(writeConcern: WriteConcern.journaled);
  }

  Future<int> _next(String collection, String field) async {
    final rows = await _db
        .collection(collection)
        .modernFind(sort: {field: -1}, limit: 1)
        .toList();
    final max = rows.isEmpty ? 0 : (rows.first[field] as num).toInt();
    final counters = _db.collection('_app_counters');
    await _checked(
      counters.updateOne(
        {'_id': '$collection.$field'},
        {
          r'$max': {'value': max},
        },
        upsert: true,
      ),
    );
    final row = await counters.findAndModify(
      query: {'_id': '$collection.$field'},
      update: {
        r'$inc': {'value': 1},
      },
      returnNew: true,
    );
    return (row!['value'] as num).toInt();
  }

  Future<dynamic> _checked(Future<dynamic> operation) async {
    final result = await operation;
    if (!result.isSuccess || result.hasWriteErrors) {
      throw StateError('Không xác nhận được kết quả lưu');
    }
    return result;
  }

  Future<void> _insert(String collection, Map<String, dynamic> row) async {
    final result = await _checked(
      _db
          .collection(collection)
          .updateOne({'_id': row['_id']}, {r'$setOnInsert': row}, upsert: true),
    );
    if (!result.isSuccess || result.hasWriteErrors) {
      throw StateError('Không lưu được $collection');
    }
  }

  @override
  Future<void> save(ReceiptPreview receipt, String requestId) async {
    await recoverPending();
    final journal = _db.collection('GiaoDichNhapHang');
    var plan = await journal.findOne({'_id': requestId});
    if (plan == null) {
      for (final entry in {
        'DoiTac': receipt.partnerId ?? receipt.batchInfo?.partnerId,
        'VanChuyen': receipt.carrierId ?? receipt.batchInfo?.carrierId,
      }.entries) {
        if (entry.value != null &&
            await _db.collection(entry.key).findOne({
                  '_id': entry.value,
                  'DaXoa': true,
                }) !=
                null) {
          throw StateError(
            'Đối tác hoặc vận chuyển đã bị xóa. Vui lòng chọn lại.',
          );
        }
      }

      if (receipt.batchId == null &&
          receipt.batchInfo == null &&
          (receipt.paidAmount < 0 ||
              receipt.paidAmount > receipt.total ||
              (receipt.carrier.trim().isNotEmpty &&
                  receipt.carrierId == null))) {
        throw ArgumentError(
          'Thông tin thanh toán hoặc vận chuyển không hợp lệ',
        );
      }

      final batchId = receipt.batchId ?? await _next('NhapHang', 'IdNhapHang');
      if (receipt.batchId != null &&
          await _db.collection('NhapHang').findOne({'IdNhapHang': batchId}) ==
              null) {
        throw StateError('Lô hàng không còn tồn tại');
      }
      final rows = <Map<String, dynamic>>[];
      var index = 0;
      for (final line in receipt.lines) {
        final kind = receipt.type.isVehicle ? 'xe' : 'phu_tung';
        final matches = await _db.collection('SanPham').find({
          'TenSanPham': line.name,
          'DaXoa': {r'$ne': true},
          'LoaiSanPham': kind,
          if (!receipt.type.isVehicle && line.productCode.isNotEmpty)
            'MaSanPham': line.productCode,
        }).toList();
        // Ambiguous legacy names retain their identities; never merge brands by name.
        final existing = matches.length == 1 ? matches.single : null;
        final productId =
            (existing?['IdSanPham'] as num?)?.toInt() ??
            await _next('SanPham', 'IdSanPham');
        final vehicleId = receipt.type.isVehicle
            ? await _next('Xe', 'IdXe')
            : null;
        rows.add({
          'Catalog': existing == null
              ? {
                  '_id': '$requestId-c-$index',
                  ...line.toCatalogFields(
                    receipt.type,
                    productId: productId,
                    generatedCode: 'SP$productId',
                  ),
                }
              : null,
          'Vehicle': vehicleId == null
              ? null
              : {
                  '_id': '$requestId-v-$index',
                  ...line.toVehicleFields(
                    receipt.type,
                    vehicleId: vehicleId,
                    productId: productId,
                  ),
                  'IdHangXe': existing?['IdHangXe'],
                  'IdNhapHang': batchId,
                  'TinhTrang': false,
                  'DangNhapHang': requestId,
                },
          'Extension': vehicleId == null
              ? null
              : {
                  '_id': '$requestId-e-$index',
                  ...line.toVehicleDetailFields(
                    receipt.type,
                    vehicleId: vehicleId,
                    batchId: batchId,
                  ),
                },
          'Detail': {
            '_id': '$requestId-d-$index',
            'IdNhapHang': batchId,
            'IdSanPham': productId,
            'IdXe': vehicleId,
            'TenSanPham': line.name,
            'SoLuong': line.quantity,
            'GiaNhap': line.unitPrice,
            'ChiPhi': line.costs.map((c) => c.toMap()).toList(),
            'TongChiPhi': line.totalCosts,
          },
        });
        index++;
      }
      final date = DateTime.utc(
        receipt.date.year,
        receipt.date.month,
        receipt.date.day,
      );
      final initialPaid = receipt.batchInfo?.paidAmount ?? receipt.paidAmount;
      final initialDue =
          receipt.batchInfo?.remainingAmount ?? receipt.remainingAmount;
      plan = {
        '_id': requestId,
        'TrangThai': 'dang_luu',
        'Rows': rows,
        'InitialPayment': receipt.batchId == null && initialPaid > 0
            ? {
                '_id': '$requestId-p',
                'IdTraNoNhapHang': await _next(
                  'TraNoNhapHang',
                  'IdTraNoNhapHang',
                ),
                'IdNhapHang': batchId,
                'NgayTra': date,
                'SoTienTra': initialPaid,
                'SoCoNo': initialDue,
                'GhiChu': 'Thanh toán khi nhập hàng',
              }
            : null,

        'ExtensionCollection': receipt.type == ReceiptProductType.newVehicle
            ? 'XeMoi'
            : 'XeCu',
        'Header': receipt.batchId != null
            ? null
            : {
                '_id': '$requestId-h',
                'IdNhapHang': batchId,
                ...?receipt.batchInfo?.toDatabaseFields(),
                if (receipt.batchInfo == null) ...{
                  'SoLuong': receipt.quantity,
                  'SoTien': receipt.total,
                  'SoTienDaTra': receipt.paidAmount,
                  'SoTienConNo': receipt.remainingAmount,
                  'NgayNhap': date,
                  'NoiNhap': receipt.partner,
                  'NguoiCho': receipt.carrier,
                  'IdVanChuyen': ?receipt.carrierId,
                  'IdDoiTac': receipt.partnerId,
                },
                'LoaiSanPham': switch (receipt.type) {
                  ReceiptProductType.newVehicle => 'xe_moi',
                  ReceiptProductType.usedVehicle => 'xe_cu',
                  ReceiptProductType.part => 'phu_tung',
                },
                'GhiChu': receipt.notes,
                'NhapDangLuu': requestId,
              },
      };
      await _insert('GiaoDichNhapHang', plan);
      plan = (await journal.findOne({'_id': requestId}))!;
    }
    await _commit(plan);
  }

  Future<void> _commit(Map<String, dynamic> plan) async {
    final batchId =
        ((plan['Header'] as Map?)?['IdNhapHang'] ??
        ((plan['Rows'] as List).first as Map)['Detail']['IdNhapHang']);
    if (plan['TrangThai'] == 'hoan_tat') {
      await _checked(
        _db
            .collection('NhapHang')
            .updateOne(
              {'IdNhapHang': batchId, 'NhapDangLuu': plan['_id']},
              {
                r'$unset': {'NhapDangLuu': ''},
              },
            ),
      );
      return;
    }
    final batch = await _db.collection('NhapHang').findOne({
      'IdNhapHang': batchId,
    });
    if (batch != null) {
      final held = await _db
          .collection('NhapHang')
          .findAndModify(
            query: {
              '_id': batch['_id'],
              'SuaXoaDangLuu': null,
              r'$or': [
                {'NhapDangLuu': null},
                {'NhapDangLuu': plan['_id']},
              ],
            },
            update: {
              r'$set': {'NhapDangLuu': plan['_id']},
            },
            returnNew: true,
          );
      if (held == null) {
        throw StateError('Lô hàng đang được sửa/xóa hoặc nhập sản phẩm.');
      }
    } else if (plan['Header'] == null) {
      throw StateError(
        'Lô hàng đã được xóa, không thể tiếp tục thêm sản phẩm.',
      );
    }
    final id = plan['_id'] as String;
    final journal = _db.collection('GiaoDichNhapHang');
    final acquired = await journal.findAndModify(
      query: {
        '_id': id,
        'TrangThai': 'dang_luu',
        r'$or': [
          {'ChuKhoa': _owner},
          {
            'KhoaDen': {r'$lt': DateTime.now().toUtc()},
          },
          {'ChuKhoa': null},
        ],
      },
      update: {
        r'$set': {
          'ChuKhoa': _owner,
          'KhoaDen': DateTime.now().toUtc().add(const Duration(minutes: 5)),
        },
      },
      returnNew: true,
    );
    if (acquired == null) throw StateError('Phiếu đang được lưu');
    for (final raw in plan['Rows'] as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      if (row['Catalog'] != null) {
        await _insert(
          'SanPham',
          Map<String, dynamic>.from(row['Catalog'] as Map),
        );
      }
      if (row['Vehicle'] != null) {
        await _insert('Xe', Map<String, dynamic>.from(row['Vehicle'] as Map));
        await _insert(
          plan['ExtensionCollection'] as String,
          Map<String, dynamic>.from(row['Extension'] as Map),
        );
      }
      await _insert(
        'ChiTietNhapHang',
        Map<String, dynamic>.from(row['Detail'] as Map),
      );
    }
    if (checkpoint != null) await checkpoint!('afterDetails');
    if (plan['Header'] != null) {
      await _insert(
        'NhapHang',
        Map<String, dynamic>.from(plan['Header'] as Map),
      );
    }
    if (plan['InitialPayment'] != null) {
      await _insert(
        'TraNoNhapHang',
        Map<String, dynamic>.from(plan['InitialPayment'] as Map),
      );
    }
    for (final raw in plan['Rows'] as List) {
      final row = raw as Map;
      if (row['Vehicle'] != null) {
        await _checked(
          _db
              .collection('Xe')
              .updateOne(
                {'_id': (row['Vehicle'] as Map)['_id'], 'DangNhapHang': id},
                {
                  r'$set': {'TinhTrang': true},
                  r'$unset': {'DangNhapHang': ''},
                },
              ),
        );
      } else {
        final detail = row['Detail'] as Map;
        final productId = detail['IdSanPham'];
        final stocks = _db.collection('TonKhoPhuTung');
        await _checked(
          stocks.updateOne(
            {'IdSanPham': productId},
            {
              r'$setOnInsert': {
                '_id': 'receipt-stock-$productId',
                'IdSanPham': productId,
                'SoLuongTon': 0,
              },
            },
            upsert: true,
          ),
        );
        final token = detail['_id'];
        await _checked(
          stocks.updateOne(
            {
              'IdSanPham': productId,
              'SuaXoaDangLuu': null,
              'PhieuNhap.$token': {r'$exists': false},
            },
            {
              r'$inc': {'SoLuongTon': detail['SoLuong']},
              r'$set': {
                'PhieuNhap.$token': true,
                'GiaVonThamKhao': detail['GiaNhap'],
              },
            },
          ),
        );
      }
    }
    for (final raw in plan['Rows'] as List) {
      final row = raw as Map;
      if (row['Vehicle'] == null) {
        final detail = row['Detail'] as Map;
        if (await _db.collection('TonKhoPhuTung').findOne({
              'IdSanPham': detail['IdSanPham'],
              'PhieuNhap.${detail['_id']}': true,
            }) ==
            null) {
          throw StateError('Tồn kho đang được chỉnh sửa. Vui lòng thử lại.');
        }
      }
    }
    if (checkpoint != null) await checkpoint!('afterStock');
    await _checked(
      journal.updateOne(
        {'_id': id},
        {
          r'$set': {
            'TrangThai': 'hoan_tat',
            'NgayHoanTat': DateTime.now().toUtc(),
          },
        },
      ),
    );
    await _checked(
      _db
          .collection('NhapHang')
          .updateOne(
            {'IdNhapHang': batchId, 'NhapDangLuu': id},
            {
              r'$unset': {'NhapDangLuu': ''},
            },
          ),
    );
  }

  Future<void> recoverPending() async {
    await _connect();
    final pending = await _db.collection('GiaoDichNhapHang').find({
      'TrangThai': 'dang_luu',
      r'$or': [
        {'ChuKhoa': null},
        {
          'KhoaDen': {r'$lt': DateTime.now().toUtc()},
        },
        {'ChuKhoa': _owner},
      ],
    }).toList();
    for (final plan in pending) {
      await _commit(plan);
    }
  }

  @override
  Future<void> close() async {
    if (_db.isConnected) await _db.close();
  }
}
