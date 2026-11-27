import 'package:mongo_dart/mongo_dart.dart';

import '../core/config/database_config.dart';
import '../models/maintenance/record_maintenance.dart';
import 'mongo_record_maintenance.dart';
import 'mongo_sync_journal.dart';

class StuckOrderIssue {
  const StuckOrderIssue({
    required this.orderId,
    required this.title,
    required this.details,
    required this.actions,
    required this.fixable,
    this.blocker,
  });
  final int orderId;
  final String title;
  final List<String> details, actions;
  final bool fixable;
  final String? blocker;
}

class StuckOrderScan {
  const StuckOrderScan({
    required this.issues,
    required this.checkedOrders,
    required this.pendingPlans,
    required this.staleLocks,
    required this.headerMismatches,
    required this.at,
  });
  final List<StuckOrderIssue> issues;
  final int checkedOrders, pendingPlans, staleLocks, headerMismatches;
  final DateTime at;
  bool get hasFixable => issues.any((issue) => issue.fixable);
}

class StuckOrderRepairResult {
  const StuckOrderRepairResult({
    required this.orderId,
    required this.ok,
    required this.message,
    this.fixed = false,
  });
  final int orderId;
  final bool ok, fixed;
  final String message;
}

class StuckOrderRepairRun {
  const StuckOrderRepairRun({
    required this.results,
    required this.scan,
    this.historyError,
  });
  final List<StuckOrderRepairResult> results;
  final StuckOrderScan scan;
  final String? historyError;
  bool get wrote => results.any((result) => result.fixed);
  bool get ok => results.every((result) => result.ok);
}

abstract class StuckOrderRunner {
  Future<StuckOrderScan> scan();
  Future<StuckOrderRepairRun> repair();
  Future<void> close();
}

class StuckOrderException implements Exception {
  const StuckOrderException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Finds and repairs orders blocked by a half-applied record change: pending
/// plans, stale `SuaXoaDangLuu` locks and a header that no longer matches the
/// debt book. New sale headers must satisfy the same rules as the deployed
/// HoaDonBan validator.
class StuckOrderRepair implements StuckOrderRunner {
  StuckOrderRepair(this.db, this.connect);
  factory StuckOrderRepair.local() {
    final db = SyncTrackedDb(DatabaseConfig.mongoUri);
    return StuckOrderRepair(db, () async {
      if (!db.isConnected) await db.open(writeConcern: WriteConcern.journaled);
    });
  }

  final Db db;
  final Future<void> Function() connect;
  late final _maintenance = MongoRecordMaintenance(db, connect);

  @override
  Future<void> close() async {
    if (db.isConnected) await db.close();
  }

  @override
  Future<StuckOrderScan> scan() async {
    final collected = await _collect();
    return _scanFrom(collected);
  }

  @override
  Future<StuckOrderRepairRun> repair() async {
    final collected = await _collect();
    final results = <StuckOrderRepairResult>[];
    var wrote = false;
    for (final context in collected.contexts) {
      if (!context.fixable) continue;
      try {
        final stepResults = await _repairOrder(context);
        final changed = stepResults.$1;
        final message = stepResults.$2;
        wrote = wrote || changed;
        results.add(
          StuckOrderRepairResult(
            orderId: context.orderId,
            ok: true,
            message: message,
            fixed: changed,
          ),
        );
      } catch (error) {
        results.add(
          StuckOrderRepairResult(
            orderId: context.orderId,
            ok: false,
            message: '$error',
          ),
        );
      }
    }
    final after = await _collect();
    final scan = _scanFrom(after);
    String? historyError;
    try {
      await db.collection('_fix_history').insertOne({
        '_id': ObjectId(),
        'Date': DateTime.now().toUtc(),
        'Ok': results.every((result) => result.ok),
        'Description': 'Quét và sửa đơn kẹt',
        'Operations': results.length,
        'Executed': results.length,
        'Script': 'builtin:stuck-orders',
        'Results': [
          for (final result in results)
            {
              'OrderId': result.orderId,
              'Ok': result.ok,
              'Fixed': result.fixed,
              'Message': result.message,
            },
        ],
      });
    } catch (error) {
      historyError = '$error';
    }
    return StuckOrderRepairRun(
      results: results,
      scan: scan,
      historyError: historyError,
    );
  }

