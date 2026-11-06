import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/models/orders/order_details.dart';
import 'package:xemay_app/services/mongo_order_repository.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  final name = 'XM_order_test_${DateTime.now().microsecondsSinceEpoch}';
  final uri = 'mongodb://127.0.0.1:27017/$name';
  final db = Db(uri);
  await db.open();
  final repo = MongoOrderRepository(uri: uri);
  try {
    await db.collection('HoaDonBan').insertMany([
      {
        'IdHoaDon': 42,
        'IdKH': 1,
        'NgayMua': DateTime.utc(2026, 11, 1),
        'TongThanhToan': 200000,
        'GiamGia': 10000,
        'SoTienDaTra': 50000,
        'SoTienConNo': 150000,
      },
      {'IdHoaDon': 43, 'IdKH': 1, 'NgayMua': DateTime.utc(2026, 11, 1)},
      {'IdHoaDon': 44, 'IdKH': 1, 'NgayMua': DateTime.utc(2026, 11, 1)},
    ]);
    await db.collection('KhachHang').insertOne({
      'IdKH': 1,
      'TenKhachHang': 'Khách thử',
    });
    await db.collection('SanPham').insertOne({
      'IdSanPham': 10,
      'TenSanPham': 'Tên danh mục',
    });
    await db.collection('XeMoi').insertOne({'IdXe': 7, 'SoKhung': 'KHUNG-7'});
    await db.collection('ChiTietHoaDonBan').insertMany([
      {
        'IdHoaDon': 42,
        'IdSanPham': 10,
        'IdXe': 7,
        'SoLuong': 1,
        'DonGia': 200000,
      },
      {
        'IdHoaDon': 42,
        'LoaiSanPham': 'dich_vu',
        'TenSanPham': 'Vá săm',
        'SoLuong': 1,
        'DonGia': 10000,
      },
      {
        'IdHoaDon': 43,
        'IdSanPham': 10,
        'SoLuong': 1,
        'DonGia': null,
        'DonGiaNguon': 999999,
        'NguonChuyenDoi': 'product_schema_v2',
        'NguonDonGia': 'Xe.GiaBan',
      },
    ]);
    await db.collection('SoNo').insertMany([
      {
        'IdSoNo': 1,
        'IdHoaDon': 42,
        'SoTienDaTra': 50000,
        'SoTienConNo': 150000,
      },
      {'IdSoNo': 2, 'IdHoaDon': 43, 'SoTienDaTra': 0, 'SoTienConNo': 50000},
      {'IdSoNo': 3, 'IdHoaDon': 44, 'SoTienDaTra': 0, 'SoTienConNo': 50000},
      {'IdSoNo': 4, 'IdHoaDon': 44, 'SoTienDaTra': 0, 'SoTienConNo': 50000},
    ]);
    await db.collection('TraNo').insertOne({
      'IdTraNo': 1,
      'IdSoNo': 1,
      'SotienTra': 50000,
      'NgayTra': DateTime.utc(2026, 11, 1),
      'SoCoNo': 150000,
    });
    await db.collection('_app_counters').insertOne({
      '_id': 'TraNo',
      'value': 100,
    });
    var detail = await repo.load(42);
    check(
      detail.total == 200000 &&
          detail.lines.length == 2 &&
          detail.customer?['TenKhachHang'] == 'Khách thử',
      'Order details incorrect',
    );
    check(
      detail.lines.any((l) => l['SoKhung'] == 'KHUNG-7') &&
          detail.lines.any((l) => l['TenSanPham'] == 'Vá săm'),
      'Product identity or service snapshot missing',
    );

    // Old invoices without price snapshots or even migrated lines use their linked vehicle.
    await db.collection('Xe').insertOne({
      'IdXe': 99,
      'IdSanPham': 10,
      'TenXe': 'Xe cũ thiếu giá chi tiết',
      'GiaBan': 25000000,
    });
    await db.collection('HoaDonBan').insertMany([
      {'IdHoaDon': 15197, 'IdXe': 99, 'IdKH': 1},
      {'IdHoaDon': 15198, 'IdXe': 99, 'IdKH': 1},
      {'IdHoaDon': 15199, 'IdXe': 99, 'IdKH': 1, 'PhienBanBanHang': 3},
    ]);
    await db.collection('ChiTietHoaDonBan').insertMany([
      {'IdHoaDon': 15198, 'IdXe': 99, 'SoLuong': 1, 'DonGia': null},
      {'IdHoaDon': 15199, 'IdXe': 99, 'SoLuong': 1, 'DonGia': null},
    ]);
    for (final id in [15197, 15198]) {
      final legacy = await repo.load(id);
      check(
        legacy.goodsTotal == 25000000 &&
            legacy.discount == 0 &&
            legacy.total == 25000000,
        'Legacy invoice lost vehicle sale price',
      );
    }
    check(
      (await repo.load(15199)).goodsTotal == null,
      'Modern invoice price silently replaced',
    );
    final token = ObjectId().oid;
    await repo.pay(
      42,
      date: DateTime(2026, 11, 4),
      amount: 40000,
      notes: 'Thu tiền',
      requestId: token,
    );
    await repo.pay(
      42,
      date: DateTime(2026, 11, 4),
      amount: 40000,
      notes: 'Thu tiền',
      requestId: token,
    );
    detail = await repo.load(42);
    check(
      detail.due == 110000 &&
          detail.paid == 90000 &&
          detail.payments.length == 2,
      'Payment duplicate or balance wrong',
    );
    check(
      detail.payments.any((p) => p['IdTraNo'] == 101),
      'Did not share sale payment counter',
    );
    bool rejected = false;
    try {
      await repo.pay(
        42,
        date: DateTime(2026, 11, 4),
        amount: 110001,
        notes: '',
        requestId: ObjectId().oid,
      );
    } on OrderException {
      rejected = true;
    }
    check(rejected, 'Overpayment accepted');
    bool fail = true;
    final interrupted = MongoOrderRepository(
      uri: uri,
      checkpoint: (point) async {
        if (fail && point == 'afterDebt') {
          fail = false;
          throw StateError('Interrupted');
        }
      },
    );
    final retry = ObjectId().oid;
    try {
      await interrupted.pay(
        42,
        date: DateTime(2026, 11, 4),
        amount: 10000,
        notes: 'Khôi phục',
        requestId: retry,
      );
    } catch (_) {}
    detail = await repo.load(42);
    check(
      detail.due == 100000 && detail.payments.length == 3,
      'Interrupted payment not recovered',
    );
    await interrupted.pay(
      42,
      date: DateTime(2026, 11, 4),
      amount: 10000,
      notes: 'Khôi phục',
      requestId: retry,
    );
    await interrupted.close();
    final other = MongoOrderRepository(uri: uri);
    final outcomes = await Future.wait(
      [repo, other].map((r) async {
        try {
          await r.pay(
            42,
            date: DateTime(2026, 11, 4),
            amount: 70000,
            notes: 'Đồng thời',
            requestId: ObjectId().oid,
          );
          return true;
        } on OrderException {
          return false;
        }
      }),
    );
    check(
      outcomes.where((v) => v).length == 1,
      'Concurrent overpayment succeeded',
    );
    await other.close();
    detail = await repo.load(42);
    check(
      detail.due == 30000 && detail.paid == 170000,
      'Concurrent totals wrong',
    );
    await repo.pay(
      42,
      date: DateTime(2026, 11, 4),
      amount: 30000,
      notes: 'Trả đủ',
      requestId: ObjectId().oid,
    );
    detail = await repo.load(42);
    check(
      detail.due == 0 &&
          !detail.canPay &&
          detail.header['SoTienDaTra'] == 200000 &&
          detail.header['GiamGia'] == 10000,
      'Final balance/header sync wrong',
    );
    check(
      (await repo.load(43)).total == 999999,
      'Legacy original sale price not displayed',
    );
    check(!(await repo.load(44)).canPay, 'Ambiguous debt permitted payment');
    await db.collection('HoaDonBan').insertOne({
      'IdHoaDon': 45,
      'IdKH': 1,
      'NgayMua': DateTime.utc(2026, 1, 1),
      'NgayTinhLai': DateTime.utc(2026, 1, 1),
      'NgayHen': DateTime.utc(2026, 1, 1),
      'MaYeuCauLuu': 'interest-test',
      'TrangThaiLuu': 'da_luu',
      'PhienBanBanHang': 3,
      'TongTienHang': 1000000,
      'GiamGia': 0,
      'TongThanhToan': 1000000,
      'SoTienKhachDua': 0,
      'TienThua': 0,
      'SoTienDaTra': 0,
      'SoTienConNo': 1000000,
    });
    final live = Db('mongodb://127.0.0.1:27017/XM');
    await live.open();
    try {
      final info = await live.runCommand({
        'listCollections': 1,
        'filter': {'name': 'HoaDonBan'},
      });
      final validator =
          (info['cursor']['firstBatch'] as List).single['options']['validator'];
      // Apply the real validation rules to this isolated database only.
      await db.runCommand({
        'collMod': 'HoaDonBan',
        'validator': validator,
        'validationLevel': 'strict',
        'validationAction': 'error',
      });
    } finally {
      await live.close();
    }
    await db.collection('SoNo').insertOne({
      'IdSoNo': 5,
      'IdHoaDon': 45,
      'SoTienDaTra': 0.0,
      'SoTienConNo': 1000000.0,
    });
    var interruptInterest = true;
    final interestRepo = MongoOrderRepository(
      uri: uri,
      today: () => DateTime(2026, 1, 31),
      checkpoint: (point) async {
        if (point == 'afterInterest' && interruptInterest) {
          interruptInterest = false;
          throw StateError('Interrupted after income');
        }
      },
    );
    final interestToken = ObjectId().oid;
    try {
      try {
        await interestRepo.pay(
          45,
          date: DateTime(2026, 1, 31),
          amount: 0,
          notes: 'Thu lãi',
          requestId: interestToken,
        );
      } on StateError catch (_) {}
      await repo.load(45);
      await interestRepo.pay(
        45,
        date: DateTime(2026, 1, 31),
        amount: 0,
        notes: 'Thu lãi',
        requestId: interestToken,
      );
      final income = await db.collection('ThuChiKhac').find({
        'IdHoaDon': 45,
      }).toList();
      final after = await repo.load(45);
      check(
        income.length == 1 &&
            income.single['SoTien'] == 20000 &&
            income.single['ThuChi'] == true &&
            income.single['LyDo'] ==
                'Thu tiền lãi của khách hàng Khách thử mã đơn hàng 45',
        'Interest income missing or duplicated',
      );
      check(
        after.due == 1000000 &&
            after.payments.single['LaiThu'] == 20000 &&
            after.header['NgayTinhLai'] == DateTime.utc(2026, 1, 31) &&
            after.header['NgayHen'] == DateTime.utc(2026, 2, 28) &&
            after.interestAt(DateTime(2026, 3, 2)) == 20000,
        'Interest-only payment changed principal or did not reset anchor',
      );
      await interestRepo.pay(
        45,
        date: DateTime(2026, 3, 2),
        amount: 1000000,
        notes: 'Trả đủ',
        nextAppointment: DateTime(2026, 3, 15),
        requestId: ObjectId().oid,
      );
      final settled = await repo.load(45);
      check(
        settled.due == 0 &&
            settled.header['SoTienDaTra'] == 1000000 &&
            settled.header['NgayHen'] == DateTime.utc(2026, 3, 15) &&
            await db.collection('ThuChiKhac').count({'IdHoaDon': 45}) == 2,
        'Settlement or second interest income failed',
      );
    } finally {
      await interestRepo.close();
    }
    stdout.writeln(
      'PASS: order/customer/vehicle/service details, exact debt history, partial/full payment, shared counters, retry, crash recovery and concurrent overpayment protection.',
    );
  } finally {
    await repo.close();
    await db.drop();
    await db.close();
  }
}
