import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/models/pawn/pawn_models.dart';
import 'package:xemay_app/services/mongo_pawn_repository.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

PawnDraft draft() => PawnDraft()
  ..customerId = 1
  ..asset = 'Xe thế chấp'
  ..amount = '5000000'
  ..rate = '2,5'
  ..daily = false
  ..loanDate = DateTime(2026, 11, 4)
  ..dueDate = DateTime(2026, 12, 4)
  ..notes = 'Giữ nguyên trường gốc';
Future<void> main() async {
  final uri =
      'mongodb://127.0.0.1:27017/XM_pawn_test_${DateTime.now().microsecondsSinceEpoch}';
  final db = Db(uri);
  await db.open();
  final repo = MongoPawnRepository(uri: uri);
  try {
    await db.collection('KhachHang').insertMany([
      {
        'IdKH': 1,
        'TenKhachHang': 'Khách cầm đồ thử',
        'SoDienThoai': '0900000001',
      },
      {'IdKH': 2, 'TenKhachHang': 'Khách khác'},
    ]);
    await db.collection('CamDo').insertOne({
      'IdCamDo': 10,
      'IdKhachHang': 2,
      'NgayVay': DateTime.utc(2026, 10, 1),
      'SoTienVay': 1000000,
      'TrangThai': true,
    });
    final token = ObjectId().oid;
    final id = await repo.create(draft(), requestId: token);
    check(id == 11, 'Identity sequence wrong');
    check(
      await repo.create(draft(), requestId: token) == id &&
          await db.collection('CamDo').count() == 2,
      'Retry duplicated contract',
    );
    final row = (await db.collection('CamDo').findOne({'IdCamDo': id}))!;
    check(
      row.keys.toSet().difference({
        '_id',
        'IdCamDo',
        'SoTienVay',
        'TaiSanTheChap',
        'NgayPhanTram',
        'LaiSuat',
        'NgayHan',
        'NgayVay',
        'IdKhachHang',
        'GhiChu',
        'TrangThai',
      }).isEmpty,
      'Unrequested fields persisted',
    );
    check(
      row['LaiSuat'] == 2.5 &&
          row['NgayPhanTram'] == false &&
          row['TrangThai'] == false,
      'Flags or monthly rate incorrect',
    );
    check(
      row['NgayVay'] == DateTime.utc(2026, 11, 4) &&
          row['NgayHan'] == DateTime.utc(2026, 12, 4),
      'Date shifted',
    );
    var page = await repo.fetch(search: '0900000001');
    check(
      page.total == 1 && page.rows.single['TenKhachHang'] == 'Khách cầm đồ thử',
      'Customer search or linkage wrong',
    );
    final scoped = await repo.fetch(customerId: 2);
    check(
      scoped.total == 1 && scoped.rows.single['IdCamDo'] == 10,
      'Customer pawn scope wrong',
    );
    check(
      (await repo.fetch(customerId: 1, search: 'Khách khác')).total == 0,
      'Search escaped exact customer scope',
    );
    final active = await repo.fetch(status: 'active');
    check(
      active.total == 1 && active.rows.single['TrangThai'] == false,
      'Active filter incorrect',
    );
    final closed = await repo.fetch(status: 'closed');
    check(
      closed.total == 1 && closed.rows.single['TrangThai'] == true,
      'Closed filter incorrect',
    );
    check(
      (await repo.fetch(status: 'active', customerId: 2)).total == 0,
      'Status bypassed customer scope',
    );
    check(
      (await repo.fetch(status: 'closed', search: '0900000001')).total == 0,
      'Search bypassed status',
    );
    page = await repo.fetch();
    check(page.rows.first['IdCamDo'] == 11, 'Newest contracts not first');
    bool rejected = false;
    try {
      await repo.create(draft()..customerId = 999, requestId: ObjectId().oid);
    } on PawnException {
      rejected = true;
    }
    check(rejected, 'Missing parent customer allowed');
    rejected = false;
    try {
      await repo.create(draft()..rate = '-1', requestId: ObjectId().oid);
    } on PawnException {
      rejected = true;
    }
    check(rejected, 'Negative rate accepted');
    rejected = false;
    try {
      await repo.create(
        draft()..dueDate = DateTime(2026, 10, 1),
        requestId: ObjectId().oid,
      );
    } on PawnException {
      rejected = true;
    }
    check(rejected, 'Due date before loan accepted');
    final other = MongoPawnRepository(uri: uri);
    final ids = await Future.wait(
      [repo, other].map(
        (r) => r.create(
          draft()
            ..daily = true
            ..rate = '2000',
          requestId: ObjectId().oid,
        ),
      ),
    );
    check(ids.toSet().length == 2, 'Concurrent IDs collided');
    await other.close();
    check(
      await db.collection('TraNoCamDo').count() == 0,
      'Unrequested payment history created',
    );
    stdout.writeln(
      'PASS: source-only fields, customer link/search, daily/monthly flags, decimal rate, dates, retry and concurrent IDs; no added payment or interest computation.',
    );
  } finally {
    await repo.close();
    await db.drop();
    await db.close();
  }
  final live = MongoPawnRepository();
  try {
    final current = await live.fetch();
    check(current.total >= 2674, 'Live pawn records missing');
    stdout.writeln('Read-only live check: ${current.total} pawn contracts.');
  } finally {
    await live.close();
  }
}
