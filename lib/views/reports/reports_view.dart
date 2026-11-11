import 'reports_overview_view.dart';
import 'customer_debt_chart.dart';
import 'sales_charts.dart';
import 'stock_chart.dart';
import 'cash_category_report_view.dart';
import '../../models/dashboard/dashboard_module.dart';
import '../../services/report_excel_service.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../controllers/reports_controller.dart';
import '../../core/formatters/inventory_formatters.dart';
import '../../models/reports/report_models.dart';
import '../../models/repositories/reports_repository.dart';
import '../../services/mongo_reports_repository.dart';
import '../widgets/scrollable_data_table.dart';

class ReportsView extends StatefulWidget {
  const ReportsView({
    super.key,
    this.repository,
    this.initialKind = ReportKind.overview,
    this.exportReport,
    this.onOpenFundingLoans,
    this.onOpenOpeningDebt,
    this.onOpenProductTab,
  });
  final ReportsRepository? repository;
  final ReportKind initialKind;
  final VoidCallback? onOpenFundingLoans, onOpenOpeningDebt;
  final ValueChanged<DashboardModule>? onOpenProductTab;
  final Future<bool> Function(ReportKind, ReportSection, ReportRange, DateTime)?
  exportReport;
  @override
  State<ReportsView> createState() => _ReportsViewState();
}

