import '../models/maintenance/record_maintenance.dart';
import 'mongo_record_maintenance.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'mongo_sync_journal.dart';
import '../core/config/database_config.dart';
import '../models/batches/batch_models.dart';
import '../models/goods_receipt/goods_receipt_models.dart';
import '../models/repositories/batch_repository.dart';

/// Read-only access to lots and their actual source relationships.
class MongoBatchRepository implements BatchRepository {
  MongoBatchRepository({String? uri, this.checkpoint})
    : _db = SyncTrackedDb(uri ?? DatabaseConfig.mongoUri);
  final Db _db;
  @override
  RecordMaintenance get maintenance => MongoRecordMaintenance(_db, connect);

  final Future<void> Function(String)? checkpoint;
  Future<void>? _opening;

  @override
  Future<void> connect() =>
      _opening ??= _open().whenComplete(() => _opening = null);
  Future<void> _open() async {
    if (!_db.isConnected) await _db.open(writeConcern: WriteConcern.journaled);
  }

  static Map<String, dynamic> filterFor(
    ReceiptProductType type,
    String search,
  ) {
    final kind = switch (type) {
      ReceiptProductType.newVehicle => 'xe_moi',
      ReceiptProductType.usedVehicle => 'xe_cu',
      ReceiptProductType.part => 'phu_tung',
    };
    // Legacy NhapHang records relate to XeMoi; no inferred matches to used vehicles/parts.
    final filter = <String, dynamic>{
      if (type == ReceiptProductType.newVehicle)
        r'$or': [
          {'LoaiSanPham': kind},
          {
            'LoaiSanPham': {r'$exists': false},
          },
        ]
      else
        'LoaiSanPham': kind,
    };
    final term = search.trim();
    if (term.isNotEmpty) {
      filter[r'$and'] = [
        {
          r'$or': [
            {
              'NguoiCho': {r'$regex': RegExp.escape(term), r'$options': 'i'},
            },
            {
              'NoiNhap': {r'$regex': RegExp.escape(term), r'$options': 'i'},
            },
            if (int.tryParse(term) != null) {'IdNhapHang': int.parse(term)},
          ],
        },
      ];
    }
    return filter;
  }

  @override
  Future<BatchPage> fetch(
    ReceiptProductType type, {
    int page = 0,
    int pageSize = 30,
    String search = '',
  }) async {
    final filter = filterFor(type, search);
    final collection = _db.collection('NhapHang');
    final total = await collection.count(filter);
    final rows = await collection
        .modernFind(
          filter: filter,
          sort: {'NgayNhap': -1, 'IdNhapHang': -1},
          skip: page == 0 ? null : page * pageSize,
          limit: pageSize,
        )
        .toList();
    return BatchPage(rows.map(ReceiptBatch.fromMap).toList(), total);
  }

  @override
  Future<List<BatchProduct>> products(
    ReceiptBatch batch,
    ReceiptProductType type,
  ) async {
    if (!type.isVehicle) {
      final rows = await _db.collection('ChiTietNhapHang').find({
        'IdNhapHang': batch.id,
      }).toList();
      return rows
          .map(
            (r) => BatchProduct(
              sourceId: r['_id'],
              batchId: batch.id,
              productId: (r['IdSanPham'] as num).toInt(),
              name: r['TenSanPham'] as String,
              quantity: r['SoLuong'] as num,
              cost: r['GiaNhap'] as num?,
            ),
          )
          .toList();
    }
    final extensions = type == ReceiptProductType.newVehicle
        ? await _db.collection('XeMoi').find({'IdNhapHang': batch.id}).toList()
        : <Map<String, dynamic>>[];
    final byVehicle = {for (final row in extensions) row['IdXe']: row};
    final vehicles = await _db
        .collection('Xe')
        .modernFind(
          filter: {
            'DangNhapHang': null,
            'TinhTrangXe': {
              r'$in': [
                type == ReceiptProductType.newVehicle ? 'moi' : 'cu',
                'chua_xac_dinh',
              ],
            },
            r'$or': [
              {'IdNhapHang': batch.id},
              if (byVehicle.isNotEmpty)
                {
                  'IdXe': {r'$in': byVehicle.keys.toList()},
                },
            ],
          },
          sort: {'IdXe': 1},
        )
        .toList();
    if (vehicles.isNotEmpty) {
      final details = await _db
          .collection(type == ReceiptProductType.newVehicle ? 'XeMoi' : 'XeCu')
          .find({
            'IdXe': {r'$in': vehicles.map((r) => r['IdXe']).toList()},
          })
          .toList();
      byVehicle.addAll({for (final row in details) row['IdXe']: row});
    }
    final receiptLines = await _db.collection('ChiTietNhapHang').find({
      'IdNhapHang': batch.id,
    }).toList();
    return vehicles.map((row) {
      final detail = byVehicle[row['IdXe']];
      return BatchProduct(
        sourceId:
            receiptLines
                .where((l) => l['IdXe'] == row['IdXe'])
                .firstOrNull?['_id'] ??
            'legacy-receipt:${row['IdXe']}',
        batchId: batch.id,
        productId: (row['IdSanPham'] as num).toInt(),
        vehicleId: (row['IdXe'] as num).toInt(),
        name: row['TenXe']?.toString() ?? '',
        quantity: 1,
        cost: row['GiaNhap'] as num?,
        frameNumber: detail?['SoKhung']?.toString() ?? '',
        engineNumber: detail?['SoMay']?.toString() ?? '',
        plate: detail?['BienSo']?.toString() ?? '',
      );
    }).toList();
  }

