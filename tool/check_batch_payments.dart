import 'dart:io';
import 'dart:typed_data';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/models/batches/batch_models.dart';
import 'package:xemay_app/services/mongo_batch_repository.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  final uri =
      'mongodb://127.0.0.1:27017/XM_batch_payment_test_${DateTime.now().microsecondsSinceEpoch}';
  final db = Db(uri);
  await db.open();
  final repo = MongoBatchRepository(uri: uri);
  final pdf = PaymentDocument(
    name: 'bien-lai.pdf',
    mimeType: 'application/pdf',
    bytes: Uint8List.fromList('%PDF-1.4\nchung tu'.codeUnits),
  );
  final image = PaymentDocument(
    name: 'anh.png',
    mimeType: 'image/png',
    bytes: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0]),
  );
  BatchPaymentPreview payment(int amount, {List<PaymentDocument>? documents}) =>
      BatchPaymentPreview(
        batchId: 42,
        amount: amount,
        date: DateTime(2026, 11, 4),
        notes: 'Thu chứng từ',
        documents: documents ?? [pdf, image],
      );
  try {
    await db.collection('NhapHang').insertOne({
      'IdNhapHang': 42,
      'NgayNhap': DateTime.utc(2026, 11, 1),
      'SoTien': 200000,
      'SoTienDaTra': 50000,
      'SoTienConNo': 150000,
    });
    await repo.connect();
    final id = ObjectId().oid;
    await repo.pay(payment(40000), requestId: id);
    await repo.pay(payment(40000), requestId: id);
    var history = await repo.payments(42);
    var batch = (await repo.findById(42))!;
    check(
      batch.remaining == 110000 && batch.paid == 90000 && history.length == 1,
      'Payment duplicated or balances wrong',
    );
    check(
      history.single.documents.length == 2 &&
          history.single.documents.first.bytes.join(',') == pdf.bytes.join(','),
      'PDF bytes changed',
    );
    check(
      history.single.documents.last.bytes.join(',') == image.bytes.join(','),
      'Image bytes changed',
    );
    bool rejected = false;
    try {
      await repo.pay(payment(110001), requestId: ObjectId().oid);
    } on BatchPaymentException {
      rejected = true;
    }
    check(rejected, 'Overpayment accepted');
    final bad = PaymentDocument(
      name: 'fake.pdf',
      mimeType: 'application/pdf',
      bytes: Uint8List.fromList([1, 2, 3]),
    );
    rejected = false;
    try {
      await repo.pay(payment(1, documents: [bad]), requestId: ObjectId().oid);
    } on BatchPaymentException {
      rejected = true;
    }
    check(rejected, 'Invalid document accepted');
    bool fail = true;
    final interrupted = MongoBatchRepository(
      uri: uri,
      checkpoint: (point) async {
        if (fail && point == 'afterBalance') {
          fail = false;
          throw StateError('Interrupted');
        }
      },
    );
    final retry = ObjectId().oid;
    try {
      await interrupted.pay(payment(10000), requestId: retry);
    } catch (_) {}
    history = await repo.payments(42);
    check(
      history.length == 2 && history.first.documents.length == 2,
      'Pending payment or attachments not recovered',
    );
    await interrupted.pay(payment(10000), requestId: retry);
    await interrupted.close();
    check(
      (await repo.findById(42))!.remaining == 100000,
      'Retry charged twice',
    );

    bool failHistory = true;
    final afterHistory = MongoBatchRepository(
      uri: uri,
      checkpoint: (point) async {
        if (failHistory && point == 'afterHistory') {
          failHistory = false;
          throw StateError('Lost confirmation');
        }
      },
    );
    final historyToken = ObjectId().oid;
    try {
      await afterHistory.pay(payment(5000), requestId: historyToken);
    } catch (_) {}
    await afterHistory.pay(payment(5000), requestId: historyToken);
    await afterHistory.close();
    check(
      (await repo.findById(42))!.remaining == 95000 &&
          (await repo.payments(42)).length == 3,
      'History acknowledgement retry duplicated payment',
    );
    final oversized = PaymentDocument(
      name: 'large.pdf',
      mimeType: 'application/pdf',
      bytes: Uint8List(PaymentDocument.maxTotalBytes + 1),
    );
    rejected = false;
    try {
      await repo.pay(
        payment(1, documents: [oversized]),
        requestId: ObjectId().oid,
      );
    } on BatchPaymentException {
      rejected = true;
    }
    check(rejected, 'Oversized documents accepted');
    final other = MongoBatchRepository(uri: uri);
    final results = await Future.wait(
      [repo, other].map((r) async {
        try {
          await r.pay(payment(70000, documents: []), requestId: ObjectId().oid);
          return true;
        } on BatchPaymentException {
          return false;
        }
      }),
    );
    check(
      results.where((r) => r).length == 1,
      'Concurrent overpayment accepted',
    );
    await other.close();
    await repo.pay(payment(25000, documents: []), requestId: ObjectId().oid);
    batch = (await repo.findById(42))!;
    check(
      batch.remaining == 0 && batch.paid == 200000,
      'Full settlement incorrect',
    );
    check((await repo.payments(42)).length == 5, 'History count incorrect');
    stdout.writeln(
      'PASS: payment balances, images/PDF binary roundtrip, retry, invalid documents, overpayment, crash recovery and concurrent settlement.',
    );
  } finally {
    await repo.close();
    await db.drop();
    await db.close();
  }
}
