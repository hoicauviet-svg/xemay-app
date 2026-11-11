/// Read-only report diagnosis; never opens the repositories' migration path.
import 'dart:convert';
import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/core/config/database_config.dart';
import 'package:xemay_app/models/reports/report_models.dart';

Future<void> main() async {
  final db = Db(
    Platform.environment['XEMAY_REPORT_URI'] ?? DatabaseConfig.mongoUri,
  );
  try {
    await db.open();
    final source = <String, List<Map<String, dynamic>>>{};
    for (final name in [
      'HoaDonBan',
      'ChiTietHoaDonBan',
      'Xe',
      'SoNo',
      'NhapHang',
      'SanPham',
      'TonKhoPhuTung',
      'ChiTietNhapHang',
    ]) {
      source[name] = await db.collection(name).find().toList();
    }
    final now = DateTime.now();
    final report = ReportCalculator.build(
      range: ReportRange(from: DateTime(now.year, now.month), to: now),
      source: source,
    );
    final sales = report.sections[ReportKind.sales]!;
    final price = sales.columns.indexWhere((c) => c.label == 'Giá nhập');
    final expenses = sales.columns.indexWhere((c) => c.label == 'Chi phí');
    final profit = sales.columns.indexWhere((c) => c.label == 'Lợi nhuận');
    print(
      jsonEncode({
        'totals': sales.totals,
        'missingCostOrderIds': sales.rows
            .where((r) => r[price] == null || r[expenses] == null)
            .map((r) => r.first)
            .toList(),
        'verifiedOrder': [
          for (final row in sales.rows)
            if (row.first == 152018)
              {
                'id': row.first,
                'purchase': row[price],
                'expenses': row[expenses],
                'profit': row[profit],
              },
        ],
      }),
    );
  } finally {
    if (db.isConnected) await db.close();
  }
}