  Future<(bool, String)> _repairOrder(_OrderContext context) async {
    final header = context.header;
    if (header == null &&
        (context.planFixes.isNotEmpty || context.mismatch != null)) {
      throw const StuckOrderException('Không tìm thấy đơn hàng.');
    }
    var changed = false;
    for (final fix in context.planFixes) {
      final patched = await db
          .collection('_record_changes')
          .updateOne(
            {'_id': fix.planId},
            {
              r'$set': {'Operations.${fix.index}.Fields': fix.fields},
            },
          );
      if (!patched.isSuccess || patched.hasWriteErrors) {
        throw StuckOrderException(
          'Không sửa được kế hoạch: ${_writeError(patched)}',
        );
      }
      final write = await db
          .collection('HoaDonBan')
          .updateOne(
            {'_id': header!['_id']},
            {
              if (fix.fields.isNotEmpty) r'$set': fix.fields,
              if (fix.unset.isNotEmpty)
                r'$unset': {for (final key in fix.unset) key: ''},
            },
          );
      if (!write.isSuccess || write.hasWriteErrors) {
        throw StuckOrderException(
          'MongoDB từ chối cập nhật header: ${_writeError(write)}',
        );
      }
      changed = true;
    }
    if (context.planFixes.isNotEmpty || context.recoverNeeded) {
      await _maintenance.recover(RecordKind.order, context.orderId);
      changed = true;
    }
    if (context.mismatch != null) {
      final write = await db
          .collection('HoaDonBan')
          .updateOne(
            {'_id': header!['_id']},
            {r'$set': context.mismatch!.fields},
          );
      if (!write.isSuccess || write.hasWriteErrors) {
        throw StuckOrderException(
          'MongoDB từ chối cập nhật header: ${_writeError(write)}',
        );
      }
      changed = true;
    }
    for (final lock in context.staleLocks) {
      final write = await db
          .collection(lock.collection)
          .updateOne(
            {'_id': lock.id, 'SuaXoaDangLuu': lock.lock},
            {
              r'$unset': {'SuaXoaDangLuu': ''},
            },
          );
      if (!write.isSuccess || write.hasWriteErrors) {
        throw StuckOrderException(
          'Không giải phóng được khóa ${lock.collection}: ${_writeError(write)}',
        );
      }
      changed = true;
    }
    // Re-read what remains for this order before reporting success.
    final plans = await db.collection('_record_changes').count({
      'Kind': 'order',
      'Parent': context.orderId,
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
    });
    final locked = await db.collection('HoaDonBan').count({
      'IdHoaDon': context.orderId,
      'SuaXoaDangLuu': {r'$exists': true},
    });
    if (plans > 0 || locked > 0) {
      throw const StuckOrderException(
        'Vẫn còn kế hoạch hoặc khóa sau khi sửa.',
      );
    }
    return (changed, 'Đã sửa đơn #${context.orderId}.');
  }

