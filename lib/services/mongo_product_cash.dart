import 'package:mongo_dart/mongo_dart.dart';

/// Each expense keeps one cash voucher, including retries after source storage.
class MongoProductCash {
  static Future<void> record(
    Db db, {
    required String source,
    required dynamic productId,
    required Map<String, dynamic> cost,
    required String sourceKey,
  }) async {
    if (cost['DaXoa'] == true) return;
    final amount = cost['SoTien'], date = cost['Ngay'];
    if (amount is! num ||
        !amount.isFinite ||
        amount <= 0 ||
        date is! DateTime) {
      return;
    }
    final id = 'product-cost-$source-$productId-$sourceKey';
    final cash = db.collection('ThuChiKhac');
    if (await cash.findOne({'_id': id}) != null ||
        await db.collection('_record_deleted').findOne({
              '_id': 'ThuChiKhac:$id',
            }) !=
            null)
      return;
    final last = await cash
        .modernFind(sort: {'ThuChiId': -1}, limit: 1)
        .toList();
    final counters = db.collection('_app_counters');
    final counterResult = await counters.updateOne(
      {'_id': 'ThuChiKhac'},
      {
        r'$max': {'value': last.isEmpty ? 0 : last.first['ThuChiId']},
      },
      upsert: true,
    );
    if (!counterResult.isSuccess || counterResult.hasWriteErrors) {
      throw StateError('Chưa cấp được mã phiếu chi');
    }
    final next = await counters.findAndModify(
      query: {'_id': 'ThuChiKhac'},
      update: {
        r'$inc': {'value': 1},
      },
      returnNew: true,
    );
    final result = await cash.updateOne(
      {'_id': id},
      {
        r'$setOnInsert': {
          '_id': id,
          'ThuChiId': next!['value'],
          'NgayThang': date,
          'SoTien': amount,
          'ThuChi': false,
          'IdDanhMuc': 'product-cost',
          'TenDanhMuc': 'Chi phí sản phẩm',
          'Nguon': source,
          'IdSanPhamNguon': productId,
          'MaYeuCauNguon': sourceKey,
          'LyDo':
              'Chi phí sản phẩm #$productId${'${cost['GhiChu'] ?? ''}'.trim().isEmpty ? '' : ': ${cost['GhiChu']}'}',
        },
      },
      upsert: true,
    );
    if (!result.isSuccess || result.hasWriteErrors) {
      throw StateError('Chưa xác nhận ghi phiếu chi sản phẩm');
    }
  }

  static Future<int> backfill(Db db) async {
    var count = 0;
    for (final name in ['Xe', 'SanPham', 'ChiTietNhapHang']) {
      final rows = await db.collection(name).find({
        'ChiPhi.0': {r'$exists': true},
        if (name == 'ChiTietNhapHang') 'IdXe': null,
      }).toList();
      for (final row in rows) {
        final costs = row['ChiPhi'] as List;
        for (var i = 0; i < costs.length; i++) {
          final cost = Map<String, dynamic>.from(costs[i] as Map);
          await record(
            db,
            source: name,
            productId:
                row[name == 'Xe'
                    ? 'IdXe'
                    : name == 'SanPham'
                    ? 'IdSanPham'
                    : '_id'],
            cost: cost,
            sourceKey: '${cost['MaYeuCau'] ?? 'legacy-$i'}',
          );
          count++;
        }
      }
    }
    return count;
  }
}
