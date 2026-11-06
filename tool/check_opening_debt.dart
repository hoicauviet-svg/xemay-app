import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/models/finance/finance_models.dart';
import 'package:xemay_app/models/finance/opening_debt.dart';
import 'package:xemay_app/services/mongo_opening_debt_repository.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  final uri =
      'mongodb://127.0.0.1:27017/XM_opening_debt_test_${DateTime.now().microsecondsSinceEpoch}';
  final db = Db(uri);
  await db.open();
  final repo = MongoOpeningDebtRepository(uri: uri);
  try {
    await db.collection('KhachHang').insertOne({
      'IdKH': 55,
      'TenKhachHang': 'Khách thử',
      'SoDienThoai': '0909876543',
    });
    await db.collection('NoCu').insertMany([
      for (final id in [1, 2])
        {
          'Id': id,
          'IdKH': '55',
          'TongNo': 1000000.0,
          'SoTienDaTra': 200000.0,
          'SoCoNo': 800000.0,
          'NgayHen': DateTime.utc(2026, 1, 1),
          'NgayTinhLai': DateTime.utc(2026, 1, 1),
          'GhiChu': 'Nợ mua xe',
        },
    ]);
    await db.collection('TraNoCu').insertOne({
      'Id': 1,
      'IdNoCu': 1,
      'SoTienTra': 200000.0,
      'ConNo': 800000.0,
      'TienLai': 0.0,
      'LaiThu': null,
      'NgayTra': DateTime.utc(2026, 1, 1),
    });
    check((await repo.list()).total == 2, 'Default filter');
    final searched = await repo.list(search: 'Khách thử');
    check(
      searched.total == 2 &&
          (searched.rows.first['KhachHang'] as Map)['IdKH'] == 55,
      'Legacy string customer ID',
    );
    check((await repo.list(search: '090987')).total == 2, 'Phone search');
    check((await repo.list(search: '1')).total == 1, 'ID search');
    OpeningDebtPayment pay(int n, {int id = 1, int collected = 1000}) =>
        OpeningDebtPayment(
          debtId: id,
          date: DateTime.utc(2026, 1, 11),
          principal: n,
          interest: 2000,
          collectedInterest: collected,
        );
    final key = ObjectId().oid;
    await repo.pay(pay(100000), requestId: key);
    await repo.pay(pay(100000), requestId: key);
    var data = await repo.details(1);
    check(
      data.remaining == 700000 &&
          data.debt['SoTienDaTra'] == 300000 &&
          data.debt['TongNo'] == 1000000,
      'Header balance or retry',
    );
    check(
      data.payments.length == 2 &&
          data.payments.first['ConNo'] == 700000 &&
          data.payments.first['LaiThu'] == 1000,
      'History mapping',
    );
    check(
      data.debt['NgayTinhLai'] == DateTime.utc(2026, 1, 11),
      'Interest date update',
    );
    try {
      await repo.pay(pay(700001), requestId: ObjectId().oid);
      throw StateError('Overpay accepted');
    } on FinanceException {
      /* Expected rejection. */
    }
    try {
      await repo.pay(pay(10, id: 999), requestId: ObjectId().oid);
      throw StateError('Missing debt accepted');
    } on FinanceException {
      /* Expected rejection. */
    }
    for (final stage in ['afterBalance', 'afterHistory']) {
      var crash = true;
      final interrupted = MongoOpeningDebtRepository(
        uri: uri,
        checkpoint: (s) async {
          if (crash && s == stage) {
            crash = false;
            throw StateError('interrupted');
          }
        },
      );
      final request = ObjectId().oid;
      try {
        await interrupted.pay(pay(100000, collected: 0), requestId: request);
        throw StateError('Checkpoint missed');
      } on StateError catch (e) {
        check(e.message == 'interrupted', 'Wrong error');
      }
      await interrupted.close();
      await repo.pay(pay(100000, collected: 0), requestId: request);
    }
    data = await repo.details(1);
    check(
      data.remaining == 500000 &&
          data.debt['SoTienDaTra'] == 500000 &&
          data.payments.length == 4,
      'Recovery duplicate',
    );
    final other = MongoOpeningDebtRepository(uri: uri),
        request = ObjectId().oid;
    try {
      final results = await Future.wait([
        repo
            .pay(pay(100000), requestId: request)
            .then((_) => true, onError: (_) => false),
        other
            .pay(pay(100000), requestId: request)
            .then((_) => true, onError: (_) => false),
      ]);
      check(results.any((v) => v), 'Concurrent save failed');
      await repo.pay(pay(100000), requestId: request);
      check(
        (await repo.details(1)).remaining == 400000,
        'Concurrent double debit',
      );
    } finally {
      await other.close();
    }
    await repo.pay(pay(400000), requestId: ObjectId().oid);
    data = await repo.details(1);
    check(
      data.remaining == 0 && data.debt['SoTienDaTra'] == 1000000,
      'Full repayment',
    );
    check(
      (await repo.list()).total == 1 &&
          (await repo.list(status: 'closed')).total == 1,
      'Status filters',
    );
    check(
      await db.collection('NoCu').count() == 2,
      'Created debt unexpectedly',
    );
    await db.collection('NoCu').insertMany([
      for (var i = 100; i < 135; i++)
        {
          'Id': i,
          'IdKH': '55',
          'TongNo': 100.0,
          'SoTienDaTra': 80.0,
          'SoCoNo': 20.0,
          'GhiChu': 'Bulk debts',
        },
    ]);
    final unpaged = await repo.list(search: 'Bulk debts', status: 'all');
    check(
      unpaged.total == 35 &&
          unpaged.rows.length == 35 &&
          unpaged.rows.every((r) => (r['KhachHang'] as Map?)?['IdKH'] == 55),
      'Old debt still paginated or bulk customer join failed',
    );
    stdout.writeln(
      'PASS: old debt source fields, string customer links, search, filters, payment limits, header/history balances, retries, recovery and concurrent duplicate protection.',
    );
  } finally {
    await repo.close();
    await db.drop();
    await db.close();
  }
}
