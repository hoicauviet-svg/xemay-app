import 'package:flutter_test/flutter_test.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/services/cost_delete_repair.dart';

void main() {
  test('legacy cost sum ignores deleted rows', () {
    final refresh = refreshCostValidator({
      r'$expr': {
        r'$eq': [
          r'$TongChiPhi',
          {r'$sum': r'$ChiPhi.SoTien'},
        ],
      },
    });
    expect(refresh.changed, isTrue);
    expect('${refresh.validator}', contains('DaXoa'));
    expect('${refresh.validator}', isNot(contains(r'$ChiPhi.SoTien')));
    expect(refreshCostValidator(refresh.validator).changed, isFalse);
  });

  test('only product cost plans are finished automatically', () {
    expect(
      isStuckCostPlan({
        'Kind': 'vehicleProduct',
        'Operations': [
          {
            'Collection': 'Xe',
            'Fields': {'ChiPhi': [], 'TongChiPhi': 0},
          },
          {
            'Collection': 'ThuChiKhac',
            'Id': 'product-cost-Xe-1-abc',
            'Fields': null,
          },
        ],
      }),
      isTrue,
    );
    expect(
      isStuckCostPlan({
        'Kind': 'vehicleProduct',
        'Operations': [
          {
            'Collection': 'Xe',
            'Fields': {'TenXe': 'Đổi tên'},
          },
        ],
      }),
      isFalse,
    );
    expect(
      isStuckCostPlan({
        'Kind': 'order',
        'Operations': [
          {
            'Collection': 'Xe',
            'Fields': {'TongChiPhi': 0},
          },
        ],
      }),
      isFalse,
    );
  });

  test('stuck cost delete finishes after the validator is repaired', () async {
    final db = Db(
      'mongodb://127.0.0.1:27017/XM_cost_delete_repair_${DateTime.now().microsecondsSinceEpoch}',
    );
    await db.open();
    try {
      final when = DateTime.utc(2026, 11, 11);
      final cost = {
        'Ngay': when,
        'SoTien': 100000,
        'GhiChu': 'Sơn',
        'MaYeuCau': 'abc',
      };
      await db.collection('Xe').insertOne({
        '_id': 1,
        'IdXe': 1,
        'ChiPhi': [cost],
        'TongChiPhi': 100000,
        'SuaXoaDangLuu': 'cost-plan-1',
      });
      await db.collection('ThuChiKhac').insertOne({
        '_id': 'product-cost-Xe-1-abc',
        'SoTien': 100000,
      });
      await db.runCommand({
        'collMod': 'Xe',
        'validator': {
          r'$expr': {
            r'$eq': [
              r'$TongChiPhi',
              {r'$sum': r'$ChiPhi.SoTien'},
            ],
          },
        },
        'validationLevel': 'strict',
        'validationAction': 'error',
      });
      final rejected = await db.collection('Xe').updateOne(
        {'_id': 1},
        {
          r'$set': {
            'ChiPhi': [
              {...cost, 'DaXoa': true, 'NgayXoa': when},
            ],
            'TongChiPhi': 0,
          },
        },
      );
      expect(rejected.isSuccess, isFalse);
      await db.collection('_record_changes').insertOne({
        '_id': 'cost-plan-1',
        'Kind': 'vehicleProduct',
        'Parent': 1,
        'State': 'pending',
        'Date': when,
        'Operations': [
          {
            'Collection': 'Xe',
            'Id': 1,
            'Fields': {
              'ChiPhi': [
                {...cost, 'DaXoa': true, 'NgayXoa': when},
              ],
              'TongChiPhi': 0,
            },
            'Unset': [],
          },
          {
            'Collection': 'ThuChiKhac',
            'Id': 'product-cost-Xe-1-abc',
            'Fields': null,
            'Unset': [],
          },
        ],
        'Locks': [
          {'Collection': 'Xe', 'Id': 1},
        ],
      });

      await repairStuckCostDeletes(db);

      final vehicle = await db.collection('Xe').findOne({'_id': 1});
      final plan = await db.collection('_record_changes').findOne({
        '_id': 'cost-plan-1',
      });
      expect(vehicle?['TongChiPhi'], 0);
      expect((vehicle?['ChiPhi'] as List).single['DaXoa'], isTrue);
      expect(vehicle?.containsKey('SuaXoaDangLuu'), isFalse);
      expect(plan?['State'], 'done');
      expect(plan?['Released'], isTrue);
      expect(
        await db.collection('ThuChiKhac').findOne({
          '_id': 'product-cost-Xe-1-abc',
        }),
        isNull,
      );
      final infos = await db.getCollectionInfos({'name': 'Xe'});
      expect('${infos.first['options']}', isNot(contains(r'$ChiPhi.SoTien')));
      expect('${infos.first['options']}', contains('DaXoa'));
    } finally {
      await db.drop();
      await db.close();
    }
  });
}
