import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/models/customers/customer_models.dart';
import 'package:xemay_app/services/mongo_customer_repository.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  final live = MongoCustomerRepository();
  final uri =
      'mongodb://127.0.0.1:27017/XM_customer_test_${DateTime.now().microsecondsSinceEpoch}';
  final db = Db(uri);
  final repository = MongoCustomerRepository(uri: uri);
  try {
    final page = await live.fetch();
    final phone = await live.fetch(phoneFilter: 'with_phone');
    final missing = await live.fetch(phoneFilter: 'without_phone');
    check(phone.total + missing.total == page.total, 'Phone filters mismatch');
    final next = await live.fetch(page: 1);
    final ids = page.rows.map((r) => r['IdKH']).toSet();
    check(next.rows.every((r) => !ids.contains(r['IdKH'])), 'Pages overlap');
    check((await live.localities()).isNotEmpty, 'Missing localities');
    await db.open();
    await db.collection('Xa').insertOne({'IdXa': 1, 'TenXa': 'Xã kiểm thử'});
    final draft = CustomerDraft()
      ..name = 'Khách (test)'
      ..phone = '0900000001'
      ..address = 'Thôn kiểm thử, Xã kiểm thử';
    await repository.create(draft);
    var saved = (await repository.fetch(search: '(test)')).rows.single;
    check(
      saved['SoDienThoai'] == draft.phone &&
          saved['DiaChiChiTiet'] == draft.address,
      'Fields not saved',
    );
    check(
      (await repository.fetch(search: 'Xã kiểm thử')).total == 1,
      'Locality search failed',
    );
    final firstId = saved['IdKH'];
    final info = await repository.findById(firstId);
    check(
      info?['DiaChiHienThi'] == draft.address,
      'Customer detail address mismatch',
    );
    await db.collection('SanPham').insertOne({
      'IdSanPham': 7,
      'TenSanPham': 'Xe kiểm thử',
    });
    await db.collection('HoaDonBan').insertMany([
      {'IdHoaDon': 42, 'IdKH': firstId, 'NgayMua': DateTime(2026, 11, 1)},
      {'IdHoaDon': 43, 'IdKH': firstId + 100, 'NgayMua': DateTime(2026, 11, 2)},
    ]);
    await db.collection('ChiTietHoaDonBan').insertOne({
      'IdHoaDon': 42,
      'IdSanPham': 7,
      'IdXe': 9,
      'SoLuong': 1,
      'DonGia': null,
      'DonGiaNguon': 1000000,
    });
    final sale = await repository.orders(firstId);
    check(
      sale.total == 1 &&
          sale.rows.single['MaDonHang'] == 42 &&
          sale.rows.single['TongTien'] == null &&
          sale.rows.single['TongSoLuong'] == 1 &&
          sale.rows.single['SanPhamHienThi'] == 'Xe kiểm thử (#9)',
      'Sale links or source price handling incorrect',
    );
    await db.collection('HoaDonMua').insertOne({
      'IdMua': 44,
      'IdKh': firstId,
      'NgayBan': DateTime(2026, 11, 3),
    });
    await db.collection('ChiTietHoaDonMua').insertOne({
      'IdMua': 44,
      'IdSanPham': 7,
      'IdXe': 9,
      'SoLuong': 2,
      'DonGia': 500000,
    });
    await db.collection('HoaDonBan').deleteMany({});
    await db.collection('HoaDonMua').deleteMany({});
    final legacy = await live.findById(32);
    final legacyOrders = await live.orders(32);
    check(
      legacy != null &&
          legacyOrders.total > 0 &&
          legacyOrders.rows.every((r) => r['IdKH'] == 32),
      'Live customer orders mismatch',
    );

    for (final ref in {
      'HoaDonBan': 'IdKH',
      'HoaDonMua': 'IdKh',
      'CamDo': 'IdKhachHang',
      'NoCu': 'IdKH',
    }.entries) {
      await db.collection(ref.key).insertOne({ref.value: firstId});
      var blocked = false;
      try {
        await repository.delete(saved);
      } on CustomerException {
        blocked = true;
      }
      check(blocked, 'Allowed deletion with ${ref.key} reference');
      await db.collection(ref.key).deleteMany({});
    }
    await repository.delete(saved);
    check(
      (await repository.fetch()).total == 0,
      'Deleted customer still listed',
    );
    check(
      (await db.collection('KhachHang').findOne({'IdKH': firstId}))?['DaXoa'] ==
          true,
      'Missing recoverable record',
    );
    await Future.wait([
      repository.create(CustomerDraft()..name = 'Khách A'),
      repository.create(CustomerDraft()..name = 'Khách B'),
    ]);
    final fresh = await repository.fetch();
    check(
      fresh.total == 2 &&
          fresh.rows.map((r) => r['IdKH']).toSet().length == 2 &&
          fresh.rows.every((r) => r['IdKH'] > firstId),
      'IDs reused or duplicated',
    );
    check(
      (await repository.fetch(phoneFilter: 'without_phone')).total == 2,
      'Missing phone filter failed',
    );
    stdout.writeln(
      'PASS: ${page.total} live customers read; search, phone filters, paging, save fields, unique IDs and four deletion guards verified in isolated database.',
    );
  } finally {
    await live.close();
    await repository.close();
    if (!db.isConnected) await db.open();
    await db.drop();
    await db.close();
  }
}
