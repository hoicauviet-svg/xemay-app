import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/models/inventory/inventory_models.dart';
import 'package:xemay_app/services/mongo_inventory_repository.dart';

void check(bool ok, String message) {
  if (!ok) throw StateError(message);
}

Future<void> main() async {
  final uri =
      'mongodb://127.0.0.1:27017/XM_product_list_test_${DateTime.now().microsecondsSinceEpoch}';
  final db = Db(uri);
  await db.open();
  final repo = MongoInventoryRepository(uri: uri);
  try {
    await db.collection('_sql_metadata').insertOne({
      '_id': 'product_schema_v2',
    });
    await db.collection('Xe').insertMany([
      for (var i = 1; i <= 35; i++)
        {
          'IdXe': i,
          'IdSanPham': 1,
          'TenXe': 'Xe kiểm tra',
          'TinhTrangXe': 'moi',
          'TinhTrang': true,
          'GiaNhap': 100.0,
          'GiaBan': 150.0,
        },
    ]);
    await repo.connect();
    final all = await repo.fetch(
      InventorySection.vehicles,
      condition: 'moi',
      availability: 'available',
      pageSize: 0,
    );
    check(
      all.total == 35 &&
          all.rows.length == 35 &&
          all.rows.every((r) => r['SoLuongTon'] == 1),
      'Vehicle list still paginated',
    );
    check(
      (await repo.fetch(
        InventorySection.vehicles,
        condition: 'cu',
        pageSize: 0,
      )).rows.isEmpty,
      'Vehicle category lost',
    );
    await db.collection('SanPham').insertMany([
      for (var i = 1; i <= 35; i++)
        {
          'IdSanPham': i,
          'LoaiSanPham': 'phu_tung',
          'TenSanPham': 'Phụ tùng $i',
        },
    ]);
    await db.collection('TonKhoPhuTung').insertMany([
      for (var i = 1; i <= 35; i++) {'IdSanPham': i, 'SoLuongTon': 2},
    ]);
    final parts = await repo.fetch(
      InventorySection.parts,
      availability: 'available',
      pageSize: 0,
    );
    check(
      parts.rows.length == 35 && parts.rows.every((r) => r['SoLuongTon'] == 2),
      'Part list still paginated or stock missing',
    );
    stdout.writeln(
      'PASS: unpaged vehicle and part lists retain category, availability and stock values in isolated database.',
    );
  } finally {
    await repo.close();
    await db.drop();
    await db.close();
  }
}
