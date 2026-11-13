import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/formatters/inventory_formatters.dart';
import '../../models/reports/report_models.dart';

class _OverviewBlock {
  const _OverviewBlock(this.title, this.kind, {required this.summaryWidget});
  final String title;
  final ReportKind kind;
  final Widget? summaryWidget;
}

class ReportsOverviewView extends StatelessWidget {
  const ReportsOverviewView({
    super.key,
    required this.data,
    required this.onOpen,
    this.loading = false,
  });
  final ReportsData? data;
  final bool loading;
  final ValueChanged<ReportKind> onOpen;

  Widget _salesGroups(
    List<ReportProductGroup> groups,
    Map<ReportProductGroup, ReportSection> sections,
    ReportSection? sales,
    ReportCashflow cashflow,
  ) {
    const rows = [
      ('Số lượng', 'Số lượng', null),
      ('Giá bán', 'Tiền hàng', null),
      ('Giá vốn', 'Giá nhập', null),
      ('Chi phí', 'Chi phí', null),
      ('Giảm giá', 'Giảm giá', null),
      ('Lợi nhuận bán hàng', 'Lợi nhuận', null),
    ];
    final salesProfit =
        sales?.totals['Lợi nhuận'] ?? sales?.totals['Lợi nhuận đã xác định'];
    final pawnInterest = cashflow.income['Cầm đồ - lãi'];
    final otherIncome = cashflow.income['Thu khác'];
    final overallProfit =
        salesProfit == null || pawnInterest == null || otherIncome == null
        ? null
        : salesProfit + pawnInterest + otherIncome;
    return LayoutBuilder(
      builder: (context, constraints) {
        final salesTable = _profitPanel(
          'Bán hàng',
          LayoutBuilder(
            builder: (context, tableConstraints) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: tableConstraints.maxWidth,
                    ),
                    child: DataTable(
                      horizontalMargin: 12,
                      columnSpacing: 20,
                      headingRowHeight: 48,
                      dataRowMinHeight: 48,
                      dataRowMaxHeight: 56,
                      columns: [
                        const DataColumn(label: Text('')),
                        for (final group in groups)
                          DataColumn(
                            numeric: true,
                            label: Text(
                              group.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        const DataColumn(
                          numeric: true,
                          label: Text(
                            'Tổng',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                      rows: [
                        for (final (label, key, cashKey) in rows)
                          DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  label,
                                  style: TextStyle(
                                    fontWeight: _emphasizeProfitRow(label)
                                        ? FontWeight.w700
                                        : FontWeight.normal,
                                    fontSize: _emphasizeProfitRow(label)
                                        ? 15
                                        : null,
                                  ),
                                ),
                              ),
                              for (final group in groups)
                                DataCell(
                                  Text(
                                    key == null ||
                                            cashKey != null ||
                                            key == 'Tổng lợi nhuận'
                                        ? '—'
                                        : _salesGroupValue(
                                            sections[group],
                                            key,
                                          ),
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontWeight: _emphasizeProfitRow(label)
                                          ? FontWeight.w700
                                          : FontWeight.normal,
                                      fontSize: _emphasizeProfitRow(label)
                                          ? 15
                                          : null,
                                    ),
                                  ),
                                ),
                              DataCell(
                                Text(
                                  cashKey != null
                                      ? _cashValue(cashflow.income[cashKey])
                                      : key == 'Tổng lợi nhuận'
                                      ? _cashValue(overallProfit)
                                      : _salesTotalValue(sales, key!),
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontWeight: _emphasizeProfitRow(label)
                                        ? FontWeight.w700
                                        : FontWeight.normal,
                                    fontSize: _emphasizeProfitRow(label)
                                        ? 15
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 12, top: 4),
                  child: Text(
                    'Lợi nhuận đã xác định khi một số đơn thiếu dữ liệu giá vốn hoặc chi phí.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF65736B)),
                  ),
                ),
              ],
            ),
          ),
        );
        final table = Column(
          children: [
            salesTable,
            const SizedBox(height: 12),
            _profitValueTable('Cầm đồ', 'Lãi cầm đồ', pawnInterest),
            const SizedBox(height: 12),
            _profitValueTable('Thu khác', 'Thu khác', otherIncome),
            const SizedBox(height: 12),
            _profitValueTable('Lợi nhuận tổng', 'Lợi Nhuận', overallProfit),
          ],
        );
        final chart = Column(
          children: [
            _profitChart(sales, cashflow),
            const SizedBox(height: 14),
            _salesGroupChart(sections),
          ],
        );
        if (constraints.maxWidth < 1050) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [table, const SizedBox(height: 16), chart],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: table),
            const SizedBox(width: 20),
            Expanded(flex: 2, child: chart),
          ],
        );
      },
    );
  }

  bool _emphasizeProfitRow(String label) =>
      label == 'Lợi nhuận bán hàng' || label == 'Lợi Nhuận';

  Widget _profitChart(ReportSection? sales, ReportCashflow cashflow) =>
      _pieBreakdown('Biểu đồ lợi nhuận', [
        (
          'Bán hàng',
          sales?.totals['Lợi nhuận'] ?? sales?.totals['Lợi nhuận đã xác định'],
          const Color(0xFF0E8A6A),
        ),
        ('Cầm đồ', cashflow.income['Cầm đồ - lãi'], const Color(0xFF8B45C4)),
        ('Thu khác', cashflow.income['Thu khác'], const Color(0xFF2F6FE4)),
      ], lossNote: true);

  Widget _profitValueTable(String title, String label, num? amount) =>
      _profitPanel(
        title,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(child: Text(label)),
              Text(
                amount == null ? 'Chưa đủ dữ liệu' : money(amount),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _salesGroupChart(Map<ReportProductGroup, ReportSection> sections) =>
      _pieBreakdown('Doanh thu bán hàng theo nhóm', [
        (
          ReportProductGroup.newVehicles.label,
          sections[ReportProductGroup.newVehicles]?.totals['Doanh thu'],
          const Color(0xFF0E8A6A),
        ),
        (
          ReportProductGroup.usedVehicles.label,
          sections[ReportProductGroup.usedVehicles]?.totals['Doanh thu'],
          const Color(0xFFE36A1E),
        ),
        (
          ReportProductGroup.parts.label,
          sections[ReportProductGroup.parts]?.totals['Doanh thu'],
          const Color(0xFF2F6FE4),
        ),
        (
          ReportProductGroup.services.label,
          sections[ReportProductGroup.services]?.totals['Doanh thu'],
          const Color(0xFF8B45C4),
        ),
      ]);

  Widget _pieBreakdown(
    String title,
    List<(String, num?, Color)> values, {
    bool lossNote = false,
  }) {
    final slices = [
      for (final (label, amount, color) in values)
        if (amount != null && amount > 0) (label, amount, color),
    ];
    final total = slices.fold<num>(0, (sum, slice) => sum + slice.$2);
    final hasLoss =
        lossNote && values.any((item) => item.$2 != null && item.$2! < 0);
    return _profitPanel(
      title,
      Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 132,
                height: 132,
                child: slices.isEmpty
                    ? const Center(
                        child: Text(
                          'Chưa có phần dương',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : CustomPaint(
                        painter: _ProfitPiePainter([
                          for (final slice in slices) (slice.$3, slice.$2),
                        ]),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (label, amount, color) in values)
                      _profitLegend(label, amount, color, total),
                  ],
                ),
              ),
            ],
          ),
          if (hasLoss)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Khoản lợi nhuận âm không thể hiện thành lát biểu đồ.',
                style: TextStyle(fontSize: 12, color: Color(0xFF65736B)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _profitPanel(String title, Widget child) {
    final isSalesChart = title.contains('theo nhóm');
    final isChart = title.contains('Biểu đồ') || isSalesChart;
    final accent = isSalesChart || title == 'Thu khác'
        ? const Color(0xFF2F6FE4)
        : title == 'Cầm đồ'
        ? const Color(0xFF8B45C4)
        : isChart || title == 'Bán hàng' || title == 'Lợi nhuận tổng'
        ? const Color(0xFF0E8A6A)
        : const Color(0xFF65736B);
    final background = isSalesChart || title == 'Thu khác'
        ? const Color(0xFFF3F6FD)
        : title == 'Cầm đồ'
        ? const Color(0xFFF8F2FC)
        : isChart || title == 'Bán hàng' || title == 'Lợi nhuận tổng'
        ? const Color(0xFFF1F8F5)
        : const Color(0xFFFAFBFC);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: .38), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) ...[
            Text(
              title,
              style: TextStyle(fontWeight: FontWeight.w700, color: accent),
            ),
            const Divider(height: 20),
          ],
          child,
        ],
      ),
    );
  }

  Widget _profitLegend(String label, num? amount, Color color, num total) {
    final percent = amount != null && amount > 0 && total > 0
        ? (amount / total * 100).round()
        : null;
    final markerColor = amount != null && amount < 0
        ? const Color(0xFFD23B4A)
        : color;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: markerColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 6),
          Text(
            amount == null
                ? 'Chưa đủ dữ liệu'
                : '${money(amount)}${percent == null ? '' : ' · $percent%'}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  String _salesGroupValue(ReportSection? section, String key) {
    final totals = section?.totals;
    final value = key == 'Lợi nhuận'
        ? (totals?['Lợi nhuận'] ?? totals?['Lợi nhuận đã xác định'])
        : totals?[key];
    return value == null
        ? 'Chưa đủ dữ liệu'
        : key == 'Số lượng'
        ? NumberFormat.decimalPattern('vi').format(value)
        : money(value);
  }

  String _salesTotalValue(ReportSection? section, String key) {
    final totals = section?.totals;
    final value = key == 'Lợi nhuận'
        ? (totals?['Lợi nhuận'] ?? totals?['Lợi nhuận đã xác định'])
        : totals?[key];
    return key == 'Số lượng' && value != null
        ? NumberFormat.decimalPattern('vi').format(value)
        : _cashValue(value);
  }

  String _cashValue(num? value) =>
      value == null ? 'Chưa đủ dữ liệu' : money(value);

  Widget _metricSummary(List<(String, num?, bool)> metrics) => Column(
    children: [
      for (final (label, value, isMoney) in metrics)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(child: Text(label)),
              const SizedBox(width: 12),
              Text(
                value == null
                    ? 'Chưa đủ dữ liệu'
                    : isMoney
                    ? money(value)
                    : quantity(value),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _stockSummary(ReportSection? stock) {
    final rows = stock?.rows ?? const <List<dynamic>>[];
    num? totalValue;
    if (rows.every((row) => row.length > 2 && row[2] is num)) {
      totalValue = rows.fold<num>(0, (sum, row) => sum + (row[2] as num));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _metricSummary([('Tổng giá trị', totalValue, true)]),
        const Divider(height: 16),
        for (final row in rows)
          if (row.length >= 3)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(child: Text('${row[0]}')),
                  Text(row[1] is num ? quantity(row[1] as num) : '—'),
                  const SizedBox(width: 16),
                  Text(row[2] is num ? money(row[2] as num) : '—'),
                ],
              ),
            ),
      ],
    );
  }

  Widget _cashSummary(ReportCashflow cashflow) {
    num? sumPair(String principal, String interest) {
      final first = cashflow.income[principal],
          second = cashflow.income[interest];
      return first == null || second == null ? null : first + second;
    }

    final incomeRows = <(String, num?, bool)>[
      ('Bán hàng', cashflow.income['Bán hàng'], false),
      ('Cầm đồ', sumPair('Cầm đồ - gốc', 'Cầm đồ - lãi'), false),
      ('Gốc', cashflow.income['Cầm đồ - gốc'], true),
      ('Lãi', cashflow.income['Cầm đồ - lãi'], true),
      ('Thu nợ', sumPair('Thu nợ - gốc', 'Thu nợ - lãi'), false),
      ('Gốc', cashflow.income['Thu nợ - gốc'], true),
      ('Lãi', cashflow.income['Thu nợ - lãi'], true),
      ('Thu khác', cashflow.income['Thu khác'], false),
      ('Vay vốn', cashflow.income['Vay vốn'], false),
    ];
    final expenseRows = cashflow.expense.entries
        .map((entry) => (entry.key, entry.value, false))
        .toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final income = _cashPanel(
          'Thu',
          incomeRows,
          cashflow.totalIncome,
          const Color(0xFF0E8A6A),
        );
        final expense = _cashPanel(
          'Chi',
          expenseRows,
          cashflow.totalExpense,
          const Color(0xFFD23B4A),
        );
        final difference = _cashDifferencePanel(cashflow);
        if (constraints.maxWidth < 900) {
          return Column(
            children: [
              income,
              const SizedBox(height: 12),
              expense,
              const SizedBox(height: 12),
              difference,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: income),
            const SizedBox(width: 12),
            Expanded(child: expense),
            const SizedBox(width: 12),
            Expanded(child: difference),
          ],
        );
      },
    );
  }

  Widget _cashDifferencePanel(ReportCashflow cashflow) {
    const incomeColor = Color(0xFF0E8A6A);
    const expenseColor = Color(0xFFD23B4A);
    final income = cashflow.totalIncome;
    final expense = cashflow.totalExpense;
    final slices = <(Color, num)>[
      if (income != null && income > 0) (incomeColor, income),
      if (expense != null && expense > 0) (expenseColor, expense),
    ];
    final total = slices.fold<num>(0, (sum, slice) => sum + slice.$2);
    final balanceColor = cashflow.balance != null && cashflow.balance! < 0
        ? expenseColor
        : incomeColor;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF176455).withValues(alpha: .04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF176455).withValues(alpha: .2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Chênh lệch',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            cashflow.balance == null
                ? 'Chưa đủ dữ liệu'
                : money(cashflow.balance),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: balanceColor,
            ),
          ),
          const Text('Tổng thu trừ tổng chi', style: TextStyle(fontSize: 12)),
          const Divider(height: 20),
          if (total == 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('Chưa có số liệu')),
            )
          else ...[
            Row(
              children: [
                CustomPaint(
                  size: const Size.square(112),
                  painter: _ProfitPiePainter(slices),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    children: [
                      _profitLegend('Tổng thu', income, incomeColor, total),
                      _profitLegend('Tổng chi', expense, expenseColor, total),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _cashPanel(
    String title,
    List<(String, num?, bool)> amounts,
    num? total,
    Color accent,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: .22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w700, color: accent),
                ),
              ),
              Text(
                total == null ? 'Chưa đủ dữ liệu' : money(total),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const Divider(height: 20),
          if (amounts.isEmpty)
            Text('Chưa có khoản $title trong kỳ này.')
          else
            for (final (label, value, child) in amounts)
              Padding(
                padding: EdgeInsets.fromLTRB(child ? 20 : 0, 4, 0, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: child ? const Color(0xFF65736B) : null,
                          fontSize: child ? 13 : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      value != null ? money(value) : 'Chưa đủ dữ liệu',
                      style: TextStyle(
                        fontWeight: child ? FontWeight.normal : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const groups = [
      ReportProductGroup.newVehicles,
      ReportProductGroup.usedVehicles,
      ReportProductGroup.parts,
      ReportProductGroup.services,
    ];
    final blocks = [
      _OverviewBlock(
        'Lợi nhuận',
        ReportKind.sales,
        summaryWidget: KeyedSubtree(
          key: const ValueKey('overview-summary-sales'),
          child: _salesGroups(
            groups,
            data?.salesByGroup ?? const <ReportProductGroup, ReportSection>{},
            data?.sections[ReportKind.sales],
            data?.cashflow ?? const ReportCashflow(),
          ),
        ),
      ),
      _OverviewBlock(
        'Thu chi',
        ReportKind.cash,
        summaryWidget: KeyedSubtree(
          key: const ValueKey('overview-summary-cash'),
          child: _cashSummary(data?.cashflow ?? const ReportCashflow()),
        ),
      ),
      _OverviewBlock(
        'Kho hàng',
        ReportKind.stock,
        summaryWidget: KeyedSubtree(
          key: const ValueKey('overview-summary-stock'),
          child: _stockSummary(data?.sections[ReportKind.stock]),
        ),
      ),
      _OverviewBlock(
        'Cửa hàng nợ',
        ReportKind.supplierDebt,
        summaryWidget: KeyedSubtree(
          key: const ValueKey('overview-summary-shop-debt'),
          child: _metricSummary([
            (
              'Nợ nhà cung cấp',
              data?.sections[ReportKind.debts]?.totals['Nợ nhà cung cấp'],
              true,
            ),
            (
              'Vay vốn',
              data?.sections[ReportKind.debts]?.totals['Vay vốn'],
              true,
            ),
            (
              'Tổng cửa hàng nợ',
              _sumNullable([
                data?.sections[ReportKind.debts]?.totals['Nợ nhà cung cấp'],
                data?.sections[ReportKind.debts]?.totals['Vay vốn'],
              ]),
              true,
            ),
          ]),
        ),
      ),
      _OverviewBlock(
        'Khách hàng nợ',
        ReportKind.customerDebt,
        summaryWidget: KeyedSubtree(
          key: const ValueKey('overview-summary-customer-debt'),
          child: _metricSummary([
            (
              'Cầm đồ',
              data?.sections[ReportKind.pawnDebt]?.totals['Còn nợ'],
              true,
            ),
            (
              'Nợ bán hàng',
              data?.sections[ReportKind.customerDebt]?.totals['Còn nợ'],
              true,
            ),
            ('Nợ cũ', data?.sections[ReportKind.debts]?.totals['Nợ cũ'], true),
            (
              'Tổng khách hàng nợ',
              _sumNullable([
                data?.sections[ReportKind.pawnDebt]?.totals['Còn nợ'],
                data?.sections[ReportKind.customerDebt]?.totals['Còn nợ'],
                data?.sections[ReportKind.debts]?.totals['Nợ cũ'],
              ]),
              true,
            ),
          ]),
        ),
      ),
    ];
    return SingleChildScrollView(
      key: const ValueKey('reports-overview'),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          for (final block in blocks) ...[
            _OverviewCard(
              block: block,
              ready: data != null && !loading,
              summary: block.summaryWidget!,
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  num? _sumNullable(List<num?> values) {
    if (values.any((value) => value == null)) return null;
    return values.fold<num>(0, (sum, value) => sum + value!);
  }
}

class _ProfitPiePainter extends CustomPainter {
  const _ProfitPiePainter(this.slices);
  final List<(Color, num)> slices;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<num>(0, (sum, slice) => sum + slice.$2);
    if (total <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    var start = -math.pi / 2;
    for (final (color, value) in slices) {
      final sweep = 2 * math.pi * value / total;
      canvas.drawArc(bounds, start, sweep, true, Paint()..color = color);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _ProfitPiePainter oldDelegate) =>
      oldDelegate.slices != slices;
}

class _OverviewCard extends StatefulWidget {
  const _OverviewCard({
    required this.block,
    required this.ready,
    required this.summary,
  });
  final _OverviewBlock block;
  final bool ready;
  final Widget summary;
  @override
  State<_OverviewCard> createState() => _OverviewCardState();
}

class _OverviewCardState extends State<_OverviewCard> {
  bool _expanded = true;
  bool _shown = false;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _track();
  }

  @override
  void didUpdateWidget(covariant _OverviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ready != oldWidget.ready) _track();
  }

  void _track() {
    if (!widget.ready) {
      _shown = false;
      _epoch++;
      return;
    }
    if (_shown) return;
    final epoch = ++_epoch;
    Future<void>.delayed(Duration.zero, () {
      if (!mounted || epoch != _epoch) return;
      setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final block = widget.block;
    return Material(
      key: ValueKey('overview-card-${block.kind.name}'),
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE5EAED)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  key: ValueKey('overview-toggle-${block.kind.name}'),
                  tooltip: _expanded ? 'Thu gọn' : 'Mở rộng',
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ),
                Expanded(
                  child: Text(
                    block.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF176455),
                    ),
                  ),
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 12),
              if (!_shown)
                const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else ...[
                widget.summary,
              ],
            ],
          ],
        ),
      ),
    );
  }
}
