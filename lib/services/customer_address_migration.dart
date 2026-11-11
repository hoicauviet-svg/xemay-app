import 'package:mongo_dart/mongo_dart.dart';
import 'customer_address.dart';

/// Serialize across repository connections; retry interrupted migrations.
final _addressMigrations = <String, Future<void>>{};
Future<void> migrateCustomerAddresses(Db db) {
  final key = db.uriList.join('|');
  return _addressMigrations.putIfAbsent(
    key,
    () => _migrate(db).whenComplete(() {
      _addressMigrations.remove(key);
    }),
  );
}

Future<void> _migrate(Db db) async {
  final customers = db.collection('KhachHang');
  final places = await db.collection('Xa').find().toList();
  final names = {for (final place in places) place['IdXa']: place['TenXa']};
  final legacy = await customers.find({
    'IdXa': {r'$exists': true},
  }).toList();
  // Validate everything before changing any address or removing the old table.
  for (final row in legacy) {
    if (row['IdXa'] != null && !names.containsKey(row['IdXa'])) {
      throw StateError(
        'Khách hàng #${row['IdKH']} thiếu xã tham chiếu. Giữ nguyên dữ liệu để kiểm tra.',
      );
    }
  }
  for (final place in places) {
    final saved = await db
        .collection('_app_address_archive')
        .updateOne(
          {'_id': 'Xa:${place['_id']}'},
          {
            r'$setOnInsert': {'document': place},
          },
          upsert: true,
        );
    if (!saved.isSuccess || saved.hasWriteErrors) {
      throw StateError('Không lưu được bản lưu danh mục xã.');
    }
  }
  for (final row in legacy) {
    final updated = await customers.updateOne(
      {
        '_id': row['_id'],
        'IdXa': row['IdXa'],
        'DiaChiChiTiet': row['DiaChiChiTiet'],
      },
      {
        r'$set': {
          'DiaChiChiTiet': mergedCustomerAddress(
            row['DiaChiChiTiet'],
            names[row['IdXa']],
          ),
        },
        r'$unset': {'IdXa': '', 'DiaChiHienThi': ''},
      },
    );
    if (!updated.isSuccess || updated.hasWriteErrors) {
      throw StateError('Không cập nhật được địa chỉ khách hàng.');
    }
  }
  if (await customers.findOne({
        'IdXa': {r'$exists': true},
      }) !=
      null) {
    throw StateError(
      'Địa chỉ đang thay đổi. Vui lòng thử lại; danh mục xã được giữ nguyên.',
    );
  }
  if (places.isNotEmpty || (await db.getCollectionNames()).contains('Xa')) {
    await db.collection('Xa').drop();
  }
}
