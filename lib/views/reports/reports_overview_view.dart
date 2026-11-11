import 'package:flutter/material.dart';
import '../../core/formatters/inventory_formatters.dart';
import '../../models/reports/report_models.dart';

typedef _Metric = (String, num?, bool);

class _OverviewBlock {
  const _OverviewBlock(
    this.title,
    this.kind, {
    this.summary = const [],
    this.details = const [],
    this.stockRows,
  });
  final String title;
  final ReportKind kind;
  final List<_Metric> summary, details;
  final List<List<dynamic>>? stockRows;
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

  num? _sum(Iterable<num?> values) {
    num total = 0;
    for (final value in values) {
      if (value == null) return null;
      total += value;
    }
    return total;
  }

  Widget _metric(_Metric metric) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(child: Text(metric.$1)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            metric.$2 == null
                ? 'Chưa đủ dữ liệu'
                : metric.$3
                ? money(metric.$2)
                : quantity(metric.$2!),
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  Widget _stockRow(
    String name,
    String count,
    String value, {
    bool header = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: DefaultTextStyle.merge(
      style: TextStyle(
        fontWeight: header ? FontWeight.w600 : FontWeight.normal,
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(name)),
          const SizedBox(width: 8),
          Expanded(child: Text(count, textAlign: TextAlign.right)),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: Text(value, textAlign: TextAlign.right)),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    Map<String, num?> totals(ReportKind kind) =>
        data?.sections[kind]?.totals ?? {};
    final sales = totals(ReportKind.sales),
        receipts = totals(ReportKind.receipts),
        debts = totals(ReportKind.debts),
        cash = totals(ReportKind.cash),
        pawn = totals(ReportKind.pawnDebt);
    final stockRows =
        data?.sections[ReportKind.stock]?.rows ?? <List<dynamic>>[];
    const groups = [
      ReportProductGroup.newVehicles,
      ReportProductGroup.usedVehicles,
      ReportProductGroup.parts,
      ReportProductGroup.services,
    ];
    num? groupTotal(
      Map<ReportProductGroup, ReportSection> sections,
      ReportProductGroup group,
      String key,
    ) => sections.containsKey(group) ? sections[group]!.totals[key] : 0;
    final cashCategories = data?.sections[ReportKind.cash] == null
        ? <List<dynamic>>[]
        : ReportCalculator.cashCategoryTotals(
            data!.sections[ReportKind.cash]!,
          ).rows;
    List<_Metric> aging(ReportDebtAging value) => [
      ('Trong hạn', value.within, true),
      ('Quá hạn', value.overdue, true),
      if (value.undated == null || value.undated! > 0)
        ('Chưa có ngày hẹn', value.undated, true),
    ];
    final collectedDebts = <_Metric>[
      (
        'Khách trả gốc',
        totals(ReportKind.customerRepayments)['Tiền trả nợ'],
        true,
      ),
      (
        'Lãi khách trả',
        totals(ReportKind.customerRepayments)['Lãi thực thu'],
        true,
      ),
      (
        'Khách trả nợ cũ',
        totals(ReportKind.oldDebtRepayments)['Tiền trả nợ'],
        true,
      ),
      ('Lãi nợ cũ', totals(ReportKind.oldDebtRepayments)['Lãi thực thu'], true),
    ];
    final paidDebts = <_Metric>[
      (
        'Trả nhà cung cấp',
        totals(ReportKind.supplierRepayments)['Số tiền trả'],
        true,
      ),
      (
        'Trả gốc vay vốn',
        totals(ReportKind.fundingRepayments)['Trả gốc'],
        true,
      ),
      (
        'Trả lãi vay vốn',
        totals(ReportKind.fundingRepayments)['Trả lãi'],
        true,
      ),
    ];
    final blocks = [
      _OverviewBlock(
        'Bán hàng',
        ReportKind.sales,
        summary: [
          ('Số đơn', sales['Số đơn'], false),
          ('Doanh thu', sales['Doanh thu'], true),
          ('Giá vốn', _sum([sales['Giá nhập'], sales['Chi phí']]), true),
          (
            sales['Lợi nhuận'] == null ? 'Lợi nhuận đã xác định' : 'Lợi nhuận',
            sales['Lợi nhuận'] ?? sales['Lợi nhuận đã xác định'],
            true,
          ),
          if ((sales['Đơn thiếu lợi nhuận'] ?? 0) > 0)
            (
              'Đơn chưa xác định lợi nhuận',
              sales['Đơn thiếu lợi nhuận'],
              false,
            ),
        ],
        details: [
          for (final group in groups)
            (
              group.label,
              groupTotal(
                data?.salesByGroup ??
                    const <ReportProductGroup, ReportSection>{},
                group,
                'Doanh thu',
              ),
              true,
            ),
        ],
      ),
      _OverviewBlock(
        'Nhập hàng',
        ReportKind.receipts,
        summary: [
          ('Số lô', receipts['Số lô'], false),
          ('Tiền nhập', receipts['Tiền nhập'], true),
          ('Đã trả của lô', receipts['Đã trả của lô'], true),
          ('Còn nợ của lô', receipts['Còn nợ của lô'], true),
        ],
        details: [
          for (final group in groups)
            (
              group.label,
              groupTotal(
                data?.receiptsByGroup ??
                    const <ReportProductGroup, ReportSection>{},
                group,
                'Tiền nhập',
              ),
              true,
            ),
        ],
      ),
      _OverviewBlock(
        'Tồn kho',
        ReportKind.stock,
        summary: [
          ('Tổng giá trị', _sum(stockRows.map((r) => r[2] as num?)), true),
        ],
        stockRows: stockRows,
      ),
      _OverviewBlock(
        'Khách hàng nợ',
        ReportKind.customerDebt,
        summary: [
          ('Tổng nợ', _sum([debts['Khách nợ bán hàng'], debts['Nợ cũ']]), true),
        ],
        details: [
          ('Nợ bán hàng', debts['Khách nợ bán hàng'], true),
          ('Nợ cũ', debts['Nợ cũ'], true),
          ...aging(data?.customerAging ?? const ReportDebtAging()),
        ],
      ),
      _OverviewBlock(
        'Nợ đối tác',
        ReportKind.supplierDebt,
        summary: [
          ('Tổng nợ', _sum([debts['Nợ nhà cung cấp'], debts['Vay vốn']]), true),
        ],
        details: [
          ('Nợ nhà cung cấp', debts['Nợ nhà cung cấp'], true),
          ('Vay vốn', debts['Vay vốn'], true),
        ],
      ),
      _OverviewBlock(
        'Thu chi',
        ReportKind.cash,
        summary: [('Thu', cash['Thu'], true), ('Chi', cash['Chi'], true)],
        details: [
          for (final row in cashCategories)
            ('${row[0]}', _sum([row[1] as num?, row[2] as num?]), true),
        ],
      ),
      _OverviewBlock(
        'Cầm đồ',
        ReportKind.pawn,
        summary: [
          ('Phiếu đang cầm', pawn['Phiếu đang cầm'], false),
          ('Tiền vay', pawn['Tiền vay'], true),
          ('Còn nợ', pawn['Còn nợ'], true),
          (
            'Lãi đã thu trong kỳ',
            totals(ReportKind.pawnCollections)['Lãi thực thu'],
            true,
          ),
        ],
        details: aging(data?.pawnAging ?? const ReportDebtAging()),
      ),
      _OverviewBlock(
        'Thu trả nợ',
        ReportKind.customerRepayments,
        summary: [('Tổng thu', _sum(collectedDebts.map((m) => m.$2)), true)],
        details: collectedDebts,
      ),
      _OverviewBlock(
        'Chi trả nợ',
        ReportKind.supplierRepayments,
        summary: [('Tổng chi', _sum(paidDebts.map((m) => m.$2)), true)],
        details: paidDebts,
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
              onOpen: () => onOpen(block.kind),
              summary: Column(
                key: ValueKey('overview-summary-${block.kind.name}'),
                children: [for (final metric in block.summary) _metric(metric)],
              ),
              details: block.details.isEmpty && block.stockRows == null
                  ? null
                  : Column(
                      key: ValueKey('overview-details-${block.kind.name}'),
                      children: [
                        for (final metric in block.details) _metric(metric),
                        if (block.stockRows case final rows?) ...[
                          _stockRow(
                            'Nhóm',
                            'Số lượng',
                            'Giá trị',
                            header: true,
                          ),
                          for (final row in rows)
                            _stockRow(
                              '${row[0]}',
                              row[1] == null ? '' : quantity(row[1] as num),
                              row[2] == null ? '' : money(row[2] as num),
                            ),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _OverviewCard extends StatefulWidget {
  const _OverviewCard({
    required this.block,
    required this.ready,
    required this.onOpen,
    required this.summary,
    required this.details,
  });
  final _OverviewBlock block;
  final bool ready;
  final VoidCallback onOpen;
  final Widget summary;
  final Widget? details;
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
                  child: InkWell(
                    onTap: widget.onOpen,
                    child: Text(
                      block.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF176455),
                      ),
                    ),
                  ),
                ),
                const Text(
                  'Chi tiết',
                  style: TextStyle(color: Color(0xFF65736B)),
                ),
                IconButton(
                  tooltip: 'Mở báo cáo',
                  onPressed: widget.onOpen,
                  icon: const Icon(Icons.chevron_right, size: 20),
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
                if (widget.details != null) ...[
                  Divider(
                    key: ValueKey('overview-divider-${block.kind.name}'),
                    height: 24,
                    color: const Color(0xFFE5EAED),
                  ),
                  widget.details!,
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }
}
