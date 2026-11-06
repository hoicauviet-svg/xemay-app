import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/models/sales/sale_models.dart';
import 'package:xemay_app/services/mongo_sales_repository.dart';

Future<void> main() async {
  final uri =
      'mongodb://127.0.0.1:27017/QA_FULL_cost_${DateTime.now().microsecondsSinceEpoch}';
  final db = Db(uri);
  await db.open();
  var stop = true;
  final repo = MongoSalesRepository(
    uri: uri,
    checkpoint: (point) async {
      if (point == 'afterPurchaseCosts' && stop) {
        stop = false;
        throw StateError('Injected lost response');
      }
    },
  );
  try {
    await db.collection('_sql_metadata').insertOne({'_id': 'sales_schema_v3'});
    await db.collection('SanPham').insertOne({
      'IdSanPham': 1,
      'TenSanPham': 'QA PART',
      'LoaiSanPham': 'phu_tung',
    });
    await db.collection('TonKhoPhuTung').insertOne({
      'IdSanPham': 1,
      'SoLuongTon': 10,
      'GiaVonThamKhao': 100000,
    });
    final draft = SaleDraft(
      lines: [
        const SaleLine(
          kind: 'phu_tung',
          name: 'QA PART',
          quantity: 2,
          price: 150000,
          productId: 1,
        ),
      ],
      date: DateTime(2026, 11, 5),
      discount: 0,
      paid: 300000,
    );
    final key = ObjectId().oid;
    try {
      await repo.save(draft, key);
    } catch (_) {}
    await db
        .collection('TonKhoPhuTung')
        .updateOne(
          {'IdSanPham': 1},
          {
            r'$set': {'GiaVonThamKhao': 200000},
          },
        );
    final saved = await repo.save(draft, key);
    final lines = await db.collection('ChiTietHoaDonBan').find({
      'IdHoaDon': saved.invoiceId,
    }).toList();
    if (lines.length != 1 || lines.single['GiaNhap'] != 100000) {
      throw StateError('Cost changed across retry');
    }
    final stock = await db.collection('TonKhoPhuTung').findOne({
      'IdSanPham': 1,
    });
    if (stock?['SoLuongTon'] != 8) throw StateError('Stock duplicated');
    stdout.writeln(
      'PASS: sale cost remains 100000 across interrupted save and later reference-price change; exactly one sale line, stock 8.',
    );
  } finally {
    await repo.close();
    await db.drop();
    await db.close();
  }
}
