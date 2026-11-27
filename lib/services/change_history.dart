import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';

import '../core/app_version.dart';

/// Durable, read-only history of user edits and deletions. It references the
/// maintenance request so the original plan and backups can be inspected.
class ChangeHistory {
  static const collection = '_change_history';
  static String? _machine;

  static String get machine {
    if (_machine != null) return _machine!;
    try {
      _machine = Platform.localHostname;
    } catch (_) {
      _machine = 'khong-xac-dinh';
    }
    return _machine!;
  }

  static String get platform => Platform.operatingSystem;
  static String get appVersion => AppVersion.label;

  static String id(String requestId) => 'change:$requestId';

  static String kindLabel(String kind) => switch (kind) {
    'order' => 'đơn hàng',
    'batch' => 'lô hàng',
    'pawn' => 'phiếu cầm đồ',
    'funding' => 'phiếu vay vốn',
    'openingDebt' => 'nợ cũ',
    'cash' => 'phiếu thu/chi',
    'vehicleProduct' => 'xe',
    'partProduct' => 'phụ tùng',
    'customer' => 'khách hàng',
    'service' => 'dịch vụ',
    'partner' => 'đối tác',
    'carrier' => 'vận chuyển',
    'product' => 'sản phẩm',
    'cashCategory' => 'danh mục thu/chi',
    _ => kind,
  };

  static String summary(
    String action,
    String kind,
    dynamic parentId, {
    String? detail,
  }) {
    final label = kindLabel(kind);
    final verb = switch (action) {
      'edit' => 'Sửa',
      'delete' => 'Xóa',
      'cancel' => 'Hủy',
      'removeLine' => 'Xóa dòng',
      'deleteCost' => 'Xóa chi phí',
      'paymentEdit' => 'Sửa phiếu trả nợ',
      'paymentDelete' => 'Xóa phiếu trả nợ',
      'merge' => 'Gộp',
      _ => action,
    };
    final suffix = detail == null || detail.trim().isEmpty
        ? ''
        : ' · ${detail.trim()}';
    return '$verb $label #$parentId$suffix';
  }

  static Map<String, dynamic> entry({
    required String action,
    required String kind,
    required dynamic parentId,
    required String source,
    required String requestId,
    required String summary,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
    List<Map<String, dynamic>>? changes,
    Map<String, dynamic>? extra,
    DateTime? at,
  }) => {
    'At': at ?? DateTime.now().toUtc(),
    'Action': action,
    'Kind': kind,
    'Source': source,
    'ParentId': parentId,
    'RequestId': requestId,
    'Summary': summary,
    'Machine': machine,
    'Platform': platform,
    'AppVersion': appVersion,
    'Before': ?before,
    'After': ?after,
    'Changes': ?changes,
    ...?extra,
  };

  /// Applies the plan's header operation so the history shows the final header.
  static Map<String, dynamic>? afterFromOperations(
    Map<String, dynamic> header,
    List<Map<String, dynamic>> operations,
    String collection,
    dynamic id,
  ) {
    Map<String, dynamic>? result = Map<String, dynamic>.from(header);
    var found = false;
    for (final operation in operations) {
      if (operation['Collection'] != collection || operation['Id'] != id) {
        continue;
      }
      found = true;
      final fields = operation['Fields'];
      if (fields == null) return null;
      result.addAll(Map<String, dynamic>.from(fields as Map));
      for (final key in (operation['Unset'] as List?) ?? const []) {
        result.remove(key);
      }
    }
    return found ? result : null;
  }

  static List<Map<String, dynamic>> changes(
    List<Map<String, dynamic>> operations,
  ) => [
    for (final operation in operations)
      if (operation['Collection'] != ChangeHistory.collection)
        {
          'Collection': operation['Collection'],
          'Id': operation['Id'],
          if (operation['Fields'] == null)
            'Deleted': true
          else
            'Fields': (operation['Fields'] as Map).keys.toList(),
        },
  ];

  static Future<void> record(Db db, Map<String, dynamic> entry) async {
    final requestId = entry['RequestId'];
    if (requestId is! String) return;
    try {
      await db
          .collection(collection)
          .updateOne(
            {'_id': id(requestId)},
            {r'$setOnInsert': entry},
            upsert: true,
          );
    } catch (_) {
      // An audit failure must never block the user's change.
    }
  }

  static Future<void> recordDirect(
    Db db, {
    required String source,
    required String action,
    required String kind,
    required dynamic parentId,
    required String summary,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
    Map<String, dynamic>? extra,
  }) async {
    final requestId = ObjectId().oid;
    await record(
      db,
      entry(
        action: action,
        kind: kind,
        parentId: parentId,
        source: source,
        requestId: requestId,
        summary: summary,
        before: before,
        after: after,
        extra: extra,
      ),
    );
  }

  static Map<String, dynamic>? snapshot(Map<String, dynamic>? row) =>
      row == null ? null : Map<String, dynamic>.from(row);
}