  Future<_Collected> _collect() async {
    await connect();
    final now = DateTime.now().toUtc();
    final rawPlans = await db.collection('_record_changes').find({
      'Kind': 'order',
    }).toList();
    final activePlans = <Map<String, dynamic>>[];
    final allPlanIds = <String>{};
    for (final raw in rawPlans) {
      final plan = Map<String, dynamic>.from(raw);
      final id = plan['_id'];
      if (id is! String) continue;
      allPlanIds.add(id);
      final state = plan['State'];
      if (state == 'pending' ||
          state == 'preparing' ||
          (state == 'done' && plan['Released'] != true)) {
        activePlans.add(plan);
      }
    }
    final activePlanIds = {
      for (final plan in activePlans) plan['_id'] as String,
    };
    final byOrder = <int, List<Map<String, dynamic>>>{};
    for (final plan in activePlans) {
      final parent = (plan['Parent'] as num?)?.toInt();
      if (parent == null) continue;
      byOrder.putIfAbsent(parent, () => []).add(plan);
    }

    final headerIds = <int>{...byOrder.keys};
    final lockedHeaders = await db.collection('HoaDonBan').find({
      'SuaXoaDangLuu': {r'$exists': true},
    }).toList();
    for (final row in lockedHeaders) {
      final id = (row['IdHoaDon'] as num?)?.toInt();
      if (id != null) headerIds.add(id);
    }
    final lockedDebts = await db.collection('SoNo').find({
      'SuaXoaDangLuu': {r'$exists': true},
    }).toList();
    for (final row in lockedDebts) {
      final id = (row['IdHoaDon'] as num?)?.toInt();
      if (id != null) headerIds.add(id);
    }
    final headers = <int, Map<String, dynamic>>{};
    final debts = <int, Map<String, dynamic>>{};
    if (headerIds.isNotEmpty) {
      for (final row in await db.collection('HoaDonBan').find({
        'IdHoaDon': {r'$in': headerIds.toList()},
      }).toList()) {
        final id = (row['IdHoaDon'] as num?)?.toInt();
        if (id != null) headers[id] = row;
      }
      for (final row in await db.collection('SoNo').find({
        'IdHoaDon': {r'$in': headerIds.toList()},
      }).toList()) {
        final id = (row['IdHoaDon'] as num?)?.toInt();
        if (id != null) debts.putIfAbsent(id, () => row);
      }
    }

    final contexts = <int, _OrderContext>{};
    _OrderContext contextFor(int orderId) => contexts.putIfAbsent(
      orderId,
      () => _OrderContext(orderId, headers[orderId], debts[orderId]),
    );

    for (final entry in byOrder.entries) {
      final orderId = entry.key;
      final header = headers[orderId], debt = debts[orderId];
      final context = contextFor(orderId);
      if (header == null) {
        context.block('Không tìm thấy đơn hàng trong HoaDonBan.');
        continue;
      }
      if (debt == null) {
        if (entry.value.any((plan) => plan['Action'] == 'cancel')) {
          context.recoverNeeded = true;
          context.action('Hoàn tất hủy đơn #$orderId đang dở dang.');
        } else {
          context.block('Không tìm thấy sổ nợ của đơn.');
        }
        continue;
      }
      for (final plan in entry.value) {
        final planId = plan['_id'] as String;
        final state = plan['State'];
        final operations = (plan['Operations'] as List?) ?? const [];
        final steps = [
          for (final raw in operations)
            if (raw is Map) Map<String, dynamic>.from(raw),
        ];
        final headerIndex = steps.indexWhere(
          (step) => step['Collection'] == 'HoaDonBan',
        );
        final deleting = steps.any(
          (step) => step['Collection'] == 'HoaDonBan' && step['Fields'] == null,
        );
        if (deleting) {
          context.block(
            'Kế hoạch xóa đơn $planId đang dở dang. Dùng “Tiếp tục xử lý” thay vì sửa tự động.',
          );
          continue;
        }
        if (state == 'preparing') {
          final date = plan['Date'];
          final fresh = date is DateTime && now.difference(date).inMinutes < 2;
          if (fresh) {
            context.block(
              'Kế hoạch $planId đang được chuẩn bị. Đợi 2 phút rồi quét lại.',
            );
          } else {
            context.recoverNeeded = true;
            context.action(
              'Hủy kế hoạch chuẩn bị bị treo $planId và giải phóng khóa.',
            );
          }
          continue;
        }
        final executorUntil = plan['ExecutionUntil'];
        if (plan['Executor'] != null &&
            executorUntil is DateTime &&
            executorUntil.isAfter(now)) {
          context.block(
            'Kế hoạch $planId đang được xử lý. Đợi 2 phút rồi quét lại.',
          );
          continue;
        }
        if (state == 'done') {
          context.recoverNeeded = true;
          context.action('Hoàn tất giải phóng khóa của kế hoạch $planId.');
          continue;
        }
        if (headerIndex < 0) {
          context.block(
            'Kế hoạch $planId không có bước cập nhật header để kiểm tra.',
          );
          continue;
        }
        final step = steps[headerIndex];
        final fields = (step['Fields'] as Map?) ?? const {};
        final unset = [
          for (final value in (step['Unset'] as List?) ?? const []) '$value',
        ];
        final fix = _correctPlanFields(
          header,
          debt,
          Map<String, dynamic>.from(fields),
          unset,
        );
        if (fix == null) {
          context.block(
            'Không thể tự sửa kế hoạch $planId (dữ liệu còn vi phạm quy tắc khác).',
          );
          continue;
        }
        final changed = _fieldsDiffer(fields, fix.fields);
        context.planFixes.add(
          _PlanFix(
            planId: planId,
            index: headerIndex,
            fields: fix.fields,
            unset: unset,
          ),
        );
        context.action(
          changed
              ? 'Sửa lại bước header của kế hoạch $planId rồi hoàn tất kế hoạch.'
              : 'Hoàn tất kế hoạch $planId và giải phóng khóa.',
        );
        if (changed) {
          context.detail(
            'Kế hoạch $planId có header không thỏa ràng buộc dữ liệu.',
          );
        }
      }
    }

    // Locks left behind by a plan that no longer needs them.
    for (final source in [
      ('HoaDonBan', lockedHeaders),
      ('SoNo', lockedDebts),
    ]) {
      for (final row in source.$2) {
        final lock = row['SuaXoaDangLuu'];
        if (lock is! String || activePlanIds.contains(lock)) continue;
        final orderId = (row['IdHoaDon'] as num?)?.toInt();
        if (orderId == null) continue;
        if (headers[orderId] == null && debts[orderId] == null) continue;
        final context = contextFor(orderId);
        final existing = context.staleLocks.any(
          (item) => item.collection == source.$1 && item.id == row['_id'],
        );
        if (existing) continue;
        context.staleLocks.add(
          _LockContext(source.$1, row['_id'], orderId, lock),
        );
        context.action('Xóa khóa còn sót $lock trên ${source.$1}.');
      }
    }

    // New sale headers that no longer match their debt book.
    final mismatchRows = await db.collection('HoaDonBan').aggregateToStream([
      {
        r'$match': {'PhienBanBanHang': 3},
      },
      {
        r'$lookup': {
          'from': 'SoNo',
          'localField': 'IdHoaDon',
          'foreignField': 'IdHoaDon',
          'as': '_debt',
        },
      },
      {
        r'$match': {
          '_debt.0': {r'$exists': true},
        },
      },
      {
        r'$project': {
          '_id': 1,
          'IdHoaDon': 1,
          'IdKH': 1,
          'NgayMua': 1,
          'NgayHen': 1,
          'NgayTinhLai': 1,
          'TongTienHang': 1,
          'GiamGia': 1,
          'TongThanhToan': 1,
          'SoTienKhachDua': 1,
          'SoTienDaTra': 1,
          'SoTienConNo': 1,
          'TienThua': 1,
          'PhienBanNgayCongNo': 1,
          'PhienBanBanHang': 1,
          'MaYeuCauLuu': 1,
          'TrangThaiLuu': 1,
          'ThanhToanDangLuu': 1,
          'SuaXoaDangLuu': 1,
          'debtCount': {r'$size': r'$_debt'},
          'debt': {
            r'$arrayElemAt': [r'$_debt', 0],
          },
        },
      },
    ]).toList();
    final checked = <int>{...headerIds};
    for (final row in mismatchRows) {
      final orderId = (row['IdHoaDon'] as num?)?.toInt();
      if (orderId == null) continue;
      checked.add(orderId);
      if (row['debtCount'] != 1) continue;
      final header = Map<String, dynamic>.from(row)
        ..remove('debt')
        ..remove('debtCount');
      final debt = Map<String, dynamic>.from(row['debt'] as Map);
      if (header['ThanhToanDangLuu'] != null) continue;
      if (byOrder.containsKey(orderId)) continue; // The plan repair handles it.
      final paid = debt['SoTienDaTra'], due = debt['SoTienConNo'];
      if (paid is! num || due is! num) continue;
      final mismatch =
          header['SoTienDaTra'] != paid || header['SoTienConNo'] != due;
      final fix = _correctMismatch(header, debt);
      if (fix == null) {
        if (mismatch || !_headerValid(header)) {
          final context = contextFor(orderId)
            ..header = header
            ..debt = debt;
          context.block('Header đơn lệch sổ nợ nhưng không tự sửa được.');
        }
        continue;
      }
      final valid = _headerValid({...header, ...fix.fields});
      if (!valid) {
        final context = contextFor(orderId)
          ..header = header
          ..debt = debt;
        context.block('Header đơn lệch sổ nợ nhưng không tự sửa được.');
        continue;
      }
      if (!mismatch && _sameFields(header, fix.fields)) continue;
      final context = contextFor(orderId)
        ..header = header
        ..debt = debt;
      context.mismatch = fix;
      context.detail(
        'Header đang ghi đã trả ${header['SoTienDaTra'] ?? 0}, còn nợ '
        '${header['SoTienConNo'] ?? 0}; sổ nợ ghi $paid / $due.',
      );
      context.action('Cập nhật lại header theo sổ nợ và tiền thừa hợp lệ.');
    }

    return _Collected(
      contexts: contexts.values.where((context) => context.hasIssue).toList(),
      checkedOrders: checked.length,
      pendingPlans: activePlans.length,
      staleLocks: contexts.values.fold(
        0,
        (sum, c) => sum + c.staleLocks.length,
      ),
      headerMismatches: contexts.values.where((c) => c.mismatch != null).length,
    );
  }

