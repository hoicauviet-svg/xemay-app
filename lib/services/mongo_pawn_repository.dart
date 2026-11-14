import 'customer_address_migration.dart';
import '../models/maintenance/record_maintenance.dart';
import 'mongo_record_maintenance.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'mongo_sync_journal.dart';
import '../core/config/database_config.dart';
import '../models/pawn/pawn_models.dart';
import '../models/repositories/pawn_repository.dart';

class MongoPawnRepository implements PawnRepository {
  MongoPawnRepository({String? uri, this.checkpoint})
    : _db = SyncTrackedDb(uri ?? DatabaseConfig.mongoUri);
  final Db _db;
  bool _addressesReady = false;
  @override
  RecordMaintenance get maintenance => MongoRecordMaintenance(_db, _connect);

  final Future<void> Function(String)? checkpoint;
  Future<void>? _opening;
  Future<void> _connect() =>
      _opening ??= _open().whenComplete(() => _opening = null);
  Future<void> _open() async {
    if (!_db.isConnected) await _db.open(writeConcern: WriteConcern.journaled);
    if (!_addressesReady) {
      await migrateCustomerAddresses(_db);
      _addressesReady = true;
    }
  }

  @override
  Future<PawnPage> fetch({
    String search = '',
    int page = 0,
    int? customerId,
    String status = 'all',
  }) async {
    if (!['active', 'closed', 'all'].contains(status)) {
      throw ArgumentError.value(status, 'status');
    }
    await _connect();
    final term = search.trim();
    final filter = <String, dynamic>{
      'IdKhachHang': ?customerId,
      if (status != 'all') 'TrangThai': status == 'closed',
    };
    if (term.isNotEmpty) {
      final regex = {r'$regex': RegExp.escape(term), r'$options': 'i'};
      final customers = await _db
          .collection('KhachHang')
          .modernFind(
            filter: {
              r'$or': [
                {'TenKhachHang': regex},
                {'SoDienThoai': regex},
                if (int.tryParse(term) != null) {'IdKH': int.parse(term)},
              ],
            },
            projection: {'IdKH': 1},
          )
          .toList();
      filter[r'$or'] = [
        {'TaiSanTheChap': regex},
        {'GhiChu': regex},
        if (int.tryParse(term) != null) {'IdCamDo': int.parse(term)},
        if (customers.isNotEmpty)
          {
            'IdKhachHang': {r'$in': customers.map((c) => c['IdKH']).toList()},
          },
      ];
    }
    final total = await _db.collection('CamDo').count(filter);
    final rows = await _db
        .collection('CamDo')
        .modernFind(
          filter: filter,
          sort: {'NgayVay': -1, 'IdCamDo': -1},
          skip: page == 0 ? null : page * 30,
          limit: 30,
        )
        .toList();
    final ids = rows
        .map((r) => r['IdKhachHang'])
        .where((id) => id != null)
        .toSet()
        .toList();
    final customers = ids.isEmpty
        ? <Map<String, dynamic>>[]
        : await _db.collection('KhachHang').find({
            'IdKH': {r'$in': ids},
          }).toList();
    final byId = {for (final c in customers) c['IdKH']: c};
    for (final row in rows) {
      final customer = byId[row['IdKhachHang']];
      row['TenKhachHang'] = customer?['TenKhachHang'];
      row['SoDienThoai'] = customer?['SoDienThoai'];
      row['DiaChiKhachHang'] = customer?['DiaChiChiTiet'];
    }
    return PawnPage(rows, total);
  }

