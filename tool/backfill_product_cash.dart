import 'dart:convert';
import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/services/mongo_product_cash.dart';

Future<void> main(List<String> args) async {
  final db = Db('mongodb://127.0.0.1:27017/XM');
  await db.open(writeConcern: WriteConcern.journaled);
  try {
    final sources = <String, dynamic>{};
    for (final name in ['Xe', 'SanPham', 'ChiTietNhapHang']) {
      sources[name] = await db.collection(name).find({
        'ChiPhi.0': {r'$exists': true},
        if (name == 'ChiTietNhapHang') 'IdXe': null,
      }).toList();
    }
    final before = await db.collection('ThuChiKhac').find({
      'IdDanhMuc': 'product-cost',
    }).toList();
    stdout.writeln(
      'Expense source records: ${sources.map((k, v) => MapEntry(k, (v as List).length))}; existing product cash vouchers: ${before.length}',
    );
    if (!args.contains('--apply')) return;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final backup = File('../product-cash-backfill-$stamp.json');
    await backup.writeAsString(
      JsonEncoder.withIndent(
        '  ',
        toEncodable,
      ).convert({'sources': sources, 'cashBefore': before}),
    );
    stdout.writeln('Backup: ${backup.absolute.path}');
    stdout.writeln(
      'Processed expenses: ${await MongoProductCash.backfill(db)}',
    );
    final after = await db.collection('ThuChiKhac').find({
      'IdDanhMuc': 'product-cost',
    }).toList();
    stdout.writeln(
      'Product cash vouchers after: ${after.length}; total: ${after.fold<num>(0, (s, r) => s + (r['SoTien'] as num))}',
    );
  } finally {
    await db.close();
  }
}

dynamic toEncodable(dynamic value) =>
    value is DateTime ? value.toIso8601String() : value.toString();