  StuckOrderScan _scanFrom(_Collected collected) {
    final issues = [for (final context in collected.contexts) context.issue];
    return StuckOrderScan(
      issues: issues,
      checkedOrders: collected.checkedOrders,
      pendingPlans: collected.pendingPlans,
      staleLocks: collected.staleLocks,
      headerMismatches: collected.headerMismatches,
      at: DateTime.now(),
    );
  }

  _HeaderFix? _correctPlanFields(
    Map<String, dynamic> header,
    Map<String, dynamic> debt,
    Map<String, dynamic> fields,
    List<String> unset,
  ) {
    final paid = fields['SoTienDaTra'] ?? debt['SoTienDaTra'];
    final due = fields['SoTienConNo'] ?? debt['SoTienConNo'];
    if (paid is! num || due is! num) return null;
    final result = Map<String, dynamic>.from(fields)
      ..['SoTienDaTra'] = paid
      ..['SoTienConNo'] = due;
    final cash = _cashFields(header, result, paid, due);
    if (cash == null) return null;
    result.addAll(cash);
    if (!_fillDates(header, result, due)) return null;
    final candidate = <String, dynamic>{...header, ...result};
    for (final key in unset) {
      candidate.remove(key);
    }
    final normalized = _normalize(candidate);
    if (normalized == null) return null;
    result.addAll(normalized);
    for (final key in unset) {
      result.remove(key);
    }
    final finalCandidate = <String, dynamic>{...header, ...result};
    for (final key in unset) {
      finalCandidate.remove(key);
    }
    if (!_headerValid(finalCandidate)) return null;
    return _HeaderFix(result, unset);
  }

