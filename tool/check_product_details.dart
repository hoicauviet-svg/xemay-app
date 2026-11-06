import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/models/products/product_details.dart';
import 'package:xemay_app/services/mongo_product_details_repository.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  final name =
      'XM_product_details_test_${DateTime.now().microsecondsSinceEpoch}';
  final uri = 'mongodb://127.0.0.1:27017/$name';
  final db = Db(uri);
  await db.open();
  final repo = MongoProductDetailsRepository(uri: uri);
  try {
    await db.collection('Xe').insertMany([
      {
        'IdXe': 1,
        'IdSanPham': 10,
        'TenXe': 'Xe A',
        'TinhTrangXe': 'moi',
        'GiaNhap': 10000000,
        'TinhTrang': true,
        'ChiPhi': [
          {
            'Ngay': DateTime.utc(2026, 11, 4),
            'SoTien': 10000,
            'GhiChu': 'Chi phí cũ',
          },
        ],
        'TongChiPhi': 10000,
      },
      {
        'IdXe': 2,
        'IdSanPham': 10,
        'TenXe': 'Xe A',
        'TinhTrangXe': 'cu',
        'TinhTrang': false,
      },
    ]);
    await db.collection('DoiTac').insertMany([
      {'_id': 'supplier', 'TenDoiTac': 'Nhà cung cấp thử'},
      {'_id': 'seller', 'TenDoiTac': 'Người bán thử'},
    ]);
    await db.collection('XeMoi').insertOne({
      'IdXe': 1,
      'IdNhapHang': 42,
      'SoKhung': 'KHUNG-1',
    });
    await db.collection('NhapHang').insertOne({
      'IdNhapHang': 42,
      'IdDoiTac': 'supplier',
      'NgayNhap': DateTime.utc(2026, 11, 4),
      'SoTien': 20000000,
    });
    await db.collection('HoaDonBan').insertMany([
      {'IdHoaDon': 11, 'IdXe': 1},
      {'IdHoaDon': 12, 'IdXe': 2},
      {'IdHoaDon': 13, 'TrangThaiLuu': 'dang_luu'},
    ]);
    await db.collection('ChiTietHoaDonBan').insertMany([
      {
        'IdHoaDon': 11,
        'IdXe': 1,
        'IdSanPham': 10,
        'SoLuong': 1,
        'DonGia': 12000000,
      },
      {
        'IdHoaDon': 12,
        'IdXe': 2,
        'IdSanPham': 10,
        'SoLuong': 1,
        'DonGia': 13000000,
      },
      {'IdHoaDon': 13, 'IdXe': 1, 'SoLuong': 1, 'DonGia': 14000000},
    ]);
    await db.collection('HoaDonMua').insertOne({
      'IdMua': 20,
      'IdDoiTac': 'seller',
      'IdXe': 2,
      'GiaBan': 8000000,
    });
    await db.collection('ChiTietHoaDonMua').insertOne({
      'IdMua': 20,
      'IdDoiTac': 'seller',
      'IdXe': 2,
      'IdSanPham': 10,
    });
    await db.collection('SanPham').insertOne({
      'IdSanPham': 50,
      'TenSanPham': 'Nhớt',
      'LoaiSanPham': 'phu_tung',
    });
    await db.collection('ChiTietNhapHang').insertOne({
      'IdNhapHang': 42,
      'IdSanPham': 50,
      'SoLuong': 3,
      'GiaNhap': 100000,
      'ChiPhi': [
        {
          'Ngay': DateTime.utc(2026, 11, 4),
          'SoTien': 5000,
          'GhiChu': 'Vận chuyển phụ tùng',
        },
      ],
      'TongChiPhi': 5000,
    });
    final schema = await Process.run('/private/tmp/xemay-sql-env/bin/python', [
      '../upgrade_receipt_costs.py',
      '--database',
      name,
      '--apply',
    ]);
    check(schema.exitCode == 0, '${schema.stderr}');
    const vehicle = ProductReference(id: 1, vehicle: true);
    var details = await repo.load(vehicle);
    check(
      details.sales.length == 1 && details.sales.single['Ma'] == 11,
      'Vehicle histories mixed or pending sale exposed',
    );
    check(
      details.receipts.single['Ma'] == 42 &&
          details.receipts.single['SoTien'] == 10000000,
      'Legacy lot linkage wrong',
    );
    check(
      details.receipts.single['DoiTac'] == 'Nhà cung cấp thử',
      'Lot partner missing',
    );
    check(details.totalCosts == 10000, 'Existing costs lost');
    final token = ObjectId().oid;
    await repo.addCost(
      vehicle,
      date: DateTime(2026, 11, 4),
      amount: 20000,
      notes: 'Chi phí mới',
      requestId: token,
    );
    await repo.addCost(
      vehicle,
      date: DateTime(2026, 11, 4),
      amount: 20000,
      notes: 'Chi phí mới',
      requestId: token,
    );
    await Future.wait([
      for (final amount in [1000, 2000])
        repo.addCost(
          vehicle,
          date: DateTime(2026, 11, 4),
          amount: amount,
          notes: 'Đồng thời',
          requestId: ObjectId().oid,
        ),
    ]);
    details = await repo.load(vehicle);
    check(
      details.totalCosts == 33000 && details.costs.length == 4,
      'Costs duplicated or lost under concurrency',
    );
    check(
      (await db.collection('Xe').findOne({'IdXe': 1}))!['TongChiPhi'] == 33000,
      'Stored cost total incorrect',
    );
    final used = await repo.load(const ProductReference(id: 2, vehicle: true));
    check(
      used.receipts.single['Ma'] == 20 && used.costs.isEmpty,
      'Used purchase history wrong',
    );
    check(
      used.receipts.single['DoiTac'] == 'Người bán thử',
      'Purchase partner missing',
    );
    const part = ProductReference(id: 50, vehicle: false);
    await repo.addCost(
      part,
      date: DateTime(2026, 11, 4),
      amount: 7000,
      notes: 'Chi phí phụ tùng',
      requestId: ObjectId().oid,
    );
    final parts = await repo.load(part);
    check(
      parts.totalCosts == 12000 && parts.receipts.single['SoTien'] == 300000,
      'Part costs or receipts wrong',
    );
    stdout.writeln(
      'PASS: exact vehicle histories, legacy lots, pending sale exclusion, existing costs, idempotency, concurrent costs, used purchases and part costs.',
    );
  } finally {
    await repo.close();
    await db.drop();
    await db.close();
  }
}
