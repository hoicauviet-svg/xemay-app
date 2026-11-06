import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/models/finance/finance_models.dart';
import 'package:xemay_app/services/mongo_finance_repository.dart';

void check(bool ok, String message) {
  if (!ok) throw StateError(message);
}

Future<void> main() async {
  final uri =
      'mongodb://127.0.0.1:27017/XM_finance_test_${DateTime.now().microsecondsSinceEpoch}';
  final db = Db(uri);
  await db.open();
  final repo = MongoFinanceRepository(uri: uri);
  try {
    final cash = CashEntryDraft()
      ..amount = '100000'
      ..reason = 'Thu thử';
    final key = ObjectId().oid;
    final cashId = await repo.createCash(cash, requestId: key);
    check(await repo.createCash(cash, requestId: key) == cashId, 'Cash retry');
    await db.collection('ThuChiKhac').insertMany([
      for (var i = 0; i < 35; i++)
        {
          'ThuChiId': i + 100,
          'NgayThang': DateTime.utc(2026, 1, 1),
          'ThuChi': false,
          'SoTien': 1000.0,
          'LyDo': 'Chi thử',
        },
    ]);
    final all = await repo.cashEntries();
    check(
      all.total == 36 &&
          all.rows.length == 30 &&
          all.income == 100000 &&
          all.expense == 35000,
      'Cash totals or paging',
    );
    check((await repo.cashEntries(page: 1)).rows.length == 6, 'Second page');
    check((await repo.cashEntries(type: 'income')).total == 1, 'Income true');
    check(
      (await repo.cashEntries(search: 'Chi thử')).total == 35,
      'Cash search',
    );
    await db.collection('ThuChiKhac').insertMany([
      {
        'ThuChiId': 200,
        'NgayThang': DateTime.utc(2026, 2, 1),
        'ThuChi': true,
        'SoTien': 10.0,
        'LyDo': 'Boundary',
      },
      {
        'ThuChiId': 201,
        'NgayThang': DateTime.utc(2026, 2, 2, 23, 59),
        'ThuChi': true,
        'SoTien': 20.0,
        'LyDo': 'Boundary',
      },
      {
        'ThuChiId': 202,
        'NgayThang': DateTime.utc(2026, 2, 3),
        'ThuChi': true,
        'SoTien': 40.0,
        'LyDo': 'Boundary',
      },
    ]);
    final dated = await repo.cashEntries(
      search: 'Boundary',
      type: 'income',
      fromDate: DateTime(2026, 2, 1),
      toDate: DateTime(2026, 2, 2),
    );
    check(
      dated.total == 2 && dated.income == 30,
      'Date range must include whole end day and exclude next day',
    );
    check(
      (await repo.cashEntries(
            fromDate: DateTime(2026, 2, 3),
            search: 'Boundary',
          )).total ==
          1,
      'Open date boundary',
    );
    await db.collection('ThuChiKhac').deleteMany({'LyDo': 'Boundary'});
    final draft = FundingLoanDraft()
      ..amount = '1000000'
      ..partner = 'Đối tác thử'
      ..rate = '3'
      ..date = DateTime.utc(2026, 1, 1)
      ..dueDate = DateTime.utc(2027, 1, 1);
    final loanKey = ObjectId().oid;
    final id = await repo.createLoan(draft, requestId: loanKey);
    check(await repo.createLoan(draft, requestId: loanKey) == id, 'Loan retry');
    check(
      (await repo.loanDetails(id)).interestAt(DateTime.utc(2026, 1, 31)) ==
          30000,
      'Monthly interest',
    );
    FundingPaymentDraft pay(int amount, int interest) => FundingPaymentDraft(
      loanId: id,
      date: DateTime.utc(2026, 1, 11),
      principal: amount,
      interest: interest,
    );
    final pkey = ObjectId().oid;
    await repo.repay(pay(200000, 10000), requestId: pkey);
    await repo.repay(pay(200000, 10000), requestId: pkey);
    var detail = await repo.loanDetails(id);
    check(
      detail.remaining == 800000 && detail.payments.length == 1,
      'Payment retry/balance',
    );
    check(
      detail.interestAt(DateTime.utc(2026, 1, 21)) == 8000,
      'New interest anchor',
    );
    try {
      await repo.repay(pay(900000, 0), requestId: ObjectId().oid);
      throw StateError('Overpay accepted');
    } on FinanceException {
      // Expected: the repository must reject overpayment.
    }
    for (final stage in ['afterBalance', 'afterHistory']) {
      var crash = true;
      final failing = MongoFinanceRepository(
        uri: uri,
        checkpoint: (s) async {
          if (crash && s == stage) {
            crash = false;
            throw StateError('Simulated interruption');
          }
        },
      );
      final request = ObjectId().oid;
      try {
        await failing.repay(pay(100000, 0), requestId: request);
        throw StateError('Checkpoint not reached');
      } on StateError catch (e) {
        check(e.message == 'Simulated interruption', 'Wrong failure');
      }
      await failing.close();
      await repo.repay(pay(100000, 0), requestId: request);
    }
    detail = await repo.loanDetails(id);
    check(
      detail.remaining == 600000 && detail.payments.length == 3,
      'Recovery double debited',
    );
    check(detail.loan['ThanhToanDangLuu'] == null, 'Pending not cleared');
    final concurrentKey = ObjectId().oid;
    final other = MongoFinanceRepository(uri: uri);
    try {
      final results = await Future.wait([
        repo
            .repay(pay(100000, 0), requestId: concurrentKey)
            .then((_) => true, onError: (_) => false),
        other
            .repay(pay(100000, 0), requestId: concurrentKey)
            .then((_) => true, onError: (_) => false),
      ]);
      check(results.any((ok) => ok), 'Both concurrent requests failed');
      await repo.repay(pay(100000, 0), requestId: concurrentKey);
      check(
        (await repo.loanDetails(id)).remaining == 500000,
        'Concurrent retry debited twice',
      );
    } finally {
      await other.close();
    }
    await repo.repay(pay(500000, 0), requestId: ObjectId().oid);
    check(
      (await repo.loans()).total == 0 &&
          (await repo.loans(status: 'closed')).total == 1,
      'Closed filter',
    );
    check(
      await db.collection('ThuChiKhac').count() == 36,
      'Funding created duplicate cash flow',
    );
    await db.collection('VayVon').insertMany([
      for (var i = 100; i < 135; i++)
        {
          'IdVayVon': i,
          'DoiTac': 'Bulk loans',
          'SoTienVay': 100.0,
          'TongConNo': 20.0,
        },
    ]);
    final unpaged = await repo.loans(search: 'Bulk loans', status: 'all');
    check(
      unpaged.total == 35 && unpaged.rows.length == 35,
      'Loans still paginated',
    );
    stdout.writeln(
      'PASS: finance totals, paging, source flags, monthly interest, create/payment retries, interruption recovery, debt limits and settlement.',
    );
  } finally {
    await repo.close();
    await db.drop();
    await db.close();
  }
}
