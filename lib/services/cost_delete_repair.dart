import 'package:mongo_dart/mongo_dart.dart';

import '../models/maintenance/record_maintenance.dart';
import 'mongo_record_maintenance.dart';

const costCollections = ['Xe', 'SanPham', 'ChiTietNhapHang'];

/// TongChiPhi counts only costs that are still active.
final activeCostSum = {
  r'$sum': {
    r'$map': {
      'input': {
        r'$ifNull': [r'$ChiPhi', []],
      },
      'as': 'cost',
      'in': {
        r'$cond': [
          {
            r'$eq': [r'$$cost.DaXoa', true],
          },
          0,
          r'$$cost.SoTien',
        ],
      },
    },
  },
};

class CostValidatorRefresh {
  const CostValidatorRefresh(this.validator, this.changed);
  final Map<String, dynamic> validator;
  final bool changed;
}

/// Replaces the legacy rule that required TongChiPhi to equal every SoTien,
/// including rows already marked DaXoa.
CostValidatorRefresh refreshCostValidator(dynamic node) {
  var changed = false;
  dynamic walk(dynamic value) {
    if (value is Map && value[r'$sum'] == r'$ChiPhi.SoTien') {
      changed = true;
      return activeCostSum;
    }
    if (value is Map) {
      return {
        for (final entry in value.entries) '${entry.key}': walk(entry.value),
      };
    }
    if (value is List) return [for (final item in value) walk(item)];
    return value;
  }

  final next = walk(node);
  return CostValidatorRefresh(
    next is Map<String, dynamic>
        ? next
        : Map<String, dynamic>.from(next as Map),
    changed,
  );
}

bool isStuckCostPlan(Map<String, dynamic> plan) {
  final kind = plan['Kind'];
  if (kind != 'vehicleProduct' && kind != 'partProduct') return false;
  final operations = plan['Operations'];
  if (operations is! List || operations.isEmpty) return false;
  for (final raw in operations) {
    if (raw is! Map) return false;
    final fields = raw['Fields'];
    if (fields == null) {
      if (raw['Collection'] != 'ThuChiKhac' ||
          !'${raw['Id']}'.startsWith('product-cost-')) {
        return false;
      }
      continue;
    }
    if (fields is! Map) return false;
    final keys = fields.keys.map((key) => '$key').toSet();
    if (keys.isEmpty ||
        keys.any((key) => key != 'ChiPhi' && key != 'TongChiPhi')) {
      return false;
    }
  }
  return true;
}

final _repairs = <String, Future<void>>{};
final _repaired = <String>{};

String _repairKey(Db db) => '${db.databaseName}|${db.uriList.join('|')}';

/// Fixes the cost validator, then finishes product-cost plans left pending
/// because that validator rejected the soft delete.
Future<void> repairStuckCostDeletes(Db db) {
  final key = _repairKey(db);
  if (_repaired.contains(key)) return Future.value();
  return _repairs.putIfAbsent(key, () async {
    try {
      if (await _repair(db)) _repaired.add(key);
    } catch (_) {
      // The next open tries again. A failed repair must not block the screen.
    } finally {
      _repairs.remove(key);
    }
  });
}

Future<void> refreshCostCollectionValidators(Db db) async {
  for (final name in costCollections) {
    final infos = await db.getCollectionInfos({'name': name});
    if (infos.isEmpty) continue;
    final options = infos.first['options'];
    if (options is! Map || options['validator'] is! Map) continue;
    final refresh = refreshCostValidator(options['validator']);
    if (!refresh.changed) continue;
    await db.runCommand({
      'collMod': name,
      'validator': refresh.validator,
      'validationLevel': 'strict',
      'validationAction': 'error',
    });
  }
}

Future<bool> _repair(Db db) async {
  await refreshCostCollectionValidators(db);
  if (!await db.getCollectionNames().then(
    (names) => names.contains('_record_changes'),
  )) {
    return true;
  }
  final plans = await db.collection('_record_changes').find({
    'Kind': {
      r'$in': ['vehicleProduct', 'partProduct'],
    },
    r'$or': [
      {
        'State': {
          r'$in': ['pending', 'preparing'],
        },
      },
      {
        'State': 'done',
        'Released': {r'$ne': true},
      },
    ],
  }).toList();
  final maintenance = MongoRecordMaintenance(db, () async {});
  var retry = false;
  for (final plan in plans) {
    if (!isStuckCostPlan(plan)) continue;
    if (plan['State'] == 'preparing') {
      final date = plan['Date'];
      if (date is! DateTime ||
          DateTime.now().toUtc().difference(date.toUtc()).inSeconds < 120) {
        retry = true;
        continue;
      }
    }
    final parent = _asInt(plan['Parent']);
    final kind = plan['Kind'];
    if (parent == null || kind is! String) {
      retry = true;
      continue;
    }
    try {
      await maintenance.recover(RecordKind.values.byName(kind), parent);
    } catch (_) {
      retry = true;
    }
  }
  return !retry;
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num && value == value.roundToDouble()) return value.toInt();
  return null;
}
