import '../models/maintenance/record_maintenance.dart';
import 'mongo_record_maintenance.dart';
import '../models/finance/cash_category.dart';
import 'package:mongo_dart/mongo_dart.dart';
import '../core/config/database_config.dart';
import '../models/finance/finance_models.dart';
import '../models/repositories/finance_repository.dart';

class MongoFinanceRepository implements FinanceRepository {
  MongoFinanceRepository({String? uri, this.checkpoint})
    : _db = Db(uri ?? DatabaseConfig.mongoUri);
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

  Future<void> _checked(Future<dynamic> operation) async {
    final r = await operation;
    if (!r.isSuccess || r.hasWriteErrors) {
      throw StateError('Chưa xác nhận lưu dữ liệu');
    }
  }

  bool _same(Map<String, dynamic> row, Map<String, dynamic> values) =>
      values.entries.every((e) => row[e.key] == e.value);
  void _validateId(String id) {
    if (!RegExp(r'^[a-f0-9]{24}$').hasMatch(id)) {
      throw const FinanceException('Yêu cầu lưu không hợp lệ.');
    }
  }

  Future<int> _next(String collection, String field) async {
    final last = await _db
        .collection(collection)
        .modernFind(sort: {field: -1}, limit: 1)
        .toList();
    final counter = _db.collection('_app_counters');
    await _checked(
      counter.updateOne(
        {'_id': collection},
        {
          r'$max': {'value': last.isEmpty ? 0 : last.first[field]},
        },
        upsert: true,
      ),
    );
    final row = await counter.findAndModify(
      query: {'_id': collection},
      update: {
        r'$inc': {'value': 1},
      },
      returnNew: true,
    );
    return (row!['value'] as num).toInt();
  }

  Future<int> _create(
    String collection,
    String field,
    Map<String, dynamic> values,
    String requestId,
  ) async {
    _validateId(requestId);
    await _connect();
    final id = '$collection-$requestId';
    final rows = _db.collection(collection);
    var row = await rows.findOne({'_id': id});
    if (row == null) {
      final next = await _next(collection, field);
      await _checked(
        rows.updateOne(
          {'_id': id},
          {
            r'$setOnInsert': {'_id': id, field: next, ...values},
          },
          upsert: true,
        ),
      );
      row = (await rows.findOne({'_id': id}))!;
    }
    if (!_same(row, values)) {
      throw const FinanceException('Yêu cầu lưu đã có nội dung khác.');
    }
    return (row[field] as num).toInt();
  }

