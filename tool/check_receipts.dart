import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/models/goods_receipt/goods_receipt_models.dart';
import 'package:xemay_app/services/mongo_receipt_repository.dart';
import 'package:xemay_app/services/mongo_batch_repository.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

ReceiptPreview draft(
  ReceiptProductType type, {
  int? batchId,
  int paidAmount = 0,
  String carrier = '',
  String? carrierId,
}) => ReceiptPreview(
  type: type,
  mode: ReceiptMode.single,
  date: DateTime(2026, 11, 4),
  partner: '',
  notes: '',
  batchId: batchId,
  paidAmount: paidAmount,
  carrier: carrier,
  carrierId: carrierId,
  lines: [
    ReceiptLine(
      name: 'Sản phẩm thử',
      quantity: type.isVehicle ? 1 : 3,
      unitPrice: 100000,
      frameNumber: 'FRAME-TEST',
      engineNumber: 'ENGINE-TEST',
      plate: '',
      costs: [
        ReceiptCost(DateTime(2026, 11, 4), 50000, 'Vận chuyển'),
        ReceiptCost(DateTime(2026, 11, 5), 25000, 'Sửa chữa'),
      ],
    ),
  ],
);
Future<void> main() async {
  final name = 'XM_receipt_test_${DateTime.now().microsecondsSinceEpoch}';
  final uri = 'mongodb://127.0.0.1:27017/$name';
  final db = Db(uri);
  await db.open();
  final schema = await Process.run('/private/tmp/xemay-sql-env/bin/python', [
    '../upgrade_receipt_costs.py',
    '--database',
    name,
    '--apply',
  ]);
  check(schema.exitCode == 0, '${schema.stderr}');
  final repo = MongoReceiptRepository(uri: uri);
  final reader = MongoBatchRepository(uri: uri);
  try {
    await db.collection('NhapHang').insertOne({
      'IdNhapHang': 42,
      'SoLuong': 2,
      'SoTien': 200000,
      'SoTienDaTra': 50000,
      'SoTienConNo': 150000,
    });
    final header = await db.collection('NhapHang').findOne({'IdNhapHang': 42});
    final receipt = draft(ReceiptProductType.newVehicle, batchId: 42);
    final id = ObjectId().oid;
    await repo.save(receipt, id);
    await repo.save(receipt, id);
    check(await db.collection('Xe').count() == 1, 'Retry duplicated vehicle');
    final vehicle = (await db.collection('Xe').findOne())!;
    check(
      vehicle['TongChiPhi'] == 75000 && (vehicle['ChiPhi'] as List).length == 2,
      'Costs not persisted',
    );
    check(
      vehicle['GiaNhap'] == 100000 && vehicle['TinhTrang'] == true,
      'Wrong cost or state',
    );
    check(
      (await db.collection('NhapHang').findOne({
            'IdNhapHang': 42,
          })).toString() ==
          header.toString(),
      'Legacy finances changed',
    );
    await reader.connect();
    check(
      (await reader.products(
            (await reader.findById(42))!,
            ReceiptProductType.newVehicle,
          )).length ==
          1,
      'Batch list not updated',
    );
    bool fail = true;
    final interrupted = MongoReceiptRepository(
      uri: uri,
      checkpoint: (point) async {
        if (fail && point == 'afterStock') {
          fail = false;
          throw StateError('Interrupted');
        }
      },
    );
    final partId = ObjectId().oid;
    final paidPart = draft(
      ReceiptProductType.part,
      paidAmount: 100000,
      carrier: 'Vận chuyển thử',
      carrierId: 'carrier-test',
    );
    try {
      await interrupted.save(paidPart, partId);
    } catch (_) {}
    await interrupted.save(paidPart, partId);
    check(
      (await db.collection('TonKhoPhuTung').findOne())!['SoLuongTon'] == 3,
      'Retry incremented stock twice',
    );
    check(
      await db.collection('NhapHang').count({
            'SoThamChieu': {r'$exists': true},
          }) ==
          0,
      'Unsupported voucher field written',
    );

    final partHeader = (await db.collection('NhapHang').findOne({
      '_id': '$partId-h',
    }))!;
    check(
      partHeader['SoTienDaTra'] == 100000 &&
          partHeader['SoTienConNo'] == 200000,
      'Single payment balances wrong',
    );
    check(
      partHeader['IdVanChuyen'] == 'carrier-test' &&
          partHeader['NguoiCho'] == 'Vận chuyển thử',
      'Carrier not saved',
    );
    final payments = await reader.payments(partHeader['IdNhapHang'] as int);
    check(
      payments.length == 1 &&
          payments.single.amount == 100000 &&
          payments.single.remaining == 200000,
      'Initial payment missing or duplicated after retry',
    );
    final fullId = ObjectId().oid;
    await repo.save(
      draft(ReceiptProductType.usedVehicle, paidAmount: 100000),
      fullId,
    );
    final fullHeader = (await db.collection('NhapHang').findOne({
      '_id': '$fullId-h',
    }))!;
    check(
      fullHeader['SoTienConNo'] == 0 && fullHeader['NguoiCho'] == '',
      'Full payment or self pickup wrong',
    );
    bool rejected = false;
    try {
      await repo.save(
        draft(ReceiptProductType.part, paidAmount: 300001),
        ObjectId().oid,
      );
    } on ArgumentError {
      rejected = true;
    }
    check(rejected, 'Overpayment accepted');
    await interrupted.close();

    check(!partHeader.containsKey('HinhThucNhap'), 'Unexpected receipt mode');
    final batchToken = ObjectId().oid;
    final batchReceipt = ReceiptPreview(
      type: ReceiptProductType.newVehicle,
      mode: ReceiptMode.batch,
      date: DateTime(2026, 11, 4),
      partner: 'Nhà cung cấp thử',
      notes: '',
      batchInfo: BatchReceiptInfo(
        quantity: 1,
        totalAmount: 100000,
        deliveredBy: 'Vận chuyển thử',
        origin: 'Nhà cung cấp thử',
        date: DateTime(2026, 11, 4),
        paidAmount: 30000,
      ),
      lines: draft(ReceiptProductType.newVehicle).lines,
    );
    await repo.save(batchReceipt, batchToken);
    await repo.save(batchReceipt, batchToken);
    final batchHeader = (await db.collection('NhapHang').findOne({
      '_id': '$batchToken-h',
    }))!;
    final batchPayments = await reader.payments(
      batchHeader['IdNhapHang'] as int,
    );
    check(
      !batchHeader.containsKey('HinhThucNhap') &&
          batchHeader['SoTienDaTra'] == 30000 &&
          batchHeader['SoTienConNo'] == 70000,
      'Batch balances or mode incorrect',
    );
    check(
      batchPayments.length == 1 &&
          batchPayments.single.amount == 30000 &&
          batchPayments.single.remaining == 70000,
      'Batch initial payment missing or duplicated',
    );
    final usedId = ObjectId().oid;
    await repo.save(draft(ReceiptProductType.usedVehicle, batchId: 42), usedId);
    check(
      (await reader.products(
            (await reader.findById(42))!,
            ReceiptProductType.usedVehicle,
          )).length ==
          1,
      'Used vehicle linkage missing',
    );
    // A retry after a later sale must never make that vehicle available again.
    await db
        .collection('Xe')
        .updateOne(
          {'_id': vehicle['_id']},
          {
            r'$set': {'TinhTrang': false},
          },
        );
    await repo.save(receipt, id);
    check(
      (await db.collection('Xe').findOne({
            '_id': vehicle['_id'],
          }))!['TinhTrang'] ==
          false,
      'Retry resurrected sold vehicle',
    );
    stdout.writeln(
      'PASS: batch linkage, costs, totals, unchanged finances, idempotency, interrupted stock save, used vehicles.',
    );
  } finally {
    await repo.close();
    await reader.close();
    await db.drop();
    await db.close();
  }
}
