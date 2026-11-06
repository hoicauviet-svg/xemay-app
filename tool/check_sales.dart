import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/models/sales/sale_models.dart';
import 'package:xemay_app/services/mongo_sales_repository.dart';
import 'package:xemay_app/services/mongo_customer_repository.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

SaleLine vehicle(int id) => SaleLine(
  kind: 'xe',
  name: 'Xe $id',
  quantity: 1,
  price: 1000000,
  productId: 10,
  vehicleId: id,
);
SaleLine get part => const SaleLine(
  kind: 'phu_tung',
  name: 'Phụ tùng',
  quantity: 2,
  price: 100000,
  productId: 20,
);
const service = SaleLine(
  kind: 'dich_vu',
  name: 'Vá săm',
  quantity: 1,
  price: 50000,
  serviceId: 'svc-1',
);
SaleDraft draft(List<SaleLine> lines, {int discount = 0, int paid = 2000000}) =>
    SaleDraft(
      lines: lines,
      date: DateTime(2026, 11, 4),
      discount: discount,
      paid: paid,
      customerId: 1,
    );
Future<void> main() async {
  final name = 'XM_sales_test_${DateTime.now().microsecondsSinceEpoch}';
  final uri = 'mongodb://127.0.0.1:27017/$name';
  final db = Db(uri);
  final repository = MongoSalesRepository(uri: uri);
  final readers = MongoCustomerRepository(uri: uri);
  final extra = <MongoSalesRepository>[];
  try {
    await db.open();
    await db.collection('HoaDonBan').insertOne({
      '_id': 500,
      'IdHoaDon': 500,
      'IdKH': 1,
      'NgayMua': DateTime.utc(2020, 1, 1),
    });
    final root = File.fromUri(Platform.script).parent.parent.parent.path;
    final backup = await Directory.systemTemp.createTemp('xm-sales-write-');
    final migration = await Process.run('/private/tmp/xemay-sql-env/bin/python', [
      '-c',
      'from upgrade_sales_schema import upgrade; import sys; upgrade(sys.argv[1], True, sys.argv[2])',
      name,
      backup.path,
    ], workingDirectory: root);
    check(migration.exitCode == 0, 'Migration failed: ${migration.stderr}');
    await db.collection('KhachHang').insertOne({
      'IdKH': 1,
      'TenKhachHang': 'Khách kiểm thử',
    });
    await db.collection('SanPham').insertMany([
      {'IdSanPham': 10, 'TenSanPham': 'Xe', 'LoaiSanPham': 'xe'},
      {'IdSanPham': 20, 'TenSanPham': 'Phụ tùng', 'LoaiSanPham': 'phu_tung'},
    ]);
    for (final id in [100, 101, 102, 103, 104, 105]) {
      await db.collection('Xe').insertOne({
        'IdXe': id,
        'IdSanPham': 10,
        'TinhTrang': true,
        'GiaBan': 999999,
      });
    }
    await db.collection('TonKhoPhuTung').insertOne({
      'IdSanPham': 20,
      'SoLuongTon': 5,
    });
    await db.collection('DichVu').insertOne({
      '_id': 'svc-1',
      'TenDichVu': 'Vá săm',
      'MoTa': '',
      'GiaTien': 50000,
    });
    final mixed = draft(
      [vehicle(100), part, service],
      discount: 50000,
      paid: 1500000,
    );
    final key = ObjectId().oid;
    final result = await repository.save(mixed, key);
    check(
      result.invoiceId == 501,
      'Invoice counter does not follow legacy IDs',
    );
    final header = await db.collection('HoaDonBan').findOne({
      'IdHoaDon': result.invoiceId,
    });
    check(
      header?['GiamGia'] == 50000 &&
          header?['TongThanhToan'] == 1200000 &&
          header?['SoTienDaTra'] == 1200000 &&
          header?['TienThua'] == 300000 &&
          header?['TrangThaiLuu'] == 'da_luu',
      'Header totals mismatch',
    );
    check(
      await db.collection('ChiTietHoaDonBan').count({
            'IdHoaDon': result.invoiceId,
          }) ==
          3,
      'Missing invoice lines',
    );
    check(
      (await db.collection('Xe').findOne({'IdXe': 100}))?['TinhTrang'] == false,
      'Vehicle not sold',
    );
    check(
      (await db.collection('TonKhoPhuTung').findOne({
            'IdSanPham': 20,
          }))?['SoLuongTon'] ==
          3,
      'Part stock not deducted',
    );
    final debt = await db.collection('SoNo').findOne({
      'IdHoaDon': result.invoiceId,
    });
    final payment = await db.collection('TraNo').findOne({
      'IdSoNo': debt!['IdSoNo'],
    });
    check(
      debt['SoTienConNo'] == 0 && payment?['SotienTra'] == 1200000,
      'Change counted as revenue/debt',
    );
    check(
      (await repository.save(mixed, key)).invoiceId == result.invoiceId,
      'Repeat did not return same invoice',
    );
    check(
      await db.collection('HoaDonBan').count({'MaYeuCauLuu': key}) == 1 &&
          (await db.collection('TonKhoPhuTung').findOne({
                'IdSanPham': 20,
              }))?['SoLuongTon'] ==
              3,
      'Repeat created duplicate or deducted twice',
    );
    final customerOrders = await readers.orders(1);
    check(
      customerOrders.rows.first['TongTien'] == 1200000 &&
          customerOrders.rows.first['SanPhamHienThi'].toString().contains(
            'Vá săm',
          ),
      'Customer history misses service or discount',
    );
    // A domain error after an earlier reservation must release the earlier hold.
    var rejected = false;
    try {
      await repository.save(
        draft([
          vehicle(102),
          const SaleLine(
            kind: 'dich_vu',
            name: 'Missing',
            quantity: 1,
            price: 1,
            serviceId: 'missing',
          ),
        ]),
        ObjectId().oid,
      );
    } on SaleSaveException catch (e) {
      rejected = !e.uncertain;
    }
    check(
      rejected &&
          (await db.collection('Xe').findOne({
                'IdXe': 102,
              }))?['GiuChoBanHang'] ==
              null,
      'Failed order leaked vehicle reservation',
    );
    var insufficient = false;
    try {
      await repository.save(
        draft([
          vehicle(102),
          const SaleLine(
            kind: 'phu_tung',
            name: 'Phụ tùng',
            quantity: 999,
            price: 1000,
            productId: 20,
          ),
        ]),
        ObjectId().oid,
      );
    } on SaleSaveException catch (e) {
      insufficient = !e.uncertain;
    }
    check(
      insufficient &&
          (await db.collection('Xe').findOne({
                'IdXe': 102,
              }))?['GiuChoBanHang'] ==
              null &&
          (await db.collection('TonKhoPhuTung').findOne({
                'IdSanPham': 20,
              }))?['SoLuongTon'] ==
              3,
      'Insufficient stock did not roll back earlier hold',
    );
    // Two independent orders competing for a vehicle cannot both sell it.
    final competitor = MongoSalesRepository(uri: uri);
    extra.add(competitor);
    final race = await Future.wait([
      repository
          .save(draft([vehicle(101)]), ObjectId().oid)
          .then<Object>((r) => r)
          .catchError((Object e) => e),
      competitor
          .save(draft([vehicle(101)]), ObjectId().oid)
          .then<Object>((r) => r)
          .catchError((Object e) => e),
    ]);
    check(
      race.whereType<SaleSaveResult>().length == 1 &&
          race.whereType<SaleSaveException>().length == 1,
      'Same vehicle sold twice',
    );
    // Crash after header creation: hide incomplete order, then roll forward once.
    var fail = true;
    final interrupted = MongoSalesRepository(
      uri: uri,
      checkpoint: (point) async {
        if (fail && point == 'afterHeader') {
          fail = false;
          throw StateError('simulated process loss');
        }
      },
    );
    extra.add(interrupted);
    final interruptedKey = ObjectId().oid;
    final interruptedDraft = draft([
      vehicle(103),
      const SaleLine(
        kind: 'phu_tung',
        name: 'Phụ tùng',
        quantity: 1,
        price: 100000,
        productId: 20,
      ),
    ]);
    try {
      await interrupted.save(interruptedDraft, interruptedKey);
    } on SaleSaveException catch (e) {
      check(e.uncertain, 'Unknown outcome treated as rejection');
    }
    final pending = await db.collection('GiaoDichBanHang').findOne({
      '_id': interruptedKey,
    });
    check(
      !(await readers.orders(
        1,
      )).rows.any((r) => r['IdHoaDon'] == pending!['IdHoaDon']),
      'Incomplete order exposed in customer history',
    );
    await db
        .collection('GiaoDichBanHang')
        .updateOne(
          {'_id': interruptedKey},
          {
            r'$set': {'KhoaDen': DateTime.utc(2000)},
          },
        );
    final recovered = await repository.recoverPending();
    check(
      recovered.any((r) => r.invoiceId == pending!['IdHoaDon']),
      'Recovery did not complete order',
    );
    check(
      (await db.collection('TonKhoPhuTung').findOne({
            'IdSanPham': 20,
          }))?['SoLuongTon'] ==
          2,
      'Recovery deducted part twice',
    );
    check(
      (await repository.save(interruptedDraft, interruptedKey)).invoiceId ==
          pending!['IdHoaDon'],
      'Recovered retry duplicated invoice',
    );
    // Lost success response: retry acknowledges committed order, no duplicate.
    var loseAck = true;
    final ack = MongoSalesRepository(
      uri: uri,
      checkpoint: (point) async {
        if (loseAck && point == 'afterComplete') {
          loseAck = false;
          throw StateError('lost ack');
        }
      },
    );
    extra.add(ack);
    final ackKey = ObjectId().oid;
    try {
      await ack.save(draft([vehicle(104)]), ackKey);
    } on SaleSaveException catch (e) {
      check(e.uncertain, 'Lost ack is not retryable');
    }
    final ackResult = await ack.save(draft([vehicle(104)]), ackKey);
    check(
      await db.collection('HoaDonBan').count({
            'IdHoaDon': ackResult.invoiceId,
          }) ==
          1,
      'Lost ack created duplicate',
    );
    // Crash during reservation (before any header exists) must not deduct twice.
    var loseReservationAck = true;
    final beforeHeader = MongoSalesRepository(
      uri: uri,
      checkpoint: (point) async {
        if (loseReservationAck && point == 'afterReserve') {
          loseReservationAck = false;
          throw StateError('reservation interruption');
        }
      },
    );
    extra.add(beforeHeader);
    final reservationKey = ObjectId().oid;
    final reservedDraft = draft([
      const SaleLine(
        kind: 'phu_tung',
        name: 'Phụ tùng',
        quantity: 1,
        price: 100000,
        productId: 20,
      ),
      vehicle(105),
    ]);
    try {
      await beforeHeader.save(reservedDraft, reservationKey);
    } on SaleSaveException catch (e) {
      check(e.uncertain, 'Reservation interruption was treated as rejection');
    }
    await db
        .collection('GiaoDichBanHang')
        .updateOne(
          {'_id': reservationKey},
          {
            r'$set': {'KhoaDen': DateTime.utc(2000)},
          },
        );
    await repository.recoverPending();
    check(
      (await db.collection('TonKhoPhuTung').findOne({
            'IdSanPham': 20,
          }))?['SoLuongTon'] ==
          1,
      'Reservation recovery double-deducted stock',
    );
    check(
      (await db.collection('GiaoDichBanHang').findOne({
            '_id': reservationKey,
          }))?['TrangThai'] ==
          'hoan_tat',
      'Reservation recovery not complete',
    );
    // Credit schedules survive durable-journal recovery exactly as selected.
    var interruptCredit = true;
    final creditWriter = MongoSalesRepository(
      uri: uri,
      checkpoint: (point) async {
        if (interruptCredit && point == 'afterHeader') {
          interruptCredit = false;
          throw StateError('credit interruption');
        }
      },
    );
    extra.add(creditWriter);
    final creditKey = ObjectId().oid;
    final credit = SaleDraft(
      lines: [service],
      date: DateTime(2026, 11, 4),
      discount: 0,
      paid: 10000,
      customerId: 1,
      paymentDueDate: DateTime(2026, 11, 30),
      interestDate: DateTime(2026, 11, 5),
    );
    try {
      await creditWriter.save(credit, creditKey);
    } on SaleSaveException catch (e) {
      check(e.uncertain, 'Interrupted credit did not retain request');
    }
    await db
        .collection('GiaoDichBanHang')
        .updateOne(
          {'_id': creditKey},
          {
            r'$set': {'KhoaDen': DateTime.utc(2000)},
          },
        );
    await repository.recoverPending();
    final creditHeader = await db.collection('HoaDonBan').findOne({
      'MaYeuCauLuu': creditKey,
    });
    check(
      creditHeader?['NgayHen'] == DateTime.utc(2026, 11, 30) &&
          creditHeader?['NgayTinhLai'] == DateTime.utc(2026, 11, 5) &&
          creditHeader?['SoTienConNo'] == 40000 &&
          creditHeader?['TrangThaiLuu'] == 'da_luu',
      'Credit dates or balance lost on recovery',
    );
    final creditJournal = await db.collection('GiaoDichBanHang').findOne({
      '_id': creditKey,
    });
    check(
      (creditJournal?['Payload'] as Map)['NgayHen'] == '2026-11-30',
      'Credit date missing from immutable payload',
    );
    var missingDatesRejected = false;
    try {
      await repository.save(
        SaleDraft(
          lines: [service],
          date: DateTime(2026, 11, 4),
          discount: 0,
          paid: 10000,
          customerId: 1,
        ),
        ObjectId().oid,
      );
    } on SaleSaveException catch (e) {
      missingDatesRejected = !e.uncertain;
    }
    check(missingDatesRejected, 'Credit saved without required dates');
    var anonymousRejected = false;
    try {
      await repository.save(
        SaleDraft(lines: [service], date: DateTime.now(), discount: 0, paid: 0),
        ObjectId().oid,
      );
    } on SaleSaveException catch (e) {
      anonymousRejected = !e.uncertain;
    }
    check(anonymousRejected, 'Unidentified customer debt accepted');
    stdout.writeln(
      'PASS: mixed vehicle/part/service sale, discount, exact collection/change, stock, duplicate retry, customer history, rollback, concurrent vehicle sale, interrupted-save recovery and lost-ack retry. All writes isolated.',
    );
  } finally {
    await repository.close();
    await readers.close();
    for (final r in extra) {
      await r.close();
    }
    if (!db.isConnected) await db.open();
    await db.drop();
    await db.close();
  }
}
