import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/services/customer_address_migration.dart';
import 'package:xemay_app/services/mongo_customer_repository.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  final uri =
      'mongodb://127.0.0.1:27017/XM_address_test_${DateTime.now().microsecondsSinceEpoch}';
  final db = Db(uri);
  final repo = MongoCustomerRepository(uri: uri);
  try {
    await db.open();
    await db.collection('Xa').insertOne({
      '_id': 'xa7',
      'IdXa': 7,
      'TenXa': 'Mậu A, Văn Yên, Yên Bái',
    });
    await db.collection('KhachHang').insertMany([
      {
        '_id': 'a',
        'IdKH': 1,
        'IdXa': 7,
        'TenKhachHang': 'Khách A',
        'DiaChiChiTiet': 'Tổ 3',
      },
      {
        '_id': 'b',
        'IdKH': 2,
        'IdXa': 7,
        'DiaChiChiTiet': 'Tổ 4, Mậu A, Văn Yên, Yên Bái',
      },
    ]);
    print('Checking repository migration and search…');
    final result = await repo.fetch(search: 'Mậu A');
    print('Checking saved fields…');
    check(result.total == 2, 'Full address search failed');
    check(
      (await db.collection('KhachHang').findOne({
            '_id': 'a',
          }))!['DiaChiChiTiet'] ==
          'Tổ 3, Mậu A, Văn Yên, Yên Bái',
      'Missing locality',
    );
    check(
      (await db.collection('KhachHang').findOne({
            '_id': 'b',
          }))!['DiaChiChiTiet'] ==
          'Tổ 4, Mậu A, Văn Yên, Yên Bái',
      'Duplicate locality',
    );
    check(
      !(await db.getCollectionNames()).contains('Xa'),
      'Legacy table remains',
    );
    check(
      await db.collection('_app_address_archive').count() == 1,
      'Missing archive',
    );
    print('Checking repeated migration…');
    await migrateCustomerAddresses(db);
    print('Repeated migration finished');
    check(
      await db.collection('KhachHang').count() == 2,
      'Migration lost customers',
    );
    print(
      'PASS: migrated full addresses, search, archive, drop Xa, repeat safely',
    );
  } finally {
    print('Cleaning test database…');
    await repo.close();
    if (db.isConnected) {
      await db.drop();
      await db.close();
    }
  }
}
