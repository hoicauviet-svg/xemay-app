import 'cash_details_screen.dart';
import '../../models/finance/cash_category.dart';
import 'cash_categories_popup.dart';
import '../../models/reports/report_models.dart';
import '../../models/finance/finance_list_report.dart';
import 'finance_list_widgets.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../controllers/finance_controller.dart';
import '../../core/formatters/inventory_formatters.dart';
import '../../models/repositories/finance_repository.dart';
import '../../services/mongo_finance_repository.dart';
import '../widgets/scrollable_data_table.dart';
import 'finance_editor_popup.dart';
import 'funding_details_screen.dart';

class FinanceTab extends StatefulWidget {
  const FinanceTab({
    super.key,
    required this.loans,
    this.repository,
    this.exportReport,
  });
  final bool loans;
  final FinanceRepository? repository;
  final FinanceReportExporter? exportReport;
  @override
  State<FinanceTab> createState() => _FinanceTabState();
}

class _FinanceTabState extends State<FinanceTab> {
  late final FinanceController _controller;
  final _search = TextEditingController();
  Timer? _debounce;
  @override
  void initState() {
    super.initState();
    _controller = FinanceController(
      widget.repository ?? MongoFinanceRepository(),
      loans: widget.loans,
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

  String _date(dynamic v) =>
      v is DateTime ? DateFormat('dd/MM/yyyy').format(v) : '';
  String _money(dynamic v) => v == null ? '' : money(v);
  ReportSection get _report => FinanceListReport.funding(
    _controller.data?.rows ?? [],
    search: _controller.search,
    status: _controller.filter,
  );
  Future<void> _add() async {
    final id = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FinanceEditorPopup(
        loans: widget.loans,
        repository: _controller.repository,
      ),
    );
    if (id != null && mounted) {
      _controller.page = 0;
      await _controller.load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.loans
                  ? 'Đã lưu khoản vay #$id'
                  : 'Đã lưu khoản thu/chi #$id',
            ),
          ),
        );
      }
    }
  }

  Future<void> _open(Map<String, dynamic> row) async {
    if (widget.loans) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => FundingDetailsScreen(
            id: (row['IdVayVon'] as num).toInt(),
            repository: _controller.repository,
          ),
        ),
      );
      if (mounted) await _controller.load();
    } else {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => CashDetailsScreen(
            id: (row['ThuChiId'] as num).toInt(),
            repository: _controller.repository,
          ),
        ),
      );
      if (mounted) await _controller.load();
    }
  }

  Future<void> _pickDates() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime(2079, 6, 6),
      initialDateRange: _controller.fromDate == null
          ? null
          : DateTimeRange(
              start: _controller.fromDate!,
              end: _controller.toDate!,
            ),
      helpText: 'Chọn khoảng ngày thu/chi',
      saveText: 'Áp dụng',
    );
    if (range != null && mounted) {
      _debounce?.cancel();
      _controller.search = _search.text;
      _controller.setDateRange(range.start, range.end);
    }
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: TextField(
                    key: ValueKey(
                      widget.loans ? 'funding-search' : 'cash-search',
                    ),
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: widget.loans
                          ? 'Tìm mã vay, đối tác, ghi chú…'
                          : 'Tìm mã thu/chi, lý do…',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: PopupMenuButton<String>(
                        tooltip: widget.loans ? 'Lọc vay vốn' : 'Lọc thu/chi',
                        icon: const Icon(Icons.filter_list),
                        initialValue: _controller.filter,
                        onSelected: (v) {
                          _debounce?.cancel();
                          _controller.search = _search.text;
                          _controller.setFilter(v);
                        },
                        itemBuilder: (_) => [
                          for (final e
                              in (widget.loans
                                      ? {
                                          'open': 'Còn nợ',
                                          'closed': 'Đã tất toán',
                                          'all': 'Tất cả',
                                        }
                                      : {
                                          'all': 'Tất cả',
                                          'income': 'Thu',
                                          'expense': 'Chi',
                                        })
                                  .entries)
                            CheckedPopupMenuItem(
                              value: e.key,
                              checked: _controller.filter == e.key,
                              child: Text(e.value),
                            ),
                        ],
                      ),
                    ),
                    onChanged: (v) {
                      _debounce?.cancel();
                      _debounce = Timer(
                        const Duration(milliseconds: 300),
                        () => _controller.updateSearch(v),
                      );
                    },
                  ),
                ),
              ),
              if (!widget.loans) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton.outlined(
                    key: const ValueKey('cash-date-filter'),
                    tooltip: 'Lọc theo ngày',
                    onPressed: _pickDates,
                    icon: const Icon(Icons.date_range_outlined),
                  ),
                ),
              ],
              const SizedBox(width: 12),
              SizedBox(
                width: 48,
                height: 48,
                child: IconButton.filled(
                  key: ValueKey(widget.loans ? 'funding-add' : 'cash-add'),
                  tooltip: widget.loans
                      ? 'Thêm khoản vay'
                      : 'Thêm khoản thu/chi',
                  onPressed: _add,
                  icon: const Icon(Icons.add),
                ),
              ),
              if (!widget.loans) ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton.outlined(
                    tooltip: 'Danh mục thu/chi',
                    icon: const Icon(Icons.category_outlined),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => CashCategoriesPopup(
                        repository: _controller.repository,
                      ),
                    ),
                  ),
                ),
              ],
              if (widget.loans &&
                  _controller.data != null &&
                  !_controller.loading &&
                  _controller.error == null) ...[
                const SizedBox(width: 12),
                SizedBox(
                  height: 48,
                  child: FinanceExcelButton(
                    key: const ValueKey('funding-export-excel'),
                    title: 'Vay vốn',
                    section: _report,
                    loadedAt: _controller.loadedAt ?? DateTime.now(),
                    exporter: widget.exportReport,
                  ),
                ),
              ],
            ],
          ),
          if (!widget.loans && _controller.fromDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: InputChip(
                label: Text(
                  '${_date(_controller.fromDate)} – ${_date(_controller.toDate)}',
                ),
                onPressed: _pickDates,
                onDeleted: () {
                  _debounce?.cancel();
                  _controller.search = _search.text;
                  _controller.setDateRange(null, null);
                },
                deleteButtonTooltipMessage: 'Bỏ lọc ngày',
              ),
            ),
          const SizedBox(height: 16),
          Expanded(child: _content()),
          if (!widget.loans &&
              _controller.data != null &&
              !_controller.loading &&
              _controller.error == null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_controller.data!.total} ${widget.loans ? 'khoản vay' : 'khoản thu/chi'}',
                    ),
                  ),
                  IconButton(
                    tooltip: 'Trang trước',
                    onPressed: _controller.page > 0
                        ? () => _controller.goToPage(_controller.page - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('${_controller.page + 1} / ${_controller.pageCount}'),
                  IconButton(
                    tooltip: 'Trang sau',
                    onPressed: _controller.page + 1 < _controller.pageCount
                        ? () => _controller.goToPage(_controller.page + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
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
    if (rows.isEmpty && !widget.loans) {
      return Center(
        child: Text(
          widget.loans
              ? 'Chưa có khoản vay phù hợp.'
              : 'Chưa có khoản thu/chi phù hợp.',
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, bounds) {
        if (bounds.maxWidth < 700) {
          return Column(
            children: [
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: rows.isEmpty
                      ? const Center(child: Text('Chưa có khoản vay phù hợp.'))
                      : ListView.separated(
                          itemCount: rows.length,
                          separatorBuilder: (_, _) => const Divider(),
                          itemBuilder: (context, i) {
                            final r = rows[i];
                            return ListTile(
                              onTap: () => _open(r),
                              title: Text(
                                widget.loans
                                    ? '#${r['IdVayVon']} · ${r['DoiTac'] ?? ''}'
                                    : '#${r['ThuChiId']} · ${r['ThuChi'] == true ? 'Thu' : 'Chi'}',
                              ),
                              subtitle: Text(
                                widget.loans
                                    ? 'Vay: ${_money(r['SoTienVay'])} · Còn nợ: ${_money(r['TongConNo'])}\nNgày vay: ${_date(r['NgayVay'])}\nNgày hẹn: ${_date(r['NgayHen'])}'
                                    : '${_date(r['NgayThang'])} · ${_money(r['SoTien'])}\n${CashCategory.nameFor(r)} · ${r['LyDo'] ?? ''}',
                              ),
                            );
                          },
                        ),
                ),
              ),
              if (widget.loans) FinanceTotalsStrip(totals: _report.totals),
            ],
          );
        }
        return ScrollableDataTable(
          fixedHeader: true,
          emptyContent: const Center(child: Text('Chưa có khoản vay phù hợp.')),
          footerRow: widget.loans
              ? DataRow(
                  cells: [
                    DataCell(const Text('Tổng')),
                    DataCell.empty,
                    DataCell(Text(_money(_report.totals['Số tiền vay']))),
                    DataCell.empty,
                    DataCell.empty,
                    DataCell(Text(_money(_report.totals['Còn nợ gốc']))),
                  ],
                )
              : null,
          fitWidth: true,
          rowHeight: widget.loans ? 80 : 64,
          columnWidths: widget.loans
              ? const [70, 200, 150, 110, 230, 150]
              : const [70, 130, 80, 170, 200, 330],
          columns: widget.loans
              ? const [
                  DataColumn(label: Text('MÃ')),
                  DataColumn(label: Text('ĐỐI TÁC CHO VAY')),
                  DataColumn(label: Text('SỐ TIỀN VAY')),
                  DataColumn(label: Text('LÃI SUẤT')),
                  DataColumn(label: Text('NGÀY THÁNG')),
                  DataColumn(label: Text('CÒN NỢ GỐC')),
                ]
              : const [
                  DataColumn(label: Text('MÃ')),
                  DataColumn(label: Text('NGÀY THÁNG')),
                  DataColumn(label: Text('THU/CHI')),
                  DataColumn(label: Text('SỐ TIỀN')),
                  DataColumn(label: Text('DANH MỤC')),
                  DataColumn(label: Text('LÝ DO')),
                ],
          rowCount: rows.length,
          rowBuilder: (index) {
            final r = rows[index];
            return DataRow(
              onSelectChanged: (_) => _open(r),
              cells: widget.loans
                  ? [
                      DataCell(Text('#${r['IdVayVon']}')),
                      DataCell(
                        Text(
                          '${r['DoiTac'] ?? ''}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DataCell(Text(_money(r['SoTienVay']))),
                      DataCell(
                        Text(
                          r['LaiSuat'] is num
                              ? '${quantity(r['LaiSuat'] as num)} %/tháng'
                              : '',
                        ),
                      ),
                      DataCell(
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ngày vay: ${_date(r['NgayVay'])}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            Text(
                              'Ngày hẹn: ${_date(r['NgayHen'])}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      DataCell(Text(_money(r['TongConNo']))),
                    ]
                  : [
                      DataCell(Text('#${r['ThuChiId']}')),
                      DataCell(Text(_date(r['NgayThang']))),
                      DataCell(
                        Text(
                          r['ThuChi'] == true
                              ? 'Thu'
                              : r['ThuChi'] == false
                              ? 'Chi'
                              : '',
                        ),
                      ),
                      DataCell(Text(_money(r['SoTien']))),
                      DataCell(Text(CashCategory.nameFor(r))),
                      DataCell(
                        Text(
                          '${r['LyDo'] ?? ''}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
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