  _HeaderFix? _correctMismatch(
    Map<String, dynamic> header,
    Map<String, dynamic> debt,
  ) {
    final paid = debt['SoTienDaTra'], due = debt['SoTienConNo'];
    if (paid is! num || due is! num) return null;
    final result = <String, dynamic>{'SoTienDaTra': paid, 'SoTienConNo': due};
    final cash = _cashFields(header, result, paid, due);
    if (cash == null) return null;
    result.addAll(cash);
    if (!_fillDates(header, result, due)) return null;
    final normalized = _normalize({...header, ...result});
    if (normalized == null) return null;
    result.addAll(normalized);
    if (!_headerValid({...header, ...result})) return null;
    return _HeaderFix(result, const []);
  }

  Map<String, dynamic>? _cashFields(
    Map<String, dynamic> header,
    Map<String, dynamic> fields,
    num paid,
    num due,
  ) {
    if (header['PhienBanBanHang'] != 3) return const {};
    final goods = fields['TongTienHang'] ?? header['TongTienHang'];
    final discount = fields['GiamGia'] ?? header['GiamGia'];
    final total = fields['TongThanhToan'] ?? header['TongThanhToan'];
    if (goods is! num || discount is! num || total is! num) return null;
    if (total != goods - discount || paid > total || due != total - paid) {
      return null;
    }
    final previousChange = fields['TienThua'] ?? header['TienThua'] ?? 0;
    if (previousChange is! num) return null;
    final change = paid >= total ? previousChange : 0;
    return {'SoTienKhachDua': paid + change, 'TienThua': change};
  }

