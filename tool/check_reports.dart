import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/models/reports/report_models.dart';
import 'package:xemay_app/services/mongo_reports_repository.dart';

void check(bool ok, String message) {
  if (!ok) throw StateError(message);
}

Future<void> main(List<String> args) async {
  if (args.contains('--live')) {
    final repo = MongoReportsRepository();
    try {
      final watch = Stopwatch()..start();
      final data = await repo.load(ReportRange());
      for (final section in data.sections.entries) {
        stdout.writeln(
          '${section.key.label}: ${section.value.rows.length} rows, ${section.value.totals}',
        );
      }
      for (final group in data.salesByGroup.entries) {
        stdout.writeln(
          'Bán ${group.key.label}: ${group.value.rows.length} đơn, doanh thu ${group.value.totals['Doanh thu']}',
        );
      }
      for (final group in data.receiptsByGroup.entries) {
        stdout.writeln(
          'Nhập ${group.key.label}: ${group.value.rows.length} lô, tiền nhập ${group.value.totals['Tiền nhập']}',
        );
      }
      stdout.writeln(
        'READ ONLY: reports loaded in ${watch.elapsedMilliseconds} ms',
      );
    } finally {
      await repo.close();
    }
    return;
  }
  final uri =
      'mongodb://127.0.0.1:27017/XM_reports_test_${DateTime.now().microsecondsSinceEpoch}';
  final db = Db(uri);
  await db.open();
  final repo = MongoReportsRepository(uri: uri);
  try {
    await db.collection('HoaDonBan').insertMany([
      {
        'IdHoaDon': 1,
        'IdXe': 1,
        'IdKH': 55,
        'NgayMua': DateTime.utc(2026, 1, 31, 23, 59),
      },
      {
        'IdHoaDon': 2,
        'NgayMua': DateTime.utc(2026, 2, 1),
        'TongTienHang': 999,
        'TongThanhToan': 999,
      },
      {
        'IdHoaDon': 3,
        'NgayMua': DateTime.utc(2026, 1, 31),
        'TongTienHang': 9999,
        'TrangThaiLuu': 'dang_luu',
      },
    ]);
    await db.collection('ChiTietHoaDonBan').insertOne({
      'IdHoaDon': 1,
      'IdXe': 1,
      'SoLuong': 1,
      'DonGiaNguon': 5000,
    });
    await db.collection('Xe').insertMany([
      {
        'IdXe': 1,
        'TenXe': 'Xe thử',
        'GiaBan': 5000,
        'GiaNhap': 3000,
        'TinhTrang': false,
        'ChiPhi': [
          {'SoTien': 120},
        ],
        'TongChiPhi': 120,
      },
      {'IdXe': 2, 'GiaNhap': 3000, 'TinhTrang': true, 'TinhTrangXe': 'moi'},
    ]);
    await db.collection('KhachHang').insertOne({
      'IdKH': 55,
      'TenKhachHang': 'Khách kiểm tra',
      'SoDienThoai': '091111',
      'DiaChiChiTiet': 'Địa chỉ thử',
    });
    await db.collection('SoNo').insertOne({
      'IdSoNo': 1,
      'IdHoaDon': 1,
      'SoTienDaTra': 4000,
      'SoTienConNo': 1000,
    });
    await db.collection('ThuChiKhac').insertMany([
      {
        'ThuChiId': 12345,
        'LyDo': 'Thu kiểm tra',
        'NgayThang': DateTime.utc(2026, 1, 31, 23, 59),
        'ThuChi': true,
        'SoTien': 100,
      },
      {'NgayThang': DateTime.utc(2026, 2, 1), 'ThuChi': false, 'SoTien': 999},
    ]);
    await db.collection('CamDo').insertOne({
      'IdCamDo': 1,
      'NgayVay': DateTime.utc(2025, 1, 1),
      'SoTienVay': 1000,
      'TrangThai': false,
    });
    await db.collection('TraNoCamDo').insertOne({
      'IdTraNoCamDo': 678,
      'IdCamDo': 1,
      'NgayTra': DateTime.utc(2025, 2, 1),
      'TienGoc': 200,
      'LaiThu': 10,
    });
    await db.collection('DoiTac').insertOne({
      '_id': 'partner-1',
      'TenDoiTac': 'Đối tác thử',
      'SoDienThoai': '092222',
      'DiaChi': 'Địa chỉ đối tác',
    });
    await db.collection('VanChuyen').insertOne({
      '_id': 'carrier-1',
      'TenVanChuyen': 'Vận chuyển thử',
    });
    await db.collection('NhapHang').insertOne({
      'IdNhapHang': 9,
      'NgayNhap': DateTime.utc(2026, 1, 31),
      'IdDoiTac': 'partner-1',
      'IdVanChuyen': 'carrier-1',
      'SoLuong': 1,
      'SoTien': 100,
      'SoTienDaTra': 60,
      'SoTienConNo': 40,
    });
    await db.collection('NoCu').insertOne({
      'Id': 3,
      'IdKH': '55',
      'TongNo': 200,
      'SoTienDaTra': 200,
      'SoCoNo': 0,
    });
    await db.collection('VayVon').insertOne({
      'IdVayVon': 4,
      'DoiTac': 'Người cho vay thử',
      'TongConNo': 0,
    });
    final repaymentDate = DateTime.utc(2026, 1, 31, 23, 59);
    await db.collection('TraNo').insertMany([
      {
        'IdTraNo': 10,
        'IdSoNo': 1,
        'NgayTra': repaymentDate,
        'SotienTra': 100,
        'LaiThu': 10,
        'SoCoNo': 1000,
      },
      {
        'IdTraNo': 11,
        'IdSoNo': 1,
        'NgayTra': DateTime.utc(2026, 2, 1),
        'SotienTra': 999,
        'LaiThu': 999,
      },
    ]);
    await db.collection('TraNoNhapHang').insertOne({
      'IdTraNoNhapHang': 20,
      'IdNhapHang': 9,
      'NgayTra': repaymentDate,
      'SoTienTra': 60,
      'SoCoNo': 40,
    });
    await db.collection('TraNoCu').insertOne({
      'Id': 30,
      'IdNoCu': 3,
      'NgayTra': repaymentDate,
      'SoTienTra': 200,
      'LaiThu': 20,
      'ConNo': 0,
    });
    await db.collection('TraNoVayVon').insertOne({
      'IdTraNoVayVon': 40,
      'IdVayVon': 4,
      'NgayTra': repaymentDate,
      'SoTienTraGoc': 300,
      'SoTienTraLai': 30,
      'ConNoGoc': 0,
    });
    final data = await repo.load(
      ReportRange(from: DateTime(2026, 1, 31), to: DateTime(2026, 1, 31)),
    );
    check(
      data.sections[ReportKind.sales]!.totals['Doanh thu'] == 5000,
      'Legacy revenue or date filter',
    );
    check(
      !data.sections[ReportKind.cash]!.totals.containsKey('Chênh lệch'),
      'Cash end day',
    );
    check(
      data.sections[ReportKind.cash]!.rows.single[0] == 12345 &&
          data.sections[ReportKind.cash]!.rows.single[3] == 'Thu kiểm tra',
      'Cash voucher code and reason projection',
    );
    check(
      data.sections[ReportKind.sales]!.rows.single[2] == 'Khách kiểm tra' &&
          data.sections[ReportKind.sales]!.rows.single[3] == 'Xe thử × 1',
      'Sales customer and vehicle name projections',
    );
    check(
      data.sections[ReportKind.sales]!.totals['Chi phí'] == 120 &&
          data.sections[ReportKind.sales]!.rows.single[data
                  .sections[ReportKind.sales]!
                  .columns
                  .indexWhere((c) => c.label == 'Chi phí')] ==
              120,
      'Vehicle expense projection',
    );
    check(
      data.sections[ReportKind.sales]!.totals['Giá nhập'] == 3000 &&
          data.sections[ReportKind.sales]!.totals['Lợi nhuận'] == 1880,
      'Purchase cost and profit projection',
    );
    final receipt = data.sections[ReportKind.receipts]!;
    check(
      receipt.rows.single[2] == 'Đối tác thử' &&
          receipt.rows.single[3] == 'Vận chuyển thử',
      'Receipt partner/carrier projections',
    );
    check(
      !receipt.columns.any((c) => c.label == 'Chênh lệch'),
      'Difference column still present',
    );
    check(
      data.sections[ReportKind.customerDebt]!.rows.single[3] == '091111' &&
          data.sections[ReportKind.customerDebt]!.totals['Còn nợ'] == 1000,
      'Customer debt contact projection',
    );
    check(
      data.sections[ReportKind.supplierDebt]!.rows.single[3] == '092222' &&
          data.sections[ReportKind.supplierDebt]!.totals['Còn nợ'] == 40,
      'Supplier debt contact projection',
    );
    check(
      data.sections[ReportKind.customerRepayments]!.rows.length == 1 &&
          data.sections[ReportKind.customerRepayments]!.totals['Tiền trả nợ'] ==
              100,
      'Customer repayments or end-day filter',
    );
    check(
      data.sections[ReportKind.supplierRepayments]!.totals['Số tiền trả'] == 60,
      'Supplier payment projection',
    );
    check(
      data.sections[ReportKind.oldDebtRepayments]!.rows.single[3] ==
              'Khách kiểm tra' &&
          data.sections[ReportKind.oldDebtRepayments]!.totals['Lãi thực thu'] ==
              20,
      'Old debt payment join',
    );
    check(
      data.sections[ReportKind.fundingRepayments]!.rows.single[3] ==
              'Người cho vay thử' &&
          data.sections[ReportKind.fundingRepayments]!.totals['Trả lãi'] == 30,
      'Funding payment join',
    );
    final all = await repo.load(ReportRange());
    check(
      all.sections[ReportKind.pawnCollections]!.rows.any(
        (r) => r[0] == 678 && r[2] == 1,
      ),
      'Pawn payment code projection',
    );
    check(
      data.sections[ReportKind.stock]!.totals['Xe mới'] == 1,
      'Current inventory',
    );
    check(
      data.sections[ReportKind.pawnDebt]!.totals['Còn nợ'] == 800,
      'Pawn principal must include historical repayments',
    );
    check(
      data.sections[ReportKind.pawn]!.totals['Phiếu mới'] == 0,
      'Period must not include old pawn issue',
    );
    check(
      await db.collection('HoaDonBan').count() == 3 &&
          await db.collection('TraNoCamDo').count() == 1,
      'Reports changed source',
    );
    await db.collection('NhapHang').insertOne({
      'IdNhapHang': 9001,
      'NgayNhap': DateTime.utc(2026, 1, 31),
      'LoaiSanPham': 'phu_tung',
      'SoLuong': 2,
      'SoTien': 200,
      'SoTienDaTra': 200,
      'SoTienConNo': 0,
    });
    final grouped = await repo.load(ReportRange());
    check(
      grouped.receiptsByGroup[ReportProductGroup.parts]!.totals['Tiền nhập'] ==
          200,
      'Receipt category projection missing',
    );
    check(
      grouped.receiptsByGroup[ReportProductGroup.parts]!.rows.single[0] == 9001,
      'Receipt category contains another group',
    );
    stdout.writeln(
      'PASS: Mongo report projections, legacy prices, date boundaries, current balances and read-only loading.',
    );
  } finally {
    await repo.close();
    await db.drop();
    await db.close();
  }
}
