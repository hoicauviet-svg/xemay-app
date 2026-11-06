import 'package:flutter/material.dart';
import '../../core/formatters/inventory_formatters.dart';
import '../../models/reports/report_models.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/scrollable_data_table.dart';

class CashCategoryReportView extends StatelessWidget {
  const CashCategoryReportView({super.key, required this.section});
  final ReportSection section;

  @override
  Widget build(BuildContext context) {
    final summary = ReportCalculator.cashCategoryTotals(section);
    return Scaffold(
      appBar: const AppTopBar(title: 'Chi tiết danh mục thu chi'),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ScrollableDataTable(
          key: const ValueKey('cash-category-summary'),
          fixedHeader: true,
          fitWidth: true,
          expandRows: true,
          columnWidths: const [400, 200],
          columns: const [
            DataColumn(label: Text('Danh mục')),
            DataColumn(label: Text('Số tiền')),
          ],
          emptyContent: const Center(child: Text('Chưa có dữ liệu phù hợp.')),
          rowCount: summary.rows.length,
          rowBuilder: (index) {
            final row = summary.rows[index];
            final amount = row[1] == null || row[2] == null
                ? null
                : (row[1] as num) + (row[2] as num);
            return DataRow(
              cells: [
                DataCell(Text('${row[0]}')),
                DataCell(Text(amount == null ? '' : money(amount))),
              ],
            );
          },
        ),
      ),
    );
  }
}