  bool _fillDates(
    Map<String, dynamic> header,
    Map<String, dynamic> fields,
    num due,
  ) {
    if (header['PhienBanNgayCongNo'] != 1 || due <= 0) return true;
    final sale = fields['NgayMua'] ?? header['NgayMua'];
    if (sale is! DateTime) return false;
    final saleDay = DateTime.utc(sale.year, sale.month, sale.day);
    DateTime? valid(dynamic value) {
      if (value is! DateTime) return null;
      final date = DateTime.utc(value.year, value.month, value.day);
      return date.isBefore(saleDay) ? null : date;
    }

    fields['NgayTinhLai'] =
        valid(fields['NgayTinhLai']) ?? valid(header['NgayTinhLai']) ?? saleDay;
    final lastDay = DateTime.utc(saleDay.year, saleDay.month + 2, 0).day;
    fields['NgayHen'] =
        valid(fields['NgayHen']) ??
        valid(header['NgayHen']) ??
        DateTime.utc(
          saleDay.year,
          saleDay.month + 1,
          saleDay.day > lastDay ? lastDay : saleDay.day,
        );
    return true;
  }

  /// MongoDB's schema requires int/long for money and ids. Documents created
  /// before the validator may hold integral doubles; normalize them.
  Map<String, dynamic>? _normalize(Map<String, dynamic> candidate) {
    final result = <String, dynamic>{};
    for (final key in const [
      'IdHoaDon',
      'IdKH',
      'TongTienHang',
      'GiamGia',
      'TongThanhToan',
      'SoTienKhachDua',
      'SoTienDaTra',
      'SoTienConNo',
      'TienThua',
    ]) {
      final value = candidate[key];
      if (value == null || value is int) continue;
      if (value is double &&
          value.isFinite &&
          value == value.truncateToDouble() &&
          value.abs() <= 9007199254740991) {
        result[key] = value.toInt();
      } else {
        return null;
      }
    }
    for (final key in const ['NgayMua', 'NgayHen', 'NgayTinhLai']) {
      final value = candidate[key];
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed == null) return null;
        result[key] = parsed.toUtc();
      } else if (value != null && value is! DateTime) {
        return null;
      }
    }
    return result;
  }

  String _writeError(WriteResult result) {
    final error = result.writeError;
    Map<String, dynamic>? detail;
    for (final response in result.serverResponses) {
      final errors = response['writeErrors'];
      if (errors is List && errors.isNotEmpty && errors.first is Map) {
        detail = Map<String, dynamic>.from(errors.first as Map);
        break;
      }
    }
    final rawMessage = detail?['errmsg'] ?? error?.errmsg;
    final message = rawMessage is String
        ? rawMessage
        : 'MongoDB không xác nhận lệnh ghi.';
    final code = detail?['code'] ?? error?.code;
    final info = detail?['errInfo'];
    final suffix = info == null ? '' : ' · ${_short(info)}';
    return '$message${code == null ? '' : ' (mã $code)'}$suffix';
  }

  String _short(dynamic value) {
    final text = '$value';
    return text.length > 600 ? '${text.substring(0, 600)}…' : text;
  }

  bool _headerValid(Map<String, dynamic> doc) {
    if (doc['IdHoaDon'] is! int) return false;
    if (doc['PhienBanBanHang'] == 3) {
      final goods = doc['TongTienHang'],
          discount = doc['GiamGia'],
          total = doc['TongThanhToan'],
          cash = doc['SoTienKhachDua'],
          paid = doc['SoTienDaTra'],
          due = doc['SoTienConNo'],
          change = doc['TienThua'];
      if ([
        goods,
        discount,
        total,
        cash,
        paid,
        due,
        change,
      ].any((value) => value is! int || value < 0)) {
        return false;
      }
      if (total != goods - discount) return false;
      if (paid != (cash < total ? cash : total)) return false;
      if (due != total - paid) return false;
      if (change != cash - paid) return false;
      if (doc['MaYeuCauLuu'] is! String) return false;
      if (!['dang_luu', 'da_luu'].contains(doc['TrangThaiLuu'])) return false;
      if (doc['NgayMua'] is! DateTime) return false;
    }
    if (doc['PhienBanNgayCongNo'] == 1) {
      final due = doc['SoTienConNo'];
      if (due is! int) return false;
      if (due > 0) {
        final sale = doc['NgayMua'],
            dueDate = doc['NgayHen'],
            interest = doc['NgayTinhLai'];
        if (sale is! DateTime ||
            dueDate is! DateTime ||
            interest is! DateTime) {
          return false;
        }
        if (dueDate.isBefore(sale) || interest.isBefore(sale)) return false;
        if (doc['IdKH'] is! int) return false;
      }
    }
    for (final key in const [
      'TongTienHang',
      'GiamGia',
      'TongThanhToan',
      'SoTienKhachDua',
      'SoTienDaTra',
      'SoTienConNo',
      'TienThua',
    ]) {
      if (doc.containsKey(key) && (doc[key] is! int || (doc[key] as int) < 0)) {
        return false;
      }
    }
    for (final key in const ['NgayMua', 'NgayHen', 'NgayTinhLai']) {
      if (doc.containsKey(key) && doc[key] != null && doc[key] is! DateTime) {
        return false;
      }
    }
    return true;
  }

  bool _fieldsDiffer(Map<dynamic, dynamic> left, Map<String, dynamic> right) {
    for (final entry in right.entries) {
      final old = left[entry.key];
      if (old is DateTime && entry.value is DateTime) {
        if (old.millisecondsSinceEpoch !=
            (entry.value as DateTime).millisecondsSinceEpoch) {
          return true;
        }
      } else if (old != entry.value) {
        return true;
      }
    }
    return false;
  }

  bool _sameFields(Map<String, dynamic> header, Map<String, dynamic> fields) {
    for (final entry in fields.entries) {
      final old = header[entry.key];
      if (old is DateTime && entry.value is DateTime) {
        if (old.millisecondsSinceEpoch !=
            (entry.value as DateTime).millisecondsSinceEpoch) {
          return false;
        }
      } else if (old != entry.value) {
        return false;
      }
    }
    return true;
  }
}

