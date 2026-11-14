import '../models/maintenance/record_maintenance.dart';
import 'mongo_record_maintenance.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'mongo_sync_journal.dart';
import '../core/config/database_config.dart';
import '../models/finance/finance_models.dart';
import '../models/finance/opening_debt.dart';
import '../models/repositories/opening_debt_repository.dart';

class MongoOpeningDebtRepository implements OpeningDebtRepository {
  MongoOpeningDebtRepository({String? uri, this.checkpoint})
    : _db = SyncTrackedDb(uri ?? DatabaseConfig.mongoUri);
  final Db _db;
  @override
  RecordMaintenance get maintenance => MongoRecordMaintenance(_db, _connect);

  final Future<void> Function(String)? checkpoint;
  Future<void>? _opening;
  Future<void> _connect() =>
      _opening ??= _open().whenComplete(() => _opening = null);
  Future<void> _open() async {
    if (!_db.isConnected) await _db.open(writeConcern: WriteConcern.journaled);
  }

  Future<void> _checked(Future<dynamic> action) async {
    final result = await action;
    if (!result.isSuccess || result.hasWriteErrors) {
      throw StateError('Chưa xác nhận lưu thanh toán.');
    }
  }

  bool _same(Map<String, dynamic> row, Map<String, dynamic> values) =>
      values.entries.every((e) => row[e.key] == e.value);
  Future<Map<String, dynamic>?> _customer(dynamic id) async {
    final n = int.tryParse('$id');
    return _db.collection('KhachHang').findOne({
      'IdKH': {
        r'$in': [id, ?n, '$id'],
      },
    });
  }

  @override
  Future<OpeningDebtPage> list({
    String search = '',
    String status = 'open',
  }) async {
    if (!['open', 'closed', 'all'].contains(status)) {
      throw ArgumentError('Bộ lọc không hợp lệ');
    }
    await _connect();
    final term = search.trim();
    final customers = term.isEmpty
        ? <Map<String, dynamic>>[]
        : await _db
              .collection('KhachHang')
              .modernFind(
                filter: {
                  r'$or': [
                    for (final key in ['TenKhachHang', 'SoDienThoai'])
                      {
                        key: {r'$regex': RegExp.escape(term), r'$options': 'i'},
                      },
                  ],
                },
                projection: {'IdKH': 1},
              )
              .toList();
    final ids = [
      for (final c in customers) ...[c['IdKH'], '${c['IdKH']}'],
    ];
    final filter = <String, dynamic>{
      if (status != 'all') 'SoCoNo': status == 'open' ? {r'$gt': 0} : 0,
      if (term.isNotEmpty)
        r'$or': [
          {
            'GhiChu': {r'$regex': RegExp.escape(term), r'$options': 'i'},
          },
          if (int.tryParse(term) != null) {'Id': int.parse(term)},
          if (ids.isNotEmpty)
            {
              'IdKH': {r'$in': ids},
            },
        ],
    };
    final rows = await _db
        .collection('NoCu')
        .modernFind(filter: filter, sort: {'Id': -1})
        .toList();
    final customerIds = <dynamic>{
      for (final row in rows) ...[
        row['IdKH'],
        '${row['IdKH']}',
        if (int.tryParse('${row['IdKH']}') != null) int.parse('${row['IdKH']}'),
      ],
    };
    final linkedCustomers = await _db
        .collection('KhachHang')
        .modernFind(
          filter: {
            'IdKH': {r'$in': customerIds.toList()},
          },
        )
        .toList();
    final byId = {for (final row in linkedCustomers) '${row['IdKH']}': row};
    final joined = [
      for (final row in rows) {...row, 'KhachHang': byId['${row['IdKH']}']},
    ];
    return OpeningDebtPage(joined, joined.length);
  }

  Future<void> _recover(int id) async {
    final debt = await _db.collection('NoCu').findOne({'Id': id});
    if (debt?['ThanhToanDangLuu'] is Map) await _finish(debt!);
  }

  Future<void> _finish(Map<String, dynamic> debt) async {
    final row = Map<String, dynamic>.from(debt['ThanhToanDangLuu'] as Map);
    await _checked(
      _db
          .collection('TraNoCu')
          .updateOne({'_id': row['_id']}, {r'$setOnInsert': row}, upsert: true),
    );
    final saved = (await _db.collection('TraNoCu').findOne({
      '_id': row['_id'],
    }))!;
    final fields = Map<String, dynamic>.from(row)
      ..remove('Id')
      ..remove('ConNo')
      ..remove('NgayTinhLaiTruocTra');
    if (!_same(saved, fields)) {
      await _checked(
        _db
            .collection('NoCu')
            .updateOne(
              {'_id': debt['_id'], 'ThanhToanDangLuu._id': row['_id']},
              {
                r'$inc': {
                  'SoCoNo': row['SoTienTra'],
                  'SoTienDaTra': -(row['SoTienTra'] as num),
                },
                r'$pull': {'_openingPaymentIds': row['_id']},
                r'$unset': {'ThanhToanDangLuu': ''},
              },
            ),
      );
      throw const FinanceException(
        'Yêu cầu thanh toán trùng với nội dung khác.',
      );
    }
    if (checkpoint != null) await checkpoint!('afterHistory');
    final date = row['NgayTra'] as DateTime;
    final old = debt['NgayTinhLai'];
    await _checked(
      _db
          .collection('NoCu')
          .updateOne(
            {'_id': debt['_id'], 'ThanhToanDangLuu._id': row['_id']},
            {
              r'$set': {
                if ((row['LaiThu'] as num) > 0 &&
                    (old is! DateTime || !old.isAfter(date)))
                  'NgayTinhLai': date,
              },
              r'$unset': {'ThanhToanDangLuu': ''},
            },
          ),
    );
  }