  @override
  Future<ReceiptBatch?> findById(int batchId) async {
    await maintenance.ensureReadable(RecordKind.batch, batchId);
    await _recoverPayment(batchId);
    final row = await _db.collection('NhapHang').findOne({
      'IdNhapHang': batchId,
    });
    return row == null ? null : ReceiptBatch.fromMap(row);
  }

  @override
  Future<List<BatchPayment>> payments(int batchId) async {
    await maintenance.ensureReadable(RecordKind.batch, batchId);
    await _recoverPayment(batchId);
    final rows = await _db
        .collection('TraNoNhapHang')
        .modernFind(
          filter: {'IdNhapHang': batchId},
          sort: {'NgayTra': -1, 'IdTraNoNhapHang': -1},
        )
        .toList();
    return rows.map(BatchPayment.fromMap).toList();
  }

  Future<void> _checkWrite(Future<dynamic> operation) async {
    final result = await operation;
    if (!result.isSuccess || result.hasWriteErrors) {
      throw StateError('Chưa xác nhận kết quả thanh toán');
    }
  }

  Future<void> _recoverPayment(int batchId) async {
    final batch = await _db.collection('NhapHang').findOne({
      'IdNhapHang': batchId,
    });
    if (batch?['ThanhToanDangLuu'] is Map) await _finishPayment(batch!);
  }

  Future<void> _finishPayment(Map<String, dynamic> batch) async {
    final row = Map<String, dynamic>.from(batch['ThanhToanDangLuu'] as Map);
    await _checkWrite(
      _db
          .collection('TraNoNhapHang')
          .updateOne({'_id': row['_id']}, {r'$setOnInsert': row}, upsert: true),
    );
    if (checkpoint != null) await checkpoint!('afterHistory');
    await _checkWrite(
      _db
          .collection('NhapHang')
          .updateOne(
            {'_id': batch['_id'], 'ThanhToanDangLuu._id': row['_id']},
            {
              r'$unset': {'ThanhToanDangLuu': ''},
            },
          ),
    );
  }

  Future<int> _nextPayment() async {
    final rows = await _db
        .collection('TraNoNhapHang')
        .modernFind(sort: {'IdTraNoNhapHang': -1}, limit: 1)
        .toList();
    final counter = _db.collection('_app_counters');
    await _checkWrite(
      counter.updateOne(
        {'_id': 'TraNoNhapHang.IdTraNoNhapHang'},
        {
          r'$max': {'value': rows.isEmpty ? 0 : rows.first['IdTraNoNhapHang']},
        },
        upsert: true,
      ),
    );
    final result = await counter.findAndModify(
      query: {'_id': 'TraNoNhapHang.IdTraNoNhapHang'},
      update: {
        r'$inc': {'value': 1},
      },
      returnNew: true,
    );
    return (result!['value'] as num).toInt();
  }

