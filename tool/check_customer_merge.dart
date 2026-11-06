import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/services/mongo_customer_repository.dart';

void check(bool ok, String message) {
  if (!ok) throw StateError(message);
  stdout.writeln('PASS: $message');
}

Future<void> main() async {
  final uri =
      'mongodb://127.0.0.1:27017/QA_MERGE_${DateTime.now().microsecondsSinceEpoch}';
  final db = Db(uri);
  final repo = MongoCustomerRepository(uri: uri);
  await db.open();
  try {
    for (var id = 1; id <= 5; id++) {
      await db.collection('KhachHang').insertOne({
        '_id': 'c$id',
        'IdKH': id,
        'TenKhachHang': 'Khách $id',
        'SoDienThoai': '090000000$id',
        'DiaChiChiTiet': 'Địa chỉ $id',
      });
    }
    await db.collection('Xa').insertOne({'IdXa': 7, 'TenXa': 'Xã kiểm thử'});
    await db
        .collection('KhachHang')
        .updateOne(
          {'IdKH': 2},
          {
            r'$set': {'IdXa': 7},
          },
        );
    final candidates = await repo.mergeCandidates();
    check(
      candidates.length == 5,
      'Duplicate search loads all active customers',
    );
    check(
      candidates.firstWhere((r) => r['IdKH'] == 2)['DiaChiHienThi'] ==
          'Địa chỉ 2, Xã kiểm thử',
      'Duplicate search uses full historical address including locality',
    );
    const refs = {
      'HoaDonBan': 'IdKH',
      'HoaDonMua': 'IdKh',
      'CamDo': 'IdKhachHang',
      'NoCu': 'IdKH',
    };
    for (final ref in refs.entries) {
      await db.collection(ref.key).insertMany([
        {
          '_id': 'a',
          ref.value: 2,
          'SoTien': 123456,
          'Ngay': DateTime.utc(2026, 11, 1),
        },
        {'_id': 'b', ref.value: '3', 'SoTien': 987654},
        {'_id': 'other', ref.value: 4, 'SoTien': 555},
      ]);
    }
    await db.collection('TraNo').insertOne({
      '_id': 'payment',
      'IdHoaDon': 10,
      'TienGoc': 200,
      'TienLai': 5,
    });
    final before = <String, List<Map<String, dynamic>>>{};
    for (final n in [...refs.keys, 'TraNo']) {
      before[n] = await db.collection(n).find().toList();
    }
    await repo.merge(targetId: 1, sourceIds: [2, 3, 2]);
    for (final ref in refs.entries) {
      final rows = await db.collection(ref.key).find().toList();
      for (final old in before[ref.key]!) {
        final now = rows.firstWhere((r) => r['_id'] == old['_id']);
        final expected = {...old, ref.value: old['_id'] == 'other' ? 4 : 1};
        check(
          now.toString() == expected.toString(),
          '${ref.key}/${old['_id']}: only customer reference changed',
        );
      }
    }
    check((await repo.fetch()).total == 3, 'Merged customers hidden');
    check(
      (await repo.mergeCandidates()).length == 3,
      'Merged customers excluded from duplicate candidates',
    );
    final target = await repo.findById(1);
    check(
      target!['TenKhachHang'] == 'Khách 1' &&
          target['SoDienThoai'] == '0900000001' &&
          target['DiaChiChiTiet'] == 'Địa chỉ 1',
      'Target identity preserved',
    );
    check(
      (await db.collection('TraNo').find().toList()).toString() ==
          before['TraNo'].toString(),
      'Repayment history unchanged',
    );
    final journal = await db.collection('_customer_merges').findOne({
      '_id': '1:2,3',
    });
    check(
      (journal!['BanGoc'] as List).length == 3 &&
          (journal['LienKetGoc'] as Map).length == 4,
      'Original customers and reference links retained',
    );
    await repo.merge(targetId: 1, sourceIds: [3, 2]);
    check(
      await db.collection('_customer_merges').count() == 1,
      'Retry is idempotent',
    );
    await db
        .collection('KhachHang')
        .updateOne(
          {'IdKH': 4},
          {
            r'$set': {
              'GiuChoDonBan': {'busy': true},
            },
          },
        );
    var rejected = false;
    try {
      await repo.merge(targetId: 1, sourceIds: [4]);
    } catch (_) {
      rejected = true;
    }
    check(rejected, 'Customer with pending sale is blocked');
    check(
      (await db.collection('KhachHang').findOne({'IdKH': 1}))!['KhoaGop'] ==
          null,
      'Validation failure releases acquired lock',
    );
    await db
        .collection('KhachHang')
        .updateOne(
          {'IdKH': 4},
          {
            r'$unset': {'GiuChoDonBan': ''},
          },
        );
    // Simulate an interrupted operation after some references and archive were written.
    final snapshots = await db.collection('KhachHang').find({
      'IdKH': {
        r'$in': [1, 4],
      },
    }).toList();
    await db.collection('_customer_merges').insertOne({
      '_id': '1:4',
      'TrangThai': 'dang_gop',
      'KhachChinh': 1,
      'KhachTrung': [4],
      'BanGoc': snapshots,
    });
    await db
        .collection('KhachHang')
        .updateMany(
          {
            'IdKH': {
              r'$in': [1, 4],
            },
          },
          {
            r'$set': {'KhoaGop': '1:4'},
          },
        );
    await db
        .collection('KhachHang')
        .updateOne(
          {'IdKH': 4},
          {
            r'$set': {'DaXoa': true, 'DaGopVao': 1},
          },
        );
    await db
        .collection('HoaDonBan')
        .updateOne(
          {'_id': 'other'},
          {
            r'$set': {'IdKH': 1},
          },
        );
    check(
      (await repo.pendingMerges()).length == 1,
      'Interrupted merge discoverable after restart',
    );
    await repo.merge(targetId: 1, sourceIds: [4]);
    check((await repo.pendingMerges()).isEmpty, 'Interrupted merge resumed');
    check(
      await db.collection('KhachHang').count({
            'KhoaGop': {r'$exists': true},
          }) ==
          0,
      'All customer locks released',
    );
    check(
      (await repo.orders(1)).total == 3,
      'All orders visible under retained customer',
    );
    stdout.writeln('Customer merge checks passed.');
  } finally {
    await repo.close();
    await db.drop();
    await db.close();
  }
}