  @override
  Future<OpeningDebtDetails> details(int id) async {
    await _connect();
    await maintenance.ensureReadable(RecordKind.openingDebt, id);
    await _recover(id);
    final debt = await _db.collection('NoCu').findOne({'Id': id});
    if (debt == null) {
      throw const FinanceException('Khoản nợ không còn tồn tại.');
    }
    return OpeningDebtDetails(
      debt,
      await _customer(debt['IdKH']),
      await _db
          .collection('TraNoCu')
          .modernFind(filter: {'IdNoCu': id}, sort: {'NgayTra': -1, 'Id': -1})
          .toList(),
    );
  }

  Future<int> _next() async {
    final last = await _db
        .collection('TraNoCu')
        .modernFind(sort: {'Id': -1}, limit: 1)
        .toList();
    final counter = _db.collection('_app_counters');
    await _checked(
      counter.updateOne(
        {'_id': 'TraNoCu'},
        {
          r'$max': {'value': last.isEmpty ? 0 : last.first['Id']},
        },
        upsert: true,
      ),
    );
    final row = await counter.findAndModify(
      query: {'_id': 'TraNoCu'},
      update: {
        r'$inc': {'value': 1},
      },
      returnNew: true,
    );
    return (row!['value'] as num).toInt();
  }

  @override
  Future<void> pay(
    OpeningDebtPayment payment, {
    required String requestId,
  }) async {
    final error = payment.validate();
    if (error != null) throw FinanceException(error);
    if (!RegExp(r'^[a-f0-9]{24}$').hasMatch(requestId)) {
      throw const FinanceException('Yêu cầu lưu không hợp lệ.');
    }
    await _connect();
    await _recover(payment.debtId);
    final id = 'opening-payment-$requestId', fields = payment.toFields();
    if (await _db.collection('_record_deleted').findOne({
          '_id': 'TraNoCu:$id',
        }) !=
        null) {
      throw StateError(
        'Phiếu trả nợ này đã được xóa. Tạo yêu cầu thanh toán mới nếu cần.',
      );
    }
    final existing = await _db.collection('TraNoCu').findOne({'_id': id});
    if (existing != null) {
      if (!_same(existing, fields)) {
        throw const FinanceException('Nội dung thanh toán đã thay đổi.');
      }
      return;
    }
    final data = await details(payment.debtId);
    final due = data.remaining, paid = data.debt['SoTienDaTra'];
    if (due == null ||
        !due.isFinite ||
        due <= 0 ||
        paid is! num ||
        !paid.isFinite ||
        payment.principal > due) {
      throw const FinanceException(
        'Tiền trả nợ vượt số còn nợ hoặc khoản nợ đã trả hết.',
      );
    }
    final row = {
      '_id': id,
      'Id': await _next(),
      ...fields,
      'ConNo': due - payment.principal,
      'NgayTinhLaiTruocTra': data.debt['NgayTinhLai'],
    };
    final updated = await _db
        .collection('NoCu')
        .findAndModify(
          query: {
            '_id': data.debt['_id'],
            'SoCoNo': due,
            'SoTienDaTra': paid,
            'ThanhToanDangLuu': null,
            'SuaXoaDangLuu': null,
            '_openingPaymentIds': {r'$ne': id},
          },
          update: {
            r'$addToSet': {'_openingPaymentIds': id},
            r'$set': {
              'SoCoNo': due - payment.principal,
              'SoTienDaTra': paid + payment.principal,
              'ThanhToanDangLuu': row,
            },
          },
          returnNew: true,
        );
    if (updated == null) {
      await _recover(payment.debtId);
      final saved = await _db.collection('TraNoCu').findOne({'_id': id});
      if (saved != null && _same(saved, fields)) return;
      throw const FinanceException(
        'Công nợ vừa thay đổi. Vui lòng tải lại khoản nợ.',
      );
    }
    if (checkpoint != null) await checkpoint!('afterBalance');
    await _finish(updated);
  }

  @override
  Future<void> close() async {
    try {
      await _opening;
    } catch (_) {
      /* Connection failed. */
    }
    if (_db.isConnected) await _db.close();
  }
}
