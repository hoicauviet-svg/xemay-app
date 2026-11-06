import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/services/mongo_partner_repository.dart';

void check(bool result, String message) {
  if (!result) throw StateError(message);
}

Future<void> main() async {
  final uri =
      'mongodb://127.0.0.1:27017/XM_partner_test_${DateTime.now().microsecondsSinceEpoch}';
  final db = Db(uri);
  final repo = MongoPartnerRepository(uri: uri);
  await db.open();
  try {
    await db.collection('DoiTac').insertMany([
      {
        '_id': 'p1',
        'TenDoiTac': 'Z đối tác cũ',
        'NgayTao': DateTime.utc(2026, 11, 1),
      },
      {
        '_id': 'p2',
        'TenDoiTac': 'A đối tác mới',
        'NgayTao': DateTime.utc(2026, 11, 4),
      },
    ]);
    check(
      (await repo.fetchPartners()).rows.first['_id'] == 'p2',
      'Partners not newest first',
    );
    await db.collection('NhapHang').insertMany([
      {
        'IdNhapHang': 44,
        'IdDoiTac': 'p1',
        'NgayNhap': DateTime.utc(2026, 11, 1),
        'SoLuong': 1,
        'SoTien': 500000,
      },
      {
        'IdNhapHang': 45,
        'IdDoiTac': 'p1',
        'NgayNhap': DateTime.utc(2026, 11, 4),
        'SoLuong': 2,
        'SoTien': 1000000,
      },
      {
        'IdNhapHang': 46,
        'IdDoiTac': 'p2',
        'NgayNhap': DateTime.utc(2026, 11, 4),
      },
    ]);
    await db.collection('HoaDonMua').insertOne({
      'IdMua': 99,
      'IdDoiTac': 'p1',
      'NgayBan': DateTime.utc(2026, 10, 29),
      'GiaBan': 700000,
      'IdXe': 7,
    });
    await db.collection('XeMoi').insertOne({'IdNhapHang': 44, 'IdXe': 7});
    await db.collection('Xe').insertOne({'IdXe': 7, 'TenXe': 'Xe nguồn cũ'});
    await db.collection('ChiTietNhapHang').insertOne({
      'IdNhapHang': 45,
      'IdSanPham': 8,
      'TenSanPham': 'Phụ tùng thử',
      'SoLuong': 2,
    });
    final orders = await repo.purchaseOrders('p1');
    check(
      orders.total == 3 && orders.rows.first['MaDonHang'] == 45,
      'Wrong incoming orders or sort',
    );
    check(
      orders.rows.first['TongTien'] == 1000000 &&
          orders.rows.first['SanPhamHienThi'] == 'Phụ tùng thử',
      'Receipt fields incorrect',
    );
    check(
      orders.rows[1]['SanPhamHienThi'] == 'Xe nguồn cũ (#7)',
      'Legacy lot linkage lost',
    );
    check(
      orders.rows.last['MaDonHang'] == 99 &&
          orders.rows.last['TongTien'] == 700000,
      'Used vehicle purchase hidden',
    );
    await db.collection('NhapHang').insertMany([
      for (int i = 0; i < 35; i++)
        {
          'IdNhapHang': 100 + i,
          'IdDoiTac': 'p1',
          'NgayNhap': DateTime.utc(2026, 11, 5 + i),
        },
    ]);
    final first = await repo.purchaseOrders('p1');
    final second = await repo.purchaseOrders('p1', page: 1);
    check(
      first.total == 38 &&
          first.rows.length == 30 &&
          second.rows.length == 8 &&
          second.rows.last['MaDonHang'] == 99,
      'Combined pagination wrong',
    );
    check(
      (await repo.purchaseOrders('p2')).total == 1,
      'Partner isolation failed',
    );
    check(
      (await repo.fetchPartners(search: 'đối tác mới')).total == 1,
      'Search failed',
    );
    stdout.writeln(
      'PASS: newest partners, incoming orders only, newest receipts, exact partner linkage, legacy vehicles, parts and search.',
    );
  } finally {
    await repo.close();
    await db.drop();
    await db.close();
  }
}