  bool _sameDocuments(List<PaymentDocument> a, List<PaymentDocument> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].name != b[i].name ||
          a[i].mimeType != b[i].mimeType ||
          a[i].bytes.length != b[i].bytes.length) {
        return false;
      }
      for (int j = 0; j < a[i].bytes.length; j++) {
        if (a[i].bytes[j] != b[i].bytes[j]) return false;
      }
    }
    return true;
  }

  @override
  Future<void> pay(
    BatchPaymentPreview payment, {
    required String requestId,
  }) async {
    if (!RegExp(r'^[a-f0-9]{24}$').hasMatch(requestId) ||
        payment.amount <= 0 ||
        payment.amount > 1000000000000000 ||
        payment.notes.length > 10000) {
      throw const BatchPaymentException('Thông tin thanh toán không hợp lệ.');
    }
    if (payment.documents.length > 10 ||
        payment.documents.fold<int>(0, (s, d) => s + d.bytes.length) >
            PaymentDocument.maxTotalBytes) {
      throw const BatchPaymentException(
        'Tổng dung lượng chứng từ tối đa 8 MB, tối đa 10 file.',
      );
    }
    for (final document in payment.documents) {
      if (document.name.trim().isEmpty ||
          document.name.length > 255 ||
          PaymentDocument.detectMime(document.bytes) != document.mimeType) {
        throw const BatchPaymentException(
          'Chứng từ phải là ảnh hoặc PDF hợp lệ.',
        );
      }
    }
    await connect();
    await _recoverPayment(payment.batchId);
    final id = 'batch-payment-$requestId';
    final date = DateTime.utc(
      payment.date.year,
      payment.date.month,
      payment.date.day,
    );
    if (await _db.collection('_record_deleted').findOne({
          '_id': 'TraNoNhapHang:$id',
        }) !=
        null) {
      throw StateError(
        'Phiếu trả nợ này đã được xóa. Tạo yêu cầu thanh toán mới nếu cần.',
      );
    }
    final existing = await _db.collection('TraNoNhapHang').findOne({'_id': id});
    if (existing != null) {
      final previous = BatchPayment.fromMap(existing);
      if (previous.batchId != payment.batchId ||
          previous.amount != payment.amount ||
          previous.date != date ||
          previous.notes != payment.notes.trim() ||
          !_sameDocuments(previous.documents, payment.documents)) {
        throw const BatchPaymentException('Yêu cầu thanh toán đã thay đổi.');
      }
      return;
    }
    final batch = await _db.collection('NhapHang').findOne({
      'IdNhapHang': payment.batchId,
    });
    if (batch == null) {
      throw const BatchPaymentException('Lô hàng không còn tồn tại.');
    }
    final due = batch['SoTienConNo'], paid = batch['SoTienDaTra'];
    if (due is! num ||
        paid is! num ||
        !due.isFinite ||
        !paid.isFinite ||
        paid < 0 ||
        due < payment.amount) {
      throw const BatchPaymentException(
        'Số tiền vượt số còn nợ hoặc công nợ chưa hợp lệ.',
      );
    }
    final imported = batch['NgayNhap'];
    if (imported is DateTime &&
        date.isBefore(
          DateTime.utc(imported.year, imported.month, imported.day),
        )) {
      throw const BatchPaymentException(
        'Ngày thanh toán không được trước ngày nhập.',
      );
    }
    final row = {
      '_id': id,
      'IdTraNoNhapHang': await _nextPayment(),
      'IdNhapHang': payment.batchId,
      'SoTienTra': payment.amount,
      'NgayTra': date,
      'GhiChu': payment.notes.trim(),
      'SoCoNo': due - payment.amount,
      'ChungTu': payment.documents.map((d) => d.toMap()).toList(),
    };
    final updated = await _db
        .collection('NhapHang')
        .findAndModify(
          query: {
            '_id': batch['_id'],
            'SoTienConNo': due,
            'SoTienDaTra': paid,
            'ThanhToanDangLuu': null,
            'SuaXoaDangLuu': null,
          },
          update: {
            r'$inc': {
              'SoTienConNo': -payment.amount,
              'SoTienDaTra': payment.amount,
            },
            r'$set': {'ThanhToanDangLuu': row},
          },
          returnNew: true,
        );
    if (updated == null) {
      throw const BatchPaymentException(
        'Công nợ vừa thay đổi. Vui lòng tải lại lô hàng.',
      );
    }
    if (checkpoint != null) await checkpoint!('afterBalance');
    await _finishPayment(updated);
  }

  @override
  Future<void> close() async {
    try {
      await _opening;
    } catch (_) {
      /* Reported by the controller. */
    }
    if (_db.isConnected) await _db.close();
  }
}
