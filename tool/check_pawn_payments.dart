import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/models/pawn/pawn_models.dart';
import 'package:xemay_app/services/mongo_pawn_repository.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

PawnPaymentDraft payment(
  int principal, {
  int interest = 0,
  int collected = 0,
  int pawnId = 42,
}) => PawnPaymentDraft(
  pawnId: pawnId,
  date: DateTime(2026, 11, 4),
  principal: principal,
  interest: interest,
  collectedInterest: collected,
);
Future<void> main() async {
  final uri =
      'mongodb://127.0.0.1:27017/XM_pawn_payment_test_${DateTime.now().microsecondsSinceEpoch}';
  final db = Db(uri);
  await db.open();
  final repo = MongoPawnRepository(uri: uri);
  try {
    await db.collection('KhachHang').insertOne({
      'IdKH': 1,
      'TenKhachHang': 'Khách thử',
    });
    await db.collection('CamDo').insertMany([
      for (final id in [42, 43])
        {
          'IdCamDo': id,
          'IdKhachHang': 1,
          'SoTienVay': 1000000.0,
          'NgayVay': DateTime.utc(2026, 11, 1),
          'TrangThai': false,
        },
    ]);
    await db.collection('TraNoCamDo').insertOne({
      '_id': 1,
      'IdTraNoCamDo': 1,
      'IdCamDo': 42,
      'NgayTra': DateTime.utc(2026, 11, 2),
      'TienGoc': 200000.0,
      'SoTienLai': 50000.0,
      'LaiThu': null,
    });
    final original = (await db.collection('TraNoCamDo').findOne({'_id': 1}))!;
    var detail = await repo.details(42);
    check(
      detail.remaining == 800000 &&
          detail.customer?['TenKhachHang'] == 'Khách thử',
      'Details or principal balance wrong',
    );
    final id = ObjectId().oid;
    await repo.pay(
      payment(0, interest: 30000, collected: 20000),
      requestId: id,
    );
    await repo.pay(
      payment(0, interest: 30000, collected: 20000),
      requestId: id,
    );
    detail = await repo.details(42);
    check(
      detail.remaining == 800000 && detail.payments.length == 2,
      'Interest payment affected principal or duplicated',
    );
    check(
      detail.interestStartDate == DateTime.utc(2026, 11, 4),
      'Interest anchor did not advance after collecting interest',
    );
    check(
      detail.contract['NgayVay'] == DateTime.utc(2026, 11, 1),
      'Original loan date was altered',
    );
    final latest = detail.payments.first;
    check(
      latest['SoTienLai'] == 30000 &&
          latest['LaiThu'] == 20000 &&
          latest['TienGoc'] == 0,
      'Calculated and collected interest mixed',
    );
    check(
      latest.keys.toSet().difference({
        '_id',
        'IdTraNoCamDo',
        'IdCamDo',
        'NgayTra',
        'TienGoc',
        'SoTienLai',
        'LaiThu',
      }).isEmpty,
      'Unrequested payment fields created',
    );
    bool rejected = false;
    try {
      await repo.pay(payment(800001), requestId: ObjectId().oid);
    } on PawnException {
      rejected = true;
    }
    check(rejected, 'Overpayment accepted');
    rejected = false;
    try {
      await repo.pay(payment(0), requestId: ObjectId().oid);
    } on PawnException {
      rejected = true;
    }
    check(rejected, 'Zero actual collection accepted');
    bool fail = true;
    final interrupted = MongoPawnRepository(
      uri: uri,
      checkpoint: (point) async {
        if (fail && point == 'afterReserve') {
          fail = false;
          throw StateError('Interrupted');
        }
      },
    );
    final token = ObjectId().oid;
    try {
      await interrupted.pay(
        PawnPaymentDraft(
          pawnId: 42,
          date: DateTime(2026, 11, 4),
          principal: 100000,
          interest: 0,
          collectedInterest: 0,
          appointmentDate: DateTime(2026, 11, 20),
        ),
        requestId: token,
      );
    } catch (_) {}
    detail = await repo.details(42);
    check(
      detail.remaining == 700000 && detail.payments.length == 3,
      'Pending payment not recovered',
    );
    await interrupted.pay(
      PawnPaymentDraft(
        pawnId: 42,
        date: DateTime(2026, 11, 4),
        principal: 100000,
        interest: 0,
        collectedInterest: 0,
        appointmentDate: DateTime(2026, 11, 20),
      ),
      requestId: token,
    );
    await interrupted.close();
    check(
      (await repo.details(42)).contract['NgayHan'] ==
          DateTime.utc(2026, 11, 20),
      'Recovered appointment lost',
    );
    bool historyFail = true;
    final afterHistory = MongoPawnRepository(
      uri: uri,
      checkpoint: (point) async {
        if (historyFail && point == 'afterHistory') {
          historyFail = false;
          throw StateError('Lost acknowledgement');
        }
      },
    );
    final token2 = ObjectId().oid;
    try {
      await afterHistory.pay(payment(50000), requestId: token2);
    } catch (_) {}
    await afterHistory.pay(payment(50000), requestId: token2);
    await afterHistory.close();
    check(
      (await repo.details(42)).remaining == 650000,
      'Lost acknowledgement charged twice',
    );

    final appointmentToken = ObjectId().oid;
    final appointmentPayment = PawnPaymentDraft(
      pawnId: 42,
      date: DateTime(2026, 11, 4),
      principal: 0,
      interest: 0,
      collectedInterest: 1000,
      appointmentDate: DateTime(2026, 12, 4),
    );
    await repo.pay(appointmentPayment, requestId: appointmentToken);
    await repo.pay(appointmentPayment, requestId: appointmentToken);
    check(
      (await repo.details(42)).contract['NgayHan'] == DateTime.utc(2026, 12, 4),
      'Appointment not applied',
    );
    final appointmentHistory = (await db.collection('TraNoCamDo').findOne({
      '_id': 'pawn-payment-$appointmentToken',
    }))!;
    check(
      appointmentHistory['NgayHen'] == DateTime.utc(2026, 12, 4),
      'Appointment audit missing',
    );
    final invalidAppointment = PawnPaymentDraft(
      pawnId: 42,
      date: DateTime(2026, 11, 4),
      principal: 0,
      interest: 0,
      collectedInterest: 1,
      appointmentDate: DateTime(2026, 11, 3),
    );
    rejected = false;
    try {
      await repo.pay(invalidAppointment, requestId: ObjectId().oid);
    } on PawnException {
      rejected = true;
    }
    check(rejected, 'Appointment before payment accepted');
    final other = MongoPawnRepository(uri: uri);
    final results = await Future.wait(
      [repo, other].map((r) async {
        try {
          await r.pay(payment(500000), requestId: ObjectId().oid);
          return true;
        } on PawnException {
          return false;
        }
      }),
    );
    check(
      results.where((r) => r).length == 1,
      'Concurrent principal overpayment accepted',
    );
    await other.close();
    detail = await repo.details(42);
    check(detail.remaining == 150000, 'Concurrent principal total incorrect');
    await repo.pay(payment(150000), requestId: ObjectId().oid);
    detail = await repo.details(42);
    check(
      detail.remaining == 0 &&
          detail.contract['TrangThai'] == true &&
          !detail.canPay,
      'Full principal return did not settle contract',
    );
    check(
      (await repo.fetch(
        status: 'active',
      )).rows.every((r) => r['IdCamDo'] != 42),
      'Settled contract remains active',
    );
    check(
      (await db.collection('TraNoCamDo').findOne({'_id': 1})).toString() ==
          original.toString(),
      'Legacy history altered',
    );
    rejected = false;
    try {
      await repo.pay(payment(1, pawnId: 43), requestId: id);
    } on PawnException {
      rejected = true;
    }
    check(rejected, 'Request ID reused across contracts');
    stdout.writeln(
      'PASS: exact historical fields, separate principal/calculated/collected interest, retry, crash recovery, concurrent overpayment protection, settlement and unchanged legacy history.',
    );
  } finally {
    await repo.close();
    await db.drop();
    await db.close();
  }
}
