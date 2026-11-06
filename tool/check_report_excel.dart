import 'dart:io';
import 'package:xemay_app/models/reports/report_models.dart';
import 'package:xemay_app/services/report_excel_encoder.dart';

void main(List<String> args) {
  final section = ReportSection(
    columns: const [
      ReportColumn('Mã'),
      ReportColumn('Ngày'),
      ReportColumn('Khách hàng'),
      ReportColumn('Sản phẩm / dịch vụ'),
      ReportColumn('Doanh thu', money: true),
    ],
    rows: [
      for (var i = 0; i < 40; i++)
        [
          12345 + i,
          DateTime.utc(2026, 11, 4),
          'Nguyễn Văn An & <B>',
          '=SUM(A1)\nDịch vụ: Thay dầu × 2',
          i == 0 ? null : 1000.5,
        ],
    ],
    totals: const {'Số đơn': 40, 'Doanh thu': null},
    notes: const ['Giữ dữ liệu thiếu dưới dạng ô trống.'],
  );
  final bytes = ReportExcelEncoder.encode(
    ReportKind.sales,
    section,
    ReportRange(from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 4)),
    DateTime(2026, 11, 4, 12),
  );
  File(args.single).writeAsBytesSync(bytes);
  stdout.writeln(
    'Exported 40 typed voucher rows for independent compatibility check.',
  );
}