  bool _sameFields(Map<String, dynamic> row, Map<String, dynamic> fields) =>
      fields.entries.every((e) => row[e.key] == e.value);
  @override
  Future<int> create(PawnDraft draft, {required String requestId}) async {
    final error = draft.validate();
    if (error != null) throw PawnException(error);
    if (!RegExp(r'^[a-f0-9]{24}$').hasMatch(requestId)) {
      throw const PawnException('Yêu cầu lưu không hợp lệ.');
    }
    final fields = draft.toFields();
    await _connect();
    final id = 'pawn-$requestId';
    final existing = await _db.collection('CamDo').findOne({'_id': id});
    if (existing != null) {
      if (!_sameFields(existing, fields)) {
        throw const PawnException('Nội dung phiếu đã thay đổi.');
      }
      await _db
          .collection('KhachHang')
          .updateOne(
            {'IdKH': draft.customerId},
            {
              r'$unset': {'GiuChoDonBan.$id': ''},
            },
          );
      return (existing['IdCamDo'] as num).toInt();
    }
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
      throw const PawnException('Khách hàng không còn trong danh sách.');
    }
    try {
      final last = await _db
          .collection('CamDo')
          .modernFind(sort: {'IdCamDo': -1}, limit: 1)
          .toList();
      final counter = _db.collection('_app_counters');
      final initialized = await counter.updateOne(
        {'_id': 'CamDo'},
        {
          r'$max': {'value': last.isEmpty ? 0 : last.first['IdCamDo']},
        },
        upsert: true,
      );
      if (!initialized.isSuccess || initialized.hasWriteErrors) {
        throw StateError('Không cấp được mã cầm đồ');
      }
      final sequence = await counter.findAndModify(
        query: {'_id': 'CamDo'},
        update: {
          r'$inc': {'value': 1},
        },
        returnNew: true,
      );
      final result = await _db
          .collection('CamDo')
          .updateOne(
            {'_id': id},
            {
              r'$setOnInsert': {
                '_id': id,
                'IdCamDo': sequence!['value'],
                ...fields,
              },
            },
            upsert: true,
          );
      if (!result.isSuccess || result.hasWriteErrors) {
        throw StateError('Chưa xác nhận lưu cầm đồ');
      }
      final saved = (await _db.collection('CamDo').findOne({'_id': id}))!;
      if (!_sameFields(saved, fields)) {
        throw const PawnException('Yêu cầu lưu bị trùng với nội dung khác.');
      }
      return (saved['IdCamDo'] as num).toInt();
    } finally {
      await _db
          .collection('KhachHang')
          .updateOne(
            {'IdKH': draft.customerId},
            {
              r'$unset': {'GiuChoDonBan.$id': ''},
            },
          );
    }
  }

  Future<void> _checked(Future<dynamic> operation) async {
    final result = await operation;
    if (!result.isSuccess || result.hasWriteErrors) {
      throw StateError('Chưa xác nhận thanh toán');
    }
  }

  Future<void> _recoverPayment(int id) async {
    final contract = await _db.collection('CamDo').findOne({'IdCamDo': id});
    if (contract?['ThanhToanDangLuu'] is Map) await _finishPayment(contract!);
  }

  Future<void> _finishPayment(Map<String, dynamic> contract) async {
    final pending = Map<String, dynamic>.from(
      contract['ThanhToanDangLuu'] as Map,
    );
    final payments = await _db.collection('TraNoCamDo').find({
      'IdCamDo': contract['IdCamDo'],
    }).toList();
    final alreadySaved = payments.any((p) => p['_id'] == pending['_id']);
    final details = PawnDetails(contract: contract, payments: payments);
    final remaining = details.remaining;
    if (remaining == null ||
        (!alreadySaved && (pending['TienGoc'] as num) > remaining)) {
      await _checked(
        _db
            .collection('CamDo')
            .updateOne(
              {'_id': contract['_id'], 'ThanhToanDangLuu._id': pending['_id']},
              {
                r'$unset': {'ThanhToanDangLuu': ''},
              },
            ),
      );
      throw const PawnException(
        'Tiền gốc vượt số gốc còn lại hoặc dữ liệu gốc cần đối soát.',
      );
    }
    await _checked(
      _db
          .collection('TraNoCamDo')
          .updateOne(
            {'_id': pending['_id']},
            {r'$setOnInsert': pending},
            upsert: true,
          ),
    );
    final saved = (await _db.collection('TraNoCamDo').findOne({
      '_id': pending['_id'],
    }))!;
    final fields = Map<String, dynamic>.from(pending)..remove('IdTraNoCamDo');
    if (!_sameFields(saved, fields)) {
      await _checked(
        _db
            .collection('CamDo')
            .updateOne(
              {'_id': contract['_id'], 'ThanhToanDangLuu._id': pending['_id']},
              {
                r'$unset': {'ThanhToanDangLuu': ''},
              },
            ),
      );
      throw const PawnException('Yêu cầu thanh toán trùng với nội dung khác.');
    }
    if (checkpoint != null) await checkpoint!('afterHistory');
    final after = remaining - (alreadySaved ? 0 : (pending['TienGoc'] as num));
    await _checked(
      _db
          .collection('CamDo')
          .updateOne(
            {'_id': contract['_id'], 'ThanhToanDangLuu._id': pending['_id']},
            {
              r'$set': {
                'TrangThai': after == 0,
                if (pending['NgayHen'] is DateTime)
                  'NgayHan': pending['NgayHen'],
              },
              r'$unset': {'ThanhToanDangLuu': ''},
            },
          ),
    );
  }

  @override
  Future<PawnDetails> details(int id) async {
    await _connect();
    await maintenance.ensureReadable(RecordKind.pawn, id);
    await _recoverPayment(id);
    final contract = await _db.collection('CamDo').findOne({'IdCamDo': id});
    if (contract == null) {
      throw const PawnException('Phiếu cầm đồ không còn tồn tại.');
    }
    final customer = await _db.collection('KhachHang').findOne({
      'IdKH': contract['IdKhachHang'],
    });
    if (customer != null) {
      customer['DiaChiHienThi'] = customer['DiaChiChiTiet'] ?? '';
    }
    final payments = await _db
        .collection('TraNoCamDo')
        .modernFind(
          filter: {'IdCamDo': id},
          sort: {'NgayTra': -1, 'IdTraNoCamDo': -1},
        )
        .toList();
    return PawnDetails(
      contract: contract,
      payments: payments,
      customer: customer,
    );
  }

  @override
  Future<void> pay(
    PawnPaymentDraft payment, {
    required String requestId,
  }) async {
    final error = payment.validate();
    if (error != null) throw PawnException(error);
    if (!RegExp(r'^[a-f0-9]{24}$').hasMatch(requestId)) {
      throw const PawnException('Yêu cầu thanh toán không hợp lệ.');
    }
    await _connect();
    await _recoverPayment(payment.pawnId);
    final fields = payment.toFields();
    final id = 'pawn-payment-$requestId';
    if (await _db.collection('_record_deleted').findOne({
          '_id': 'TraNoCamDo:$id',
        }) !=
        null) {
      throw StateError(
        'Phiếu trả nợ này đã được xóa. Tạo yêu cầu thanh toán mới nếu cần.',
      );
    }
    final existing = await _db.collection('TraNoCamDo').findOne({'_id': id});
    if (existing != null) {
      if (!_sameFields(existing, fields)) {
        throw const PawnException('Nội dung thanh toán đã thay đổi.');
      }
      return;
    }
    final loaded = await details(payment.pawnId);
    if (!loaded.canPay) {
      throw const PawnException(
        'Phiếu đã tất toán hoặc số gốc còn lại cần đối soát.',
      );
    }
    if (payment.principal > loaded.remaining!) {
      throw const PawnException('Tiền gốc không được vượt số gốc còn lại.');
    }
    final loanDate = loaded.contract['NgayVay'];
    final date = fields['NgayTra'] as DateTime;
    if (loanDate is DateTime &&
        date.isBefore(
          DateTime.utc(loanDate.year, loanDate.month, loanDate.day),
        )) {
      throw const PawnException('Ngày trả không được trước ngày vay.');
    }
    final last = await _db
        .collection('TraNoCamDo')
        .modernFind(sort: {'IdTraNoCamDo': -1}, limit: 1)
        .toList();
    final counter = _db.collection('_app_counters');
    await _checked(
      counter.updateOne(
        {'_id': 'TraNoCamDo'},
        {
          r'$max': {'value': last.isEmpty ? 0 : last.first['IdTraNoCamDo']},
        },
        upsert: true,
      ),
    );
    final next = await counter.findAndModify(
      query: {'_id': 'TraNoCamDo'},
      update: {
        r'$inc': {'value': 1},
      },
      returnNew: true,
    );
    final row = {
      '_id': id,
      'IdTraNoCamDo': next!['value'],
      ...fields,
      if (fields['NgayHen'] is DateTime)
        'NgayHenTruocTra': loaded.contract['NgayHan'],
    };
    final locked = await _db
        .collection('CamDo')
        .findAndModify(
          query: {
            '_id': loaded.contract['_id'],
            'TrangThai': false,
            'ThanhToanDangLuu': null,
            'SuaXoaDangLuu': null,
          },
          update: {
            r'$set': {'ThanhToanDangLuu': row},
          },
          returnNew: true,
        );
    if (locked == null) {
      throw const PawnException(
        'Phiếu đang được xử lý. Vui lòng tải lại trước khi thanh toán.',
      );
    }
    if (checkpoint != null) await checkpoint!('afterReserve');
    await _finishPayment(locked);
  }

  @override
  Future<void> close() async {
    try {
      await _opening;
    } catch (_) {}
    if (_db.isConnected) await _db.close();
  }
}
