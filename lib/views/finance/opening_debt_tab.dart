import '../../models/reports/report_models.dart';
import '../../models/finance/finance_list_report.dart';
import 'finance_list_widgets.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../controllers/opening_debt_controller.dart';
import '../../core/formatters/inventory_formatters.dart';
import '../../models/repositories/opening_debt_repository.dart';
import '../../services/mongo_opening_debt_repository.dart';
import '../widgets/scrollable_data_table.dart';
import 'opening_debt_details_screen.dart';

class OpeningDebtTab extends StatefulWidget {
  const OpeningDebtTab({super.key, this.repository, this.exportReport});
  final OpeningDebtRepository? repository;
  final FinanceReportExporter? exportReport;
  @override
  State<OpeningDebtTab> createState() => _OpeningDebtTabState();
}

class _OpeningDebtTabState extends State<OpeningDebtTab> {
  late final OpeningDebtController _controller;
  final _search = TextEditingController();
  Timer? _debounce;
  @override
  void initState() {
    super.initState();
    _controller = OpeningDebtController(
      widget.repository ?? MongoOpeningDebtRepository(),
    );
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _controller.dispose();
    unawaited(_controller.repository.close());
    super.dispose();
  }

  String _date(dynamic value) =>
      value is DateTime ? DateFormat('dd/MM/yyyy').format(value) : '';
  ReportSection get _report => FinanceListReport.opening(
    _controller.data?.rows ?? [],
    search: _controller.search,
    status: _controller.status,
  );
  Future<void> _open(Map<String, dynamic> row) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => OpeningDebtDetailsScreen(
          id: (row['Id'] as num).toInt(),
          repository: _controller.repository,
        ),
      ),
    );
    if (mounted) await _controller.load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5EAED)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: TextField(
                    key: const ValueKey('opening-debt-search'),
                    controller: _search,
                    decoration: InputDecoration(
                      hintText:
                          'Tìm mã nợ, khách hàng, số điện thoại, ghi chú…',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: PopupMenuButton<String>(
                        tooltip: 'Lọc nợ cũ',
                        icon: const Icon(Icons.filter_list),
                        initialValue: _controller.status,
                        onSelected: (s) {
                          _debounce?.cancel();
                          _controller.filter(term: _search.text, state: s);
                        },
                        itemBuilder: (_) => [
                          for (final e in {
                            'open': 'Còn nợ',
                            'closed': 'Đã trả hết',
                            'all': 'Tất cả',
                          }.entries)
                            CheckedPopupMenuItem(
                              value: e.key,
                              checked: e.key == _controller.status,
                              child: Text(e.value),
                            ),
                        ],
                      ),
                    ),
                    onChanged: (v) {
                      _debounce?.cancel();
                      _debounce = Timer(
                        const Duration(milliseconds: 300),
                        () => _controller.filter(term: v),
                      );
                    },
                  ),
                ),
              ),
              if (_controller.data != null &&
                  !_controller.loading &&
                  _controller.error == null) ...[
                const SizedBox(width: 12),
                SizedBox(
                  height: 48,
                  child: FinanceExcelButton(
                    key: const ValueKey('opening-debt-export-excel'),
                    title: 'Nợ cũ',
                    section: _report,
                    loadedAt: _controller.loadedAt ?? DateTime.now(),
                    exporter: widget.exportReport,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Expanded(child: _content()),
        ],
      ),
    ),
  );
  Widget _content() {
    if (_controller.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_controller.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_controller.error!),
            TextButton(
              onPressed: _controller.load,
              child: const Text('Thử lại'),
            ),
          ],
        ),
      );
    }
    final rows = _controller.data?.rows ?? [];
    return LayoutBuilder(
      builder: (context, bounds) {
        if (bounds.maxWidth < 850) {
          return Column(
            children: [
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: rows.isEmpty
                      ? const Center(child: Text('Chưa có khoản nợ phù hợp.'))
                      : ListView.separated(
                          itemCount: rows.length,
                          separatorBuilder: (_, _) => const Divider(),
                          itemBuilder: (context, i) {
                            final row = rows[i],
                                customer = row['KhachHang'] as Map?;
                            return ListTile(
                              onTap: () => _open(row),
                              title: Text(
                                '#${row['Id']} · ${customer?['TenKhachHang'] ?? ''}',
                              ),
                              subtitle: Text(
                                'Tổng nợ: ${money(row['TongNo'])}\nĐã trả: ${money(row['SoTienDaTra'])} · Còn nợ: ${money(row['SoCoNo'])}\nNgày hẹn: ${_date(row['NgayHen'])}',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                            );
                          },
                        ),
                ),
              ),
              FinanceTotalsStrip(totals: _report.totals),
            ],
          );
        }
        return ScrollableDataTable(
          fixedHeader: true,
          emptyContent: const Center(child: Text('Chưa có khoản nợ phù hợp.')),
          footerRow: DataRow(
            cells: [
              DataCell(const Text('Tổng')),
              DataCell.empty,
              for (final key in ['Tổng nợ', 'Đã trả', 'Còn nợ'])
                DataCell(
                  Text(
                    _report.totals[key] == null
                        ? ''
                        : money(_report.totals[key]),
                  ),
                ),
              DataCell.empty,
            ],
          ),
          fitWidth: true,
          rowHeight: 78,
          columnWidths: const [60, 190, 120, 120, 120, 170],
          columns: const [
            DataColumn(label: Text('Mã')),
            DataColumn(label: Text('Khách hàng')),
            DataColumn(label: Text('Tổng nợ')),
            DataColumn(label: Text('Đã trả')),
            DataColumn(label: Text('Còn nợ')),
            DataColumn(label: Text('Ngày tháng')),
          ],
          rowCount: rows.length,
          rowBuilder: (index) {
            final row = rows[index];
            return DataRow(
              onSelectChanged: (_) => _open(row),
              cells: [
                DataCell(Text('${row['Id']}')),
                DataCell(
                  Text(
                    '${(row['KhachHang'] as Map?)?['TenKhachHang'] ?? ''}\n${(row['KhachHang'] as Map?)?['SoDienThoai'] ?? ''}',
                  ),
                ),
                DataCell(Text(money(row['TongNo']))),
                DataCell(Text(money(row['SoTienDaTra']))),
                DataCell(Text(money(row['SoCoNo']))),
                DataCell(
                  Text(
                    'Ngày hẹn: ${_date(row['NgayHen'])}\nTính lãi: ${_date(row['NgayTinhLai'])}',
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