class _HeaderFix {
  const _HeaderFix(this.fields, this.unset);
  final Map<String, dynamic> fields;
  final List<String> unset;
}

class _PlanFix {
  const _PlanFix({
    required this.planId,
    required this.index,
    required this.fields,
    required this.unset,
  });
  final String planId;
  final int index;
  final Map<String, dynamic> fields;
  final List<String> unset;
}

class _LockContext {
  const _LockContext(this.collection, this.id, this.orderId, this.lock);
  final String collection;
  final dynamic id;
  final int orderId;
  final String lock;
}

class _OrderContext {
  _OrderContext(this.orderId, this.header, this.debt);
  final int orderId;
  Map<String, dynamic>? header, debt;
  final List<_PlanFix> planFixes = [];
  final List<_LockContext> staleLocks = [];
  bool recoverNeeded = false;
  _HeaderFix? mismatch;
  final List<String> _details = [], _actions = [], _blockers = [];
  void detail(String value) => _details.add(value);
  void action(String value) => _actions.add(value);
  void block(String value) => _blockers.add(value);
  bool get fixable => _blockers.isEmpty && _actions.isNotEmpty;
  bool get hasIssue =>
      _details.isNotEmpty || _actions.isNotEmpty || _blockers.isNotEmpty;
  StuckOrderIssue get issue => StuckOrderIssue(
    orderId: orderId,
    title: _blockers.isNotEmpty
        ? 'Cần xử lý thủ công'
        : planFixes.isNotEmpty
        ? 'Kế hoạch sửa/xóa dở dang'
        : mismatch != null
        ? 'Header lệch sổ nợ'
        : 'Khóa còn sót',
    details: List.unmodifiable(_details),
    actions: List.unmodifiable(_actions),
    fixable: fixable,
    blocker: _blockers.isEmpty ? null : _blockers.join(' '),
  );
}

class _Collected {
  const _Collected({
    required this.contexts,
    required this.checkedOrders,
    required this.pendingPlans,
    required this.staleLocks,
    required this.headerMismatches,
  });
  final List<_OrderContext> contexts;
  final int checkedOrders, pendingPlans, staleLocks, headerMismatches;
}