  @override
  Future<List<CashCategory>> categories() async {
    await _connect();
    final rows = await _db.collection('DanhMucThuChi').find().toList();
    final values = {for (final c in CashCategory.defaults) c.id: c};
    for (final row in rows) {
      final id = row['_id'] as String;
      if (row['HoatDong'] == false) {
        values.remove(id);
      } else {
        values[id] = CashCategory(
          id,
          row['TenDanhMuc'] as String,
          row['ThuChi'] == true,
        );
      }
    }
    return values.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Future<void> saveCategory(CashCategory category) async {
    if (category.name.trim().isEmpty || category.name.length > 100) {
      throw const FinanceException('Nhập tên danh mục từ 1 đến 100 ký tự.');
    }
    await _connect();
    await _checked(
      _db
          .collection('DanhMucThuChi')
          .updateOne(
            {'_id': category.id},
            {
              r'$set': {...category.toFields()}..remove('_id'),
            },
            upsert: true,
          ),
    );
  }

  @override
  Future<void> archiveCategory(String id) async {
    await _connect();
    await _checked(
      _db
          .collection('DanhMucThuChi')
          .updateOne(
            {'_id': id},
            {
              r'$set': {'HoatDong': false},
            },
            upsert: true,
          ),
    );
  }

  @override
  Future<int> createCash(
    CashEntryDraft draft, {
    required String requestId,
  }) async {
    final error = draft.validate();
    if (error != null) throw FinanceException(error);
    _validateId(requestId);
    await _connect();
    final existing = await _db.collection('ThuChiKhac').findOne({
      '_id': 'ThuChiKhac-$requestId',
    });
    final fields = draft.toFields();
    fields['IdDanhMuc'] ??= draft.income ? 'other-income' : 'other-expense';
    fields['TenDanhMuc'] ??= draft.income ? 'Thu khác' : 'Chi khác';
    if (existing != null) {
      // A replay keeps the original category snapshot, even after archival.
      fields['TenDanhMuc'] = existing['TenDanhMuc'];
    } else if (draft.categoryId != null) {
      final matches = (await categories()).where(
        (c) => c.id == draft.categoryId && c.income == draft.income,
      );
      if (matches.isEmpty) {
        throw const FinanceException(
          'Danh mục không thuộc loại phiếu đã chọn hoặc đã ngừng sử dụng.',
        );
      }
      fields['TenDanhMuc'] = matches.single.name;
    }
    return _create('ThuChiKhac', 'ThuChiId', fields, requestId);
  }

  @override
  Future<int> createLoan(
    FundingLoanDraft draft, {
    required String requestId,
  }) async {
    final error = draft.validate();
    if (error != null) throw FinanceException(error);
    return _create('VayVon', 'IdVayVon', draft.toFields(), requestId);
  }

  @override
  Future<FinancePage> cashEntries({
    String search = '',
    String type = 'all',
    int page = 0,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    if (!['all', 'income', 'expense'].contains(type)) {
      throw ArgumentError.value(type);
    }
    await _connect();
    if (fromDate != null &&
        toDate != null &&
        financeDay(fromDate).isAfter(financeDay(toDate))) {
      throw ArgumentError('Ngày bắt đầu không được sau ngày kết thúc.');
    }
    final term = search.trim();
    final filter = <String, dynamic>{
      if (fromDate != null || toDate != null)
        'NgayThang': {
          if (fromDate != null) r'$gte': financeDay(fromDate),
          if (toDate != null)
            r'$lt': financeDay(toDate).add(const Duration(days: 1)),
        },
      if (type != 'all') 'ThuChi': type == 'income',
      if (term.isNotEmpty)
        r'$or': [
          {
            'LyDo': {r'$regex': RegExp.escape(term), r'$options': 'i'},
          },
          {
            'TenDanhMuc': {r'$regex': RegExp.escape(term), r'$options': 'i'},
          },
          if (int.tryParse(term) != null) {'ThuChiId': int.parse(term)},
        ],
    };
    final rows = await _db
        .collection('ThuChiKhac')
        .modernFind(
          filter: filter,
          sort: {'NgayThang': -1, 'ThuChiId': -1},
          skip: page == 0 ? null : page * 30,
          limit: 30,
        )
        .toList();
    final totals = await _db.collection('ThuChiKhac').aggregateToStream([
      {r'$match': filter},
      {
        r'$group': {
          '_id': r'$ThuChi',
          'total': {r'$sum': r'$SoTien'},
        },
      },
    ]).toList();
    num income = 0, expense = 0;
    for (final total in totals) {
      if (total['_id'] == true) {
        income = total['total'] as num;
      } else if (total['_id'] == false) {
        expense = total['total'] as num;
      }
    }
    return FinancePage(
      rows,
      await _db.collection('ThuChiKhac').count(filter),
      income: income,
      expense: expense,
    );
  }

  @override
  Future<FinancePage> loans({
    String search = '',
    String status = 'open',
  }) async {
    if (!['open', 'closed', 'all'].contains(status)) {
      throw ArgumentError.value(status);
    }
    await _connect();
    final term = search.trim();
    final filter = <String, dynamic>{
      if (status != 'all') 'TongConNo': status == 'open' ? {r'$gt': 0} : 0,
      if (term.isNotEmpty)
        r'$or': [
          for (final key in ['DoiTac', 'GhiChu'])
            {
              key: {r'$regex': RegExp.escape(term), r'$options': 'i'},
            },
          if (int.tryParse(term) != null) {'IdVayVon': int.parse(term)},
        ],
    };
    final rows = await _db
        .collection('VayVon')
        .modernFind(filter: filter, sort: {'NgayVay': -1, 'IdVayVon': -1})
        .toList();
    return FinancePage(rows, rows.length);
  }

  Future<void> _recover(int id) async {
    final row = await _db.collection('VayVon').findOne({'IdVayVon': id});
    if (row?['ThanhToanDangLuu'] is Map) await _finish(row!);
  }

  Future<void> _finish(Map<String, dynamic> loan) async {
    final payment = Map<String, dynamic>.from(loan['ThanhToanDangLuu'] as Map);
    await _checked(
      _db
          .collection('TraNoVayVon')
          .updateOne(
            {'_id': payment['_id']},
            {r'$setOnInsert': payment},
            upsert: true,
          ),
    );
    final saved = (await _db.collection('TraNoVayVon').findOne({
      '_id': payment['_id'],
    }))!;
    final fields = Map<String, dynamic>.from(payment)
      ..remove('IdTraNoVayVon')
      ..remove('ConNoGoc')
      ..remove('NgayTinhLaiTruocTra');
    if (!_same(saved, fields)) {
      await _checked(
        _db
            .collection('VayVon')
            .updateOne(
              {'_id': loan['_id'], 'ThanhToanDangLuu._id': payment['_id']},
              {
                r'$inc': {'TongConNo': payment['SoTienTraGoc']},
                r'$pull': {'_financePaymentIds': payment['_id']},
                r'$unset': {'ThanhToanDangLuu': ''},
              },
            ),
      );
      throw const FinanceException(
        'Yêu cầu thanh toán trùng với nội dung khác.',
      );
    }
    if (checkpoint != null) await checkpoint!('afterHistory');
    final date = payment['NgayTra'] as DateTime;
    final old = loan['NgayTinhLai'];
    await _checked(
      _db
          .collection('VayVon')
          .updateOne(
            {'_id': loan['_id'], 'ThanhToanDangLuu._id': payment['_id']},
            {
              r'$set': {
                if ((payment['SoTienTraLai'] as num) > 0 &&
                    (old is! DateTime || !old.isAfter(date)))
                  'NgayTinhLai': date,
              },
              r'$unset': {'ThanhToanDangLuu': ''},
            },
          ),
    );
  }

  @override
  Future<FundingDetails> loanDetails(int id) async {
    await _connect();
    await maintenance.ensureReadable(RecordKind.funding, id);
    await _recover(id);
    final row = await _db.collection('VayVon').findOne({'IdVayVon': id});
    if (row == null) {
      throw const FinanceException('Khoản vay không còn tồn tại.');
    }
    final payments = await _db
        .collection('TraNoVayVon')
        .modernFind(
          filter: {'IdVayVon': id},
          sort: {'NgayTra': -1, 'IdTraNoVayVon': -1},
        )
        .toList();
    return FundingDetails(loan: row, payments: payments);
  }

  @override
  Future<void> repay(
    FundingPaymentDraft payment, {
    required String requestId,
  }) async {
    final error = payment.validate();
    if (error != null) throw FinanceException(error);
    _validateId(requestId);
    await _connect();
    await _recover(payment.loanId);
    final fields = payment.toFields();
    final id = 'funding-payment-$requestId';
    if (await _db.collection('_record_deleted').findOne({
          '_id': 'TraNoVayVon:$id',
        }) !=
        null) {
      throw StateError(
        'Phiếu trả nợ này đã được xóa. Tạo yêu cầu thanh toán mới nếu cần.',
      );
    }
    final existing = await _db.collection('TraNoVayVon').findOne({'_id': id});
    if (existing != null) {
      if (!_same(existing, fields)) {
        throw const FinanceException('Nội dung thanh toán đã thay đổi.');
      }
      return;
    }
    final details = await loanDetails(payment.loanId);
    final due = details.remaining;
    if (due == null || !due.isFinite || due <= 0 || payment.principal > due) {
      throw const FinanceException(
        'Tiền gốc vượt số còn nợ hoặc khoản vay đã tất toán.',
      );
    }
    final loanDate = details.loan['NgayVay'];
    if (loanDate is DateTime &&
        financeDay(payment.date).isBefore(financeDay(loanDate))) {
      throw const FinanceException('Ngày trả không được trước ngày vay.');
    }
    final row = {
      '_id': id,
      'IdTraNoVayVon': await _next('TraNoVayVon', 'IdTraNoVayVon'),
      ...fields,
      'ConNoGoc': due - payment.principal,
      'NgayTinhLaiTruocTra':
          details.loan['NgayTinhLai'] ?? details.loan['NgayVay'],
    };
    final updated = await _db
        .collection('VayVon')
        .findAndModify(
          query: {
            '_id': details.loan['_id'],
            'TongConNo': due,
            'ThanhToanDangLuu': null,
            'SuaXoaDangLuu': null,
            '_financePaymentIds': {r'$ne': id},
          },
          update: {
            r'$addToSet': {'_financePaymentIds': id},
            r'$set': {
              'TongConNo': due - payment.principal,
              'ThanhToanDangLuu': row,
            },
          },
          returnNew: true,
        );
    if (updated == null) {
      await _recover(payment.loanId);
      final saved = await _db.collection('TraNoVayVon').findOne({'_id': id});
      if (saved != null && _same(saved, fields)) return;
      throw const FinanceException(
        'Công nợ vừa thay đổi. Vui lòng tải lại khoản vay.',
      );
    }
    if (checkpoint != null) await checkpoint!('afterBalance');
    await _finish(updated);
  }

  @override
  Future<void> close() async {
    try {
      await _opening;
    } catch (_) {}
    if (_db.isConnected) await _db.close();
  }
}