class _ReportsViewState extends State<ReportsView>
    with SingleTickerProviderStateMixin {
  late final ReportsController _controller;
  late final TabController _tabs;
  bool _exporting = false;
  String _quickRange = 'month';
  ReportKind _pawnMode = ReportKind.pawnDebt;
  ReportKind _debtMode = ReportKind.debts;
  CustomerDebtTiming? _customerDebtTiming;
  ReportKind _repaymentMode = ReportKind.customerRepayments;
  static final _tabKinds = ReportKind.values
      .where(
        (kind) =>
            kind != ReportKind.pawnDebt &&
            kind != ReportKind.pawnCollections &&
            kind != ReportKind.customerDebt &&
            kind != ReportKind.supplierDebt &&
            kind != ReportKind.supplierRepayments &&
            kind != ReportKind.oldDebtRepayments &&
            kind != ReportKind.fundingRepayments,
      )
      .toList();
  @override
  void initState() {
    super.initState();
    _controller = ReportsController(
      widget.repository ?? MongoReportsRepository(),
    );
    _tabs = TabController(
      length: _tabKinds.length,
      vsync: this,
      initialIndex: _tabKinds
          .indexOf(widget.initialKind)
          .clamp(0, _tabKinds.length - 1),
    )..addListener(_tabChanged);
    unawaited(_controller.load());
  }

  void _tabChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _tabs.removeListener(_tabChanged);
    _tabs.dispose();
    _controller.dispose();
    unawaited(_controller.repository.close());
    super.dispose();
  }

  String _date(DateTime value) => DateFormat('dd/MM/yyyy').format(value);
  void _setRange(ReportRange range) {
    _controller.setRange(range);
  }

  Future<void> _pick() async {
    final range = _controller.range;
    final chosen = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime(2079, 6, 6),
      initialDateRange: range.from == null || range.to == null
          ? null
          : DateTimeRange(start: range.from!, end: range.to!),
      helpText: 'Khoảng ngày báo cáo',
      saveText: 'Áp dụng',
    );
    if (chosen != null && mounted) {
      _quickRange = 'custom';
      _setRange(ReportRange(from: chosen.start, to: chosen.end));
    }
  }

  void _preset(String value) {
    _quickRange = value;
    final now = DateTime.now();
    _setRange(switch (value) {
      'today' => ReportRange(from: now, to: now),
      'month' => ReportRange(from: DateTime(now.year, now.month), to: now),
      'previous' => ReportRange(
        from: DateTime(now.year, now.month - 1),
        to: DateTime(now.year, now.month, 0),
      ),
      'year' => ReportRange(from: DateTime(now.year), to: now),
      _ => ReportRange(),
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final tab = _tabKinds[_tabs.index];
      final kind = tab == ReportKind.pawn
          ? _pawnMode
          : tab == ReportKind.debts
          ? _debtMode
          : tab == ReportKind.customerRepayments
          ? _repaymentMode
          : tab;
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5EAED)),
        ),
        child: Column(
          children: [
            TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                for (final kind in _tabKinds)
                  Tab(
                    text: kind == ReportKind.customerRepayments
                        ? 'Trả nợ'
                        : kind.label,
                  ),
              ],
            ),
            if (tab == ReportKind.pawn ||
                tab == ReportKind.debts ||
                tab == ReportKind.customerRepayments)
              _sectionHeader(tab, kind),
            if (!_sectionReport(kind))
              Padding(padding: const EdgeInsets.all(16), child: _toolbar(kind)),
            if (kind == ReportKind.sales || kind == ReportKind.receipts)
              _productTabs(kind),
            Expanded(child: _body(kind)),
          ],
        ),
      );
    },
  );
  Widget _productTabs(ReportKind kind) {
    final groups = [
      ReportProductGroup.all,
      ReportProductGroup.newVehicles,
      ReportProductGroup.usedVehicles,
      ReportProductGroup.parts,
      if (kind == ReportKind.sales) ReportProductGroup.services,
    ];
    final current = kind == ReportKind.sales
        ? _controller.salesGroup
        : _controller.receiptsGroup;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: DefaultTabController(
        key: ValueKey('report-product-tabs-${kind.name}'),
        length: groups.length,
        initialIndex: groups.indexOf(current),
        child: TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          onTap: (index) => _controller.setProductGroup(kind, groups[index]),
          tabs: [for (final group in groups) Tab(text: group.label)],
        ),
      ),
    );
  }

  bool _sectionReport(ReportKind kind) => [
    ReportKind.debts,
    ReportKind.customerDebt,
    ReportKind.supplierDebt,
    ReportKind.pawn,
    ReportKind.pawnDebt,
    ReportKind.pawnCollections,
    ReportKind.customerRepayments,
    ReportKind.supplierRepayments,
    ReportKind.oldDebtRepayments,
    ReportKind.fundingRepayments,
  ].contains(kind);

  bool _repaymentReport(ReportKind kind) => [
    ReportKind.customerRepayments,
    ReportKind.supplierRepayments,
    ReportKind.oldDebtRepayments,
    ReportKind.fundingRepayments,
  ].contains(kind);

  Widget _sectionHeader(ReportKind tab, ReportKind kind) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                SizedBox(
                  height: 48,
                  child: SegmentedButton<ReportKind>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      padding: WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 12),
                      ),
                      visualDensity: VisualDensity.standard,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    segments: tab == ReportKind.customerRepayments
                        ? [
                            for (final entry in {
                              ReportKind.customerRepayments:
                                  'Khách hàng trả nợ',
                              ReportKind.supplierRepayments:
                                  'Trả nợ nhà cung cấp',
                              ReportKind.oldDebtRepayments: 'Khách trả nợ cũ',
                              ReportKind.fundingRepayments: 'Trả nợ vay vốn',
                            }.entries)
                              ButtonSegment(
                                value: entry.key,
                                label: SizedBox(
                                  height: 48,
                                  child: Center(
                                    widthFactor: 1,
                                    child: Text(entry.value),
                                  ),
                                ),
                              ),
                          ]
                        : tab == ReportKind.pawn
                        ? const [
                            ButtonSegment(
                              value: ReportKind.pawnDebt,
                              label: SizedBox(
                                height: 48,
                                child: Center(
                                  widthFactor: 1,
                                  child: Text('Dư nợ'),
                                ),
                              ),
                            ),
                            ButtonSegment(
                              value: ReportKind.pawn,
                              label: SizedBox(
                                height: 48,
                                child: Center(
                                  widthFactor: 1,
                                  child: Text('Phát sinh'),
                                ),
                              ),
                            ),
                            ButtonSegment(
                              value: ReportKind.pawnCollections,
                              label: SizedBox(
                                height: 48,
                                child: Center(
                                  widthFactor: 1,
                                  child: Text('Thu nợ cầm đồ'),
                                ),
                              ),
                            ),
                          ]
                        : const [
                            ButtonSegment(
                              value: ReportKind.debts,
                              label: SizedBox(
                                height: 48,
                                child: Center(
                                  widthFactor: 1,
                                  child: Text('Tổng hợp'),
                                ),
                              ),
                            ),
                            ButtonSegment(
                              value: ReportKind.customerDebt,
                              label: SizedBox(
                                height: 48,
                                child: Center(
                                  widthFactor: 1,
                                  child: Text('Khách hàng nợ'),
                                ),
                              ),
                            ),
                            ButtonSegment(
                              value: ReportKind.supplierDebt,
                              label: SizedBox(
                                height: 48,
                                child: Center(
                                  widthFactor: 1,
                                  child: Text('Nợ nhà cung cấp'),
                                ),
                              ),
                            ),
                          ],
                    selected: {kind},
                    onSelectionChanged: (value) => setState(() {
                      if (tab == ReportKind.pawn) {
                        _pawnMode = value.single;
                      } else                       if (tab == ReportKind.debts) {
                        _debtMode = value.single;
                        if (_debtMode != ReportKind.customerDebt) {
                          _customerDebtTiming = null;
                        }
                      } else {
                        _repaymentMode = value.single;
                      }
                    }),
                  ),
                ),
                if (!kind.current)
                  for (final control in _dateControls()) ...[
                    const SizedBox(width: 12),
                    control,
                  ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        _exportButton(kind),
      ],
    ),
  );

  List<Widget> _dateControls() => [
    SizedBox(
      width: 260,
      height: 48,
      child: InkWell(
        key: const ValueKey('report-date-range'),
        onTap: _controller.loading ? null : _pick,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Thời gian',
            isDense: true,
            enabled: !_controller.loading,
            suffixIcon: const Icon(Icons.date_range_outlined),
          ),
          child: Text(
            _controller.range.from == null
                ? 'Tất cả thời gian'
                : '${_date(_controller.range.from!)} – ${_date(_controller.range.to!)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    ),
    Tooltip(
      message: 'Chọn nhanh thời gian',
      child: SizedBox(
        width: 180,
        height: 48,
        child: DropdownButtonFormField<String>(
          key: ValueKey('report-quick-range-$_quickRange'),
          initialValue: _quickRange,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Chọn nhanh',
            isDense: true,
          ),
          items: [
            for (final e in {
              'today': 'Hôm nay',
              'month': 'Tháng này',
              'previous': 'Tháng trước',
              'year': 'Năm nay',
              'all': 'Tất cả thời gian',
            }.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
            const DropdownMenuItem(
              value: 'custom',
              enabled: false,
              child: Text('Tùy chọn'),
            ),
          ],
          onChanged: _controller.loading
              ? null
              : (value) {
                  if (value != null) _preset(value);
                },
        ),
      ),
    ),
  ];

  Widget _toolbar(ReportKind kind) {
    final controls = Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!kind.current) ..._dateControls(),
        if (kind == ReportKind.cash)
          SizedBox(
            width: 160,
            height: 48,
            child: DropdownButtonFormField<String>(
              key: const ValueKey('report-cash-type'),
              initialValue: _controller.cashType,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Loại phiếu',
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Tất cả')),
                DropdownMenuItem(value: 'income', child: Text('Thu')),
                DropdownMenuItem(value: 'expense', child: Text('Chi')),
              ],
              onChanged: _controller.loading
                  ? null
                  : (value) {
                      if (value != null) _controller.setCashType(value);
                    },
            ),
          ),
        if (kind == ReportKind.cash)
          SizedBox(
            width: 240,
            height: 48,
            child: DropdownButtonFormField<String>(
              key: ValueKey(
                'report-cash-category-${_controller.cashType}-${_controller.cashCategory}',
              ),
              initialValue: _controller.cashCategory ?? '',
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Danh mục',
                isDense: true,
              ),
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text(
                    _controller.cashType == 'all'
                        ? 'Chọn loại phiếu trước'
                        : 'Tất cả danh mục',
                  ),
                ),
                for (final name in _controller.cashCategories)
                  DropdownMenuItem(value: name, child: Text(name)),
              ],
              onChanged: _controller.loading || _controller.cashType == 'all'
                  ? null
                  : (v) => _controller.setCashCategory(v == '' ? null : v),
            ),
          ),
        if (!_sectionReport(kind))
          IconButton(
            tooltip: 'Cập nhật báo cáo',
            onPressed: _controller.loading
                ? null
                : () {
                    _controller.load();
                  },
            icon: const Icon(Icons.refresh),
          ),
      ],
    );
    if (kind == ReportKind.overview) {
      return Align(alignment: Alignment.centerLeft, child: controls);
    }
    if (_sectionReport(kind)) return controls;
    return LayoutBuilder(
      builder: (context, bounds) {
        if (bounds.maxWidth < 700) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              controls,
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: _exportButton(kind),
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: controls),
            const SizedBox(width: 12),
            _exportButton(kind),
          ],
        );
      },
    );
  }

  Widget _body(ReportKind kind) {
    if (kind == ReportKind.overview &&
        (_controller.loading || _controller.data != null)) {
      return ReportsOverviewView(
        data: _controller.data,
        loading: _controller.loading,
        onOpen: (target) {
          if (target == ReportKind.sales || target == ReportKind.receipts) {
            _controller.setProductGroup(target, ReportProductGroup.all);
          }
          if (target == ReportKind.cash) _controller.setCashType('all');
          if (target == ReportKind.pawn) _pawnMode = ReportKind.pawnDebt;
          final debtTarget = [
            ReportKind.debts,
            ReportKind.customerDebt,
            ReportKind.supplierDebt,
          ].contains(target);
          if (debtTarget) {
            _debtMode = target;
            if (target != ReportKind.customerDebt) _customerDebtTiming = null;
          }
          if (_repaymentReport(target)) _repaymentMode = target;
          final index = _tabKinds.indexOf(
            _repaymentReport(target)
                ? ReportKind.customerRepayments
                : debtTarget
                ? ReportKind.debts
                : target,
          );
          if (index >= 0) _tabs.animateTo(index);
        },
      );
    }
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
    final section = _controller.section(kind);
    if (section == null) return const SizedBox.shrink();
    final rows = section.rows;
    final timing = kind == ReportKind.customerDebt
        ? _customerDebtTiming
        : null;
    final listed = timing == null
        ? rows
        : [
            for (final row in rows)
              if (customerDebtTiming(row) == timing) row,
          ];
    final shown = timing == null
        ? section
        : ReportSection(
            columns: section.columns,
            rows: listed,
            totals: {
              'Tổng thanh toán': _moneyColumn(listed, 5),
              'Đã thu': _moneyColumn(listed, 6),
              'Còn nợ': _moneyColumn(listed, 7),
            },
            notes: section.notes,
          );
    final footer = _footer(kind, shown);
    final groups = _groups(kind, section);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (kind == ReportKind.sales) ...[
            SalesCharts(
              orders:
                  _controller.data?.sections[ReportKind.sales]?.rows ??
                  const [],
              revenue: {
                for (final group in SalesCharts.groups)
                  group: _controller
                      .data
                      ?.salesByGroup[group]
                      ?.totals['Doanh thu'],
              },
            ),
          ],
          if (kind == ReportKind.stock) ...[
            StockValueChart(rows: rows),
            const SizedBox(height: 12),
          ],
          if (kind == ReportKind.customerDebt) ...[
            CustomerDebtAgingChart(
              rows: rows,
              selected: _customerDebtTiming,
              onSelected: (value) =>
                  setState(() => _customerDebtTiming = value),
            ),
            const SizedBox(height: 12),
          ],
          if (kind == ReportKind.sales)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '${section.totals['Lợi nhuận'] == null ? 'Lợi nhuận đã xác định' : 'Lợi nhuận'}: ${section.totals['Lợi nhuận'] == null && section.totals['Lợi nhuận đã xác định'] == null ? 'Chưa đủ dữ liệu giá vốn / chi phí' : money(section.totals['Lợi nhuận'] ?? section.totals['Lợi nhuận đã xác định'])}${(section.totals['Đơn thiếu lợi nhuận'] ?? 0) > 0 ? ' · ${section.totals['Đơn thiếu lợi nhuận']} đơn chưa đủ dữ liệu' : ''}',
                key: const ValueKey('sales-profit-summary'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, bounds) {
                if (bounds.maxWidth < 700) {
                  return Column(
                    children: [
                      Expanded(
                        child: listed.isEmpty
                            ? Center(child: Text(_emptyMessage(kind)))
                            : Material(
                                color: Colors.transparent,
                                child: ListView.separated(
                                  itemCount: listed.length,
                                  separatorBuilder: (_, _) => const Divider(),
                                  itemBuilder: (context, i) => InkWell(
                                    onTap: _rowAction(kind, listed[i]),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _cell(
                                              listed[i][0],
                                              section.columns.first,
                                            ),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          for (
                                            var c = 1;
                                            c < section.columns.length;
                                            c++
                                          )
                                            Text(
                                              '${section.columns[c].label}: ${_cell(listed[i][c], section.columns[c])}',
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                      if (footer != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          color: const Color(0xFFF0F6F3),
                          child: Wrap(
                            spacing: 20,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              for (var i = 1; i < footer.length; i++)
                                if (footer[i].isNotEmpty)
                                  Text(
                                    kind == ReportKind.cash
                                        ? footer[i]
                                        : '${section.columns[i].label}: ${footer[i]}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF176455),
                                    ),
                                  ),
                              if (kind == ReportKind.cash)
                                _cashCategoryButton(section),
                            ],
                          ),
                        ),
                    ],
                  );
                }
                return ScrollableDataTable(
                  fixedHeader: true,
                  emptyContent: Center(child: Text(_emptyMessage(kind))),
                  expandRows:
                      kind == ReportKind.sales ||
                      kind == ReportKind.receipts ||
                      kind == ReportKind.pawnDebt ||
                      kind == ReportKind.customerDebt ||
                      kind == ReportKind.supplierDebt ||
                      _repaymentReport(kind),
                  fitWidth: true,
                  columnWidths: [for (final group in groups) group.width],
                  columns: [
                    for (final group in groups)
                      DataColumn(label: Text(group.label)),
                  ],
                  footerRow: footer == null
                      ? null
                      : DataRow(
                          cells: [
                            for (final group in groups)
                              DataCell(
                                kind == ReportKind.cash &&
                                        group.indices.last ==
                                            section.columns.length - 1
                                    ? _cashCategoryButton(section)
                                    : _groupCell(
                                        section,
                                        group,
                                        footer,
                                        footer: true,
                                      ),
                              ),
                          ],
                        ),
                  rowCount: listed.length,
                  rowBuilder: (index) => DataRow(
                    onSelectChanged: _rowAction(kind, listed[index]) == null
                        ? null
                        : (_) => _rowAction(kind, listed[index])!(),
                    cells: [
                      for (final group in groups)
                        DataCell(_groupCell(section, group, listed[index])),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _cashCategoryButton(ReportSection section) => OutlinedButton(
    key: const ValueKey('cash-category-details'),
    onPressed: () => Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CashCategoryReportView(section: section),
      ),
    ),
    child: const Text('Xem chi tiết danh mục'),
  );

  List<_ReportGroup> _groups(ReportKind kind, ReportSection section) {
    if (_repaymentReport(kind)) {
      final remaining = kind == ReportKind.supplierRepayments ? 5 : 6;
      return [
        _ReportGroup('Phiếu trả nợ', 170, [0, 1]),
        _ReportGroup('Chứng từ / Đối tác', 280, [2, 3]),
        _ReportGroup('Thanh toán', 260, [4, if (remaining == 6) 5]),
        _ReportGroup('Số dư / Ghi chú', 250, [
          remaining,
          if (section.columns.length > remaining + 1) remaining + 1,
        ]),
      ];
    }
    if (kind == ReportKind.customerDebt || kind == ReportKind.supplierDebt) {
      return [
        _ReportGroup(
          kind == ReportKind.customerDebt ? 'Đơn bán' : 'Lô nhập',
          180,
          [0, 1],
        ),
        _ReportGroup(
          kind == ReportKind.customerDebt ? 'Khách hàng' : 'Nhà cung cấp',
          350,
          [2, 3, 4],
        ),
        _ReportGroup('Thanh toán', 260, [5, 6, 7]),
        _ReportGroup('Ngày hẹn / Quá hạn', 210, [8, 9]),
      ];
    }
    if (kind != ReportKind.sales) {
      return [
        for (var i = 0; i < section.columns.length; i++)
          _ReportGroup(section.columns[i].label, section.columns[i].width, [i]),
      ];
    }
    int index(String label) =>
        section.columns.indexWhere((c) => c.label == label);
    return [
      _ReportGroup('Đơn hàng', 220, [
        index('Mã'),
        index('Ngày'),
        index('Khách hàng'),
      ]),
      _ReportGroup('Sản phẩm / dịch vụ', 300, [index('Sản phẩm / dịch vụ')]),
      _ReportGroup('Bán hàng', 210, [
        index('Tiền hàng'),
        index('Giảm giá'),
        index('Doanh thu'),
      ]),
      _ReportGroup('Giá vốn', 190, [index('Giá nhập'), index('Chi phí')]),
      _ReportGroup('Thanh toán', 190, [index('Đã thu'), index('Còn nợ')]),
      _ReportGroup('Lợi nhuận', 150, [index('Lợi nhuận')]),
    ];
  }

  Widget _groupCell(
    ReportSection section,
    _ReportGroup group,
    List<dynamic> values, {
    bool footer = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final index in group.indices)
          if (!footer || '${values[index]}'.isNotEmpty)
            Text(
              '${group.indices.length > 1 && (!footer || index != 0) ? '${section.columns[index].label}: ' : ''}${footer ? values[index] : _cell(values[index], section.columns[index])}',
              key: footer
                  ? ValueKey('report-total-${section.columns[index].label}')
                  : null,
              style:
                  !footer &&
                      group.label == 'Lợi nhuận' &&
                      values[index] is num &&
                      (values[index] as num) < 0
                  ? const TextStyle(color: Color(0xFFB5473D))
                  : null,
            ),
      ],
    );
  }

  VoidCallback? _rowAction(ReportKind kind, List<dynamic> row) {
    if (kind == ReportKind.stock && widget.onOpenProductTab != null) {
      final module = switch (row.first) {
        'Xe mới' => DashboardModule.newVehicles,
        'Xe cũ' => DashboardModule.usedVehicles,
        'Phụ tùng' => DashboardModule.parts,
        _ => null,
      };
      return module == null ? null : () => widget.onOpenProductTab!(module);
    }
    if (kind != ReportKind.debts) return null;
    return switch (row.first) {
      'Vay vốn' => widget.onOpenFundingLoans,
      'Nợ cũ' => widget.onOpenOpeningDebt,
      'Khách nợ bán hàng' => () => setState(
        () => _debtMode = ReportKind.customerDebt,
      ),
      'Nợ nhà cung cấp' => () => setState(
        () => _debtMode = ReportKind.supplierDebt,
      ),
      _ => null,
    };
  }

  Widget _exportButton(ReportKind kind) {
    final section = _controller.section(kind);
    return FilledButton.icon(
      key: const ValueKey('report-export-excel'),
      onPressed:
          _exporting ||
              _controller.loading ||
              _controller.error != null ||
              section == null
          ? null
          : () => _export(kind, section),
      icon: _exporting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.download_outlined),
      label: Text(_exporting ? 'Đang xuất…' : 'Xuất Excel'),
    );
  }

  num? _moneyColumn(List<List<dynamic>> rows, int index) {
    var sum = 0.0;
    for (final row in rows) {
      final value = index < row.length ? row[index] : null;
      if (value is! num || !value.isFinite) return null;
      sum += value;
    }
    return sum;
  }

  String _emptyMessage(ReportKind kind) {
    final timing = kind == ReportKind.customerDebt
        ? _customerDebtTiming
        : null;
    return switch (timing) {
      CustomerDebtTiming.within => 'Chưa có khoản trong hạn.',
      CustomerDebtTiming.overdue => 'Chưa có khoản quá hạn.',
      CustomerDebtTiming.undated => 'Chưa có khoản chưa có ngày hẹn.',
      null => 'Chưa có dữ liệu trong khoảng thời gian này.',
    };
  }

  List<String>? _footer(ReportKind kind, ReportSection section) {
    // These reports already show separate balances by category in their rows.
    if (kind == ReportKind.stock || kind == ReportKind.debts) return null;
    return [
      for (var i = 0; i < section.columns.length; i++)
        i == 0
            ? 'Tổng'
            : kind == ReportKind.cash && section.columns[i].label == 'Số tiền'
            ? section.totals.entries
                  .map(
                    (entry) =>
                        '${entry.key}: ${_total(entry.value, kind, entry.key)}',
                  )
                  .join('\n')
            : section.totals.containsKey(section.columns[i].label)
            ? _total(
                section.totals[section.columns[i].label],
                kind,
                section.columns[i].label,
              )
            : '',
    ];
  }

  Future<void> _export(ReportKind kind, ReportSection section) async {
    final loadedAt = _controller.data!.loadedAt;
    final range = _controller.range;
    setState(() => _exporting = true);
    try {
      final saved = await (widget.exportReport ?? ReportExcelService.save)(
        kind,
        section,
        range,
        loadedAt,
      );
      if (saved && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Xuất Excel thành công')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chưa xuất được Excel. Vui lòng thử lại.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _cell(dynamic value, ReportColumn column) {
    if (value == null) return '';
    if (value is DateTime) return _date(value);
    if (column.label.startsWith('Mã')) return '$value';
    if (value is num) {
      return column.money
          ? money(value)
          : NumberFormat.decimalPattern('vi').format(value);
    }
    return '$value';
  }

  String _total(num? value, ReportKind kind, String label) {
    if (value == null) return '';
    final count =
        kind == ReportKind.stock ||
        [
          'Số đơn',
          'Số lô',
          'Số lượng',
          'Phiếu mới',
          'Phiếu đang cầm',
        ].contains(label);
    return count
        ? NumberFormat.decimalPattern('vi').format(value)
        : money(value);
  }
}

class _ReportGroup {
  const _ReportGroup(this.label, this.width, this.indices);
  final String label;
  final double width;
  final List<int> indices;
}
