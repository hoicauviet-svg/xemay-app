import 'package:xemay_app/services/mongo_reports_repository.dart';
import 'package:xemay_app/models/reports/report_models.dart';
import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/services/mongo_record_maintenance.dart';
import 'package:xemay_app/services/mongo_product_details_repository.dart';
import 'package:xemay_app/models/maintenance/record_maintenance.dart';
import 'package:xemay_app/models/products/product_details.dart';

int checks = 0;
void check(bool ok, String label) {
  if (!ok) throw StateError(label);
  checks++;
  stdout.writeln('PASS: $label');
}

Future<void> main() async {
  final uri =
      'mongodb://127.0.0.1:27017/QA_RECORD_EDIT_${DateTime.now().microsecondsSinceEpoch}';
  final db = Db(uri);
  await db.open();
  final service = MongoRecordMaintenance(db, () async {});
  String token() => ObjectId().oid;
  Future<Map<String, dynamic>> get(String name, dynamic id) async =>
      (await db.collection(name).findOne({'_id': id}))!;
  Future<void> put(String name, Map<String, dynamic> row) async {
    await db.collection(name).insertOne(row);
  }

  Future<void> reject(Future<void> Function() action, String label) async {
    var failed = false;
    try {
      await action();
    } catch (_) {
      failed = true;
    }
    check(failed, label);
  }

  final date = DateTime.utc(2026, 1, 1), paidOn = DateTime.utc(2026, 2, 1);
  try {
    await put('KhachHang', {
      '_id': 'customer',
      'IdKH': 1,
      'TenKhachHang': 'Khách thử',
    });
    await put('SanPham', {
      '_id': 'catalog',
      'IdSanPham': 2,
      'TenSanPham': 'Phụ tùng thử',
    });
    await put('Xe', {
      '_id': 'vehicle',
      'IdXe': 1,
      'IdSanPham': 1,
      'TinhTrang': false,
      'IdHoaDonBan': 1,
      'GiaBan': 1000,
    });
    await put('TonKhoPhuTung', {
      '_id': 'stock',
      'IdSanPham': 2,
      'SoLuongTon': 10,
    });
    await put('HoaDonBan', {
      '_id': 'order',
      'IdHoaDon': 1,
      'IdKH': 1,
      'NgayMua': date,
      'NgayTinhLai': paidOn,
      'NgayTinhLaiGoc': date,
      'NgayHenGoc': paidOn,
      'TongTienHang': 1100,
      'TongThanhToan': 1100,
      'GiamGia': 0,
      'SoTienDaTra': 600,
      'SoTienConNo': 500,
      'PhienBanBanHang': 3,
    });
    await put('ChiTietHoaDonBan', {
      '_id': 'vline',
      'IdHoaDon': 1,
      'IdXe': 1,
      'IdSanPham': 1,
      'SoLuong': 1,
      'DonGia': 1000,
    });
    await put('ChiTietHoaDonBan', {
      '_id': 'pline',
      'IdHoaDon': 1,
      'IdSanPham': 2,
      'SoLuong': 1,
      'DonGia': 100,
    });
    await put('SoNo', {
      '_id': 'debt',
      'IdSoNo': 1,
      'IdHoaDon': 1,
      'SoTienDaTra': 600,
      'SoTienConNo': 500,
    });
    await put('TraNo', {
      '_id': 'initial',
      'IdTraNo': 1,
      'IdSoNo': 1,
      'NgayTra': date,
      'SotienTra': 500,
      'LaiThu': 0,
      'SoCoNo': 600,
    });
    final paymentId = 'order-payment-${token()}';
    final cashId = paymentId.replaceFirst('order-payment-', 'order-interest-');
    await put('TraNo', {
      '_id': paymentId,
      'IdTraNo': 2,
      'IdSoNo': 1,
      'NgayTra': paidOn,
      'SotienTra': 100,
      'LaiThu': 20,
      'SoTienLai': 20,
      'SoCoNo': 500,
    });
    await put('ThuChiKhac', {
      '_id': cashId,
      'ThuChiId': 1,
      'SoTien': 20,
      'ThuChi': true,
    });
    await service.payment(RecordKind.order, 1, paymentId, {
      ...await get('TraNo', paymentId),
      'SotienTra': 150,
      'LaiThu': 30,
      'SoTienLai': 30,
    }, requestId: token());
    check(
      (await get('SoNo', 'debt'))['SoTienConNo'] == 450 &&
          (await get('SoNo', 'debt'))['SoTienDaTra'] == 650,
      'Edit customer repayment updates debt',
    );
    check(
      (await get('TraNo', paymentId))['SoCoNo'] == 450,
      'Repayment snapshot not overwritten by stale editor value',
    );
    check(
      (await get('ThuChiKhac', cashId))['SoTien'] == 30,
      'Interest cash updated once',
    );
    await service.payment(
      RecordKind.order,
      1,
      paymentId,
      null,
      requestId: token(),
    );
    check(
      (await get('SoNo', 'debt'))['SoTienConNo'] == 600 &&
          (await get('HoaDonBan', 'order'))['SoTienDaTra'] == 500,
      'Delete repayment restores debt/header balance',
    );
    check(
      await db.collection('ThuChiKhac').findOne({'_id': cashId}) == null,
      'Delete repayment removes linked interest cash',
    );
    check(
      (await get('HoaDonBan', 'order'))['NgayTinhLai'] == date,
      'Deleting last interest payment restores interest baseline',
    );
    final edit = await service.load(RecordKind.order, 1);
    final fields = {...edit.header, 'GiamGia': 50};
    final lines = [
      for (final row in edit.lines)
        {...row, if (row['_id'] == 'pline') 'SoLuong': 2},
    ];
    await service.save(RecordKind.order, 1, fields, lines, requestId: token());
    check(
      (await get('HoaDonBan', 'order'))['TongThanhToan'] == 1150 &&
          (await get('SoNo', 'debt'))['SoTienConNo'] == 650,
      'Edit sale quantities/discount recalculates totals and debt',
    );
    check(
      (await get('TonKhoPhuTung', 'stock'))['SoLuongTon'] == 9,
      'Edit sale adjusts stock delta',
    );
    await reject(
      () => service.save(RecordKind.order, 1, fields, [
        for (final row in lines)
          {...row, if (row['_id'] == 'pline') 'SoLuong': 999},
      ], requestId: token()),
      'Stock oversell rejected',
    );
    check(
      (await get('TonKhoPhuTung', 'stock'))['SoLuongTon'] == 9,
      'Rejected edit leaves stock unchanged',
    );
    var injected = false;
    final faulty = MongoRecordMaintenance(
      db,
      () async {},
      checkpoint: (point) async {
        if (!injected) {
          injected = true;
          throw StateError('lost connection');
        }
      },
    );
    final deletion = token();
    await reject(
      () => faulty.delete(RecordKind.order, 1, requestId: deletion),
      'Deletion interruption simulated',
    );
    final beforeRead = (await get('TonKhoPhuTung', 'stock'))['SoLuongTon'];
    await reject(() async {
      await service.load(RecordKind.order, 1);
    }, 'Read does not resume pending mutations automatically');
    check(
      (await get('TonKhoPhuTung', 'stock'))['SoLuongTon'] == beforeRead &&
          (await service.pending()).length == 1,
      'Pending change remains untouched until explicit continuation',
    );
    final pendingReports = MongoReportsRepository(uri: uri);
    var reportBlocked = false;
    try {
      await pendingReports.load(ReportRange(from: date, to: paidOn));
    } on RecordChangeException {
      reportBlocked = true;
    } finally {
      await pendingReports.close();
    }
    check(
      reportBlocked,
      'Report refuses partial financial results while a change is pending',
    );
    await service.recover(RecordKind.order, 1);
    await service.delete(RecordKind.order, 1, requestId: deletion);
    check(
      await db.collection('HoaDonBan').count() == 0 &&
          await db.collection('SoNo').count() == 0 &&
          await db.collection('TraNo').count() == 0,
      'Sale deletion cascades child records',
    );
    check(
      (await get('Xe', 'vehicle'))['TinhTrang'] == true &&
          (await get('TonKhoPhuTung', 'stock'))['SoLuongTon'] == 11,
      'Recovered deletion restores stock exactly once',
    );
    await put('NhapHang', {
      '_id': 'batch',
      'IdNhapHang': 1,
      'NgayNhap': date,
      'SoLuong': 5,
      'SoTien': 1000,
      'SoTienDaTra': 300,
      'SoTienConNo': 700,
    });
    await put('ChiTietNhapHang', {
      '_id': 'incoming',
      'IdNhapHang': 1,
      'IdSanPham': 2,
      'SoLuong': 5,
      'GiaNhap': 200,
    });
    await put('TraNoNhapHang', {
      '_id': 'b0',
      'IdTraNoNhapHang': 1,
      'IdNhapHang': 1,
      'NgayTra': date,
      'SoTienTra': 200,
    });
    await put('TraNoNhapHang', {
      '_id': 'b1',
      'IdTraNoNhapHang': 2,
      'IdNhapHang': 1,
      'NgayTra': paidOn,
      'SoTienTra': 100,
    });
    await service.payment(RecordKind.batch, 1, 2, {
      'SoTienTra': 150,
      'NgayTra': paidOn,
    }, requestId: token());
    check(
      (await get('NhapHang', 'batch'))['SoTienConNo'] == 650,
      'Edit supplier repayment updates batch debt',
    );
    await service.payment(RecordKind.batch, 1, 2, null, requestId: token());
    check(
      (await get('NhapHang', 'batch'))['SoTienConNo'] == 800,
      'Delete supplier repayment restores batch debt',
    );
    final batch = await service.load(RecordKind.batch, 1);
    await service.save(
      RecordKind.batch,
      1,
      {...batch.header, 'SoTien': 900},
      batch.lines,
      requestId: token(),
    );
    check(
      (await get('NhapHang', 'batch'))['SoTienConNo'] == 700,
      'Edit batch declared total preserves payments',
    );
    await service.delete(RecordKind.batch, 1, requestId: token());
    check(
      (await get('TonKhoPhuTung', 'stock'))['SoLuongTon'] == 6 &&
          await db.collection('TraNoNhapHang').count() == 0,
      'Delete parts lot reverses incoming stock and payments',
    );
    await put('NhapHang', {
      '_id': 'soldbatch',
      'IdNhapHang': 2,
      'NgayNhap': date,
      'SoTien': 100,
      'SoTienDaTra': 0,
      'SoTienConNo': 100,
    });
    await put('Xe', {
      '_id': 'soldvehicle',
      'IdXe': 99,
      'IdNhapHang': 2,
      'TinhTrang': false,
    });
    await put('ChiTietNhapHang', {
      '_id': 'soldline',
      'IdNhapHang': 2,
      'IdXe': 99,
      'SoLuong': 1,
    });
    await reject(
      () => service.delete(RecordKind.batch, 2, requestId: token()),
      'Cannot delete lot containing a sold vehicle',
    );
    check(
      await db.collection('NhapHang').findOne({'_id': 'soldbatch'}) != null,
      'Blocked lot deletion preserves header',
    );
    await put('CamDo', {
      '_id': 'pawn',
      'IdCamDo': 1,
      'NgayVay': date,
      'SoTienVay': 1000,
      'TrangThai': true,
    });
    await put('TraNoCamDo', {
      '_id': 'pawnpay',
      'IdTraNoCamDo': 1,
      'IdCamDo': 1,
      'NgayTra': paidOn,
      'TienGoc': 1000,
      'LaiThu': 20,
      'SoTienLai': 20,
    });
    await service.payment(RecordKind.pawn, 1, 'pawnpay', {
      'TienGoc': 500,
      'NgayTra': paidOn,
    }, requestId: token());
    check(
      (await get('CamDo', 'pawn'))['TrangThai'] == false,
      'Edit settlement reopens pawn when principal remains',
    );
    await service.payment(
      RecordKind.pawn,
      1,
      'pawnpay',
      null,
      requestId: token(),
    );
    check(
      await db.collection('TraNoCamDo').count() == 0 &&
          (await get('CamDo', 'pawn'))['TrangThai'] == false,
      'Delete pawn repayment restores principal through history',
    );
    await put('VayVon', {
      '_id': 'loan',
      'IdVayVon': 1,
      'NgayVay': date,
      'NgayTinhLaiGoc': date,
      'TongConNo': 500,
    });
    await put('TraNoVayVon', {
      '_id': 'loanpay',
      'IdTraNoVayVon': 1,
      'IdVayVon': 1,
      'NgayTra': paidOn,
      'SoTienTraGoc': 500,
      'SoTienTraLai': 20,
    });
    await service.payment(RecordKind.funding, 1, 'loanpay', {
      'SoTienTraGoc': 600,
      'NgayTra': paidOn,
    }, requestId: token());
    check(
      (await get('VayVon', 'loan'))['TongConNo'] == 400,
      'Edit funding repayment updates debt',
    );
    await service.payment(
      RecordKind.funding,
      1,
      'loanpay',
      null,
      requestId: token(),
    );
    check(
      (await get('VayVon', 'loan'))['TongConNo'] == 1000 &&
          (await get('VayVon', 'loan'))['NgayTinhLai'] == date,
      'Delete funding repayment restores debt and interest baseline',
    );
    await put('NoCu', {
      '_id': 'old',
      'Id': 1,
      'NgayTinhLaiGoc': date,
      'SoCoNo': 500,
      'SoTienDaTra': 500,
    });
    await put('TraNoCu', {
      '_id': 'oldpay',
      'Id': 1,
      'IdNoCu': 1,
      'NgayTra': paidOn,
      'SoTienTra': 500,
      'TienLai': 20,
      'LaiThu': 20,
    });
    await service.payment(RecordKind.openingDebt, 1, 'oldpay', {
      'SoTienTra': 600,
      'NgayTra': paidOn,
    }, requestId: token());
    check(
      (await get('NoCu', 'old'))['SoCoNo'] == 400,
      'Edit opening debt repayment updates balance',
    );
    await service.payment(
      RecordKind.openingDebt,
      1,
      'oldpay',
      null,
      requestId: token(),
    );
    check(
      (await get('NoCu', 'old'))['SoCoNo'] == 1000 &&
          (await get('NoCu', 'old'))['SoTienDaTra'] == 0,
      'Delete opening debt repayment restores balance',
    );
    await put('Xe', {
      '_id': 'legacy-v',
      'IdXe': 77,
      'TenXe': 'Xe cũ',
      'GiaBan': 1000,
      'TinhTrang': false,
    });
    await put('HoaDonBan', {
      '_id': 'legacy-order',
      'IdHoaDon': 77,
      'IdXe': 77,
      'IdKH': 1,
      'NgayMua': date,
    });
    await put('SoNo', {
      '_id': 'legacy-debt',
      'IdHoaDon': 77,
      'IdSoNo': 77,
      'SoTienDaTra': 0,
      'SoTienConNo': 1000,
    });
    final legacy = await service.load(RecordKind.order, 77);
    await service.save(
      RecordKind.order,
      77,
      {...legacy.header, 'GiamGia': 100},
      [
        {...legacy.lines.single, 'DonGia': 1200},
      ],
      requestId: token(),
    );
    check(
      (await get('HoaDonBan', 'legacy-order'))['TongThanhToan'] == 1100 &&
          (await get('Xe', 'legacy-v'))['GiaBan'] == 1200,
      'Legacy sale without detail rows can edit actual vehicle price',
    );
    await put('TraNo', {
      '_id': 'legacy-pay',
      'IdTraNo': 77,
      'IdSoNo': 77,
      'NgayTra': paidOn,
      'SotienTra': 0,
      'LaiThu': 0,
    });
    await service.payment(
      RecordKind.order,
      77,
      'legacy-pay',
      {'NgayTra': paidOn, 'LaiThu': 10},
      interestStart: paidOn,
      requestId: token(),
    );
    check(
      await db.collection('ThuChiKhac').count({
            '_id': 'record-interest-legacy-pay',
            'SoTien': 10,
          }) ==
          1,
      'Editing legacy repayment creates deterministically linked interest cash',
    );
    await service.payment(
      RecordKind.order,
      77,
      'legacy-pay',
      null,
      interestStart: date,
      requestId: token(),
    );
    check(
      await db.collection('ThuChiKhac').count({
            '_id': 'record-interest-legacy-pay',
          }) ==
          0,
      'Deleting legacy repayment removes only its linked interest cash',
    );
    final products = MongoProductDetailsRepository(uri: uri);
    try {
      await products.archive(const ProductReference(id: 2, vehicle: false));
    } finally {
      await products.close();
    }
    check(
      (await get('SanPham', 'catalog'))['DaXoa'] == true &&
          (await get('TonKhoPhuTung', 'stock'))['SoLuongTon'] == 6,
      'Remove product from list retains source stock and historical documents',
    );
    check(
      await db.collection('_record_change_backups').count() > 0,
      'Original documents retained for audit',
    );
    for (final name in [
      'HoaDonBan',
      'SoNo',
      'Xe',
      'TonKhoPhuTung',
      'NhapHang',
      'CamDo',
      'VayVon',
      'NoCu',
    ]) {
      check(
        await db.collection(name).count({
              'SuaXoaDangLuu': {r'$exists': true},
            }) ==
            0,
        'All maintenance locks released: $name',
      );
    }
    stdout.writeln('$checks checks passed.');
  } finally {
    await db.drop();
    await db.close();
  }
}
