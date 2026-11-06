import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/models/services/service_models.dart';
import 'package:xemay_app/services/mongo_service_repository.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  final live = MongoServiceRepository();
  final uri =
      'mongodb://127.0.0.1:27017/XM_service_test_${DateTime.now().microsecondsSinceEpoch}';
  final db = Db(uri);
  final repository = MongoServiceRepository(uri: uri);
  try {
    final existing = await live.fetch();
    final draft = ServiceDraft()
      ..name = '  Thay dầu (test)  '
      ..description = ' Dầu động cơ '
      ..price = '150000';
    final item = await repository.create(draft);
    await db.open();
    final row = await db.collection('DichVu').findOne({'_id': item.id});
    check(
      row != null &&
          row.keys.toSet().difference({
            '_id',
            'TenDichVu',
            'MoTa',
            'GiaTien',
          }).isEmpty &&
          row['TenDichVu'] == 'Thay dầu (test)' &&
          row['MoTa'] == 'Dầu động cơ' &&
          row['GiaTien'] == 150000,
      'Service fields mismatch',
    );
    check(
      (await repository.fetch(search: '(test)')).rows.single.id == item.id,
      'Literal name search failed',
    );
    check(
      (await repository.fetch(search: 'ĐỘNG CƠ')).rows.single.id == item.id,
      'Description search failed',
    );
    for (final price in ['', '-1', '1.5', 'NaN']) {
      var rejected = false;
      try {
        await repository.create(
          ServiceDraft()
            ..name = 'Invalid'
            ..price = price,
        );
      } on ServiceException {
        rejected = true;
      }
      check(rejected, 'Invalid price accepted: $price');
    }
    await repository.create(
      ServiceDraft()
        ..name = 'Miễn phí'
        ..price = '0',
    );
    await db.collection('DichVu').insertMany([
      for (var i = 0; i < 31; i++)
        {
          '_id': 'fixture-$i',
          'TenDichVu': 'Dịch vụ ${i.toString().padLeft(2, '0')}',
          'MoTa': '',
          'GiaTien': i,
        },
    ]);
    final all = await repository.fetch();
    check(
      all.total == 33 && all.rows.length == 33,
      'Service list is still paginated',
    );
    stdout.writeln(
      'PASS: ${existing.total} live services read; create/read three fields, literal name/description search, valid prices and unpaged listing verified in isolated database.',
    );
  } finally {
    await live.close();
    await repository.close();
    if (!db.isConnected) await db.open();
    await db.drop();
    await db.close();
  }
}
