import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/formatters/inventory_formatters.dart';
import '../../models/reports/report_models.dart';

class SalesCharts extends StatelessWidget {
  const SalesCharts({
    super.key,
    required this.byGroup,
    required this.revenue,
    this.selected,
    this.onSelected,
  });
  final Map<ReportProductGroup, List<List<dynamic>>> byGroup;
  final Map<ReportProductGroup, num?> revenue;
  final ReportProductGroup? selected;
  final ValueChanged<ReportProductGroup?>? onSelected;

  static const groups = [
    ReportProductGroup.newVehicles,
    ReportProductGroup.usedVehicles,
    ReportProductGroup.parts,
    ReportProductGroup.services,
  ];
  static const colors = {
    ReportProductGroup.newVehicles: Color(0xFF0E8A6A),
    ReportProductGroup.usedVehicles: Color(0xFFE36A1E),
    ReportProductGroup.parts: Color(0xFF2F6FE4),
    ReportProductGroup.services: Color(0xFF8B45C4),
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final charts = [
        _revenueBars(compact: bounds.maxWidth < 760),
        _revenue(),
      ];
      if (bounds.maxWidth < 760) {
        return Column(
          children: [
            for (var i = 0; i < charts.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              charts[i],
            ],
          ],
        );
      }
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _revenueBars(compact: false, fill: true)),
            const SizedBox(width: 12),
            Expanded(child: _revenue(fill: true)),
          ],
        ),
      );
    },
  );

  Widget _revenueBars({required bool compact, bool fill = false}) {
    final buckets = _revenueBuckets(byGroup);
    final known = [for (final group in groups) revenue[group]].whereType<num>();
    final total = known.length == groups.length
        ? known.fold<num>(0, (sum, value) => sum + value)
        : null;
    final subtitle = total == null ? 'Chưa đủ dữ liệu' : 'Tổng: ${money(total)}';
    return _card(
      key: const ValueKey('sales-order-chart'),
      fill: fill,
      child: _revenueColumns(
        buckets,
        subtitle: subtitle,
        fill: fill,
        compact: compact,
      ),
    );
  }

  Widget _revenue({bool fill = false}) => GroupShareChart(
    chartKey: const ValueKey('sales-revenue-pie'),
    title: 'Doanh thu theo nhóm',
    emptyMessage: 'Chưa có doanh thu.',
    keyPrefix: 'sales-group',
    groups: groups,
    values: revenue,
    selected: selected,
    onSelected: onSelected,
    fill: fill,
  );

  Widget _revenueColumns(
    List<SalesRevenueBucket> buckets, {
    required String subtitle,
    required bool fill,
    required bool compact,
  }) {
    final columns = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ChartHeading(subtitle: subtitle),
        const SizedBox(width: 12),
        Expanded(
          child: buckets.isEmpty
              ? const _EmptyChart('Chưa có doanh thu trong kỳ.')
              : Column(
                  children: [
                    Expanded(
                      child: SizedBox(
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _StackedBarPainter(_stacks(buckets)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _bucketLabels(buckets),
                  ],
                ),
        ),
      ],
    );
    if (fill) return columns;
    return SizedBox(height: compact ? 156 : 168, child: columns);
  }

  Widget _bucketLabels(List<SalesRevenueBucket> buckets) {
    if (buckets.length > 8) {
      return Text(
        '${buckets.first.label} – ${buckets.last.label}',
        style: const TextStyle(fontSize: 12, color: Color(0xFF6E7D83)),
      );
    }
    return Row(
      children: [
        for (final bucket in buckets)
          Expanded(
            child: Text(
              bucket.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Color(0xFF6E7D83)),
            ),
          ),
      ],
    );
  }

  Widget _card({
    required Key key,
    required Widget child,
    bool fill = false,
  }) => Container(
    key: key,
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      color: const Color(0xFFF7FBFA),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE5EAED)),
    ),
    child: fill ? Column(children: [Expanded(child: child)]) : child,
  );
}

class _ChartHeading extends StatelessWidget {
  const _ChartHeading({required this.subtitle});
  final String subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Doanh thu',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: Color(0xFF6E7D83)),
      ),
      const SizedBox(height: 12),
      const _GroupLegend(),
    ],
  );
}

class SalesRevenueBucket {
  SalesRevenueBucket(this.label);
  final String label;
  final Map<ReportProductGroup, num?> amounts = {
    for (final group in SalesCharts.groups) group: 0,
  };

  num? get knownTotal {
    final values = amounts.values.toList();
    if (values.any((value) => value == null)) {
      final known = values.whereType<num>();
      if (known.isEmpty) return null;
      return known.fold<num>(0, (sum, value) => sum + value);
    }
    return values.fold<num>(0, (sum, value) => sum + value!);
  }
}

String revenueShare(num? value, num? total) {
  if (value == null || total == null) return '—';
  if (total == 0) return '0%';
  return '${(value / total * 100).round()}%';
}

List<SalesRevenueBucket> _revenueBuckets(
  Map<ReportProductGroup, List<List<dynamic>>> byGroup,
) {
  final dates = <DateTime>[];
  for (final rows in byGroup.values) {
    for (final row in rows) {
      if (row.length > 1 && row[1] is DateTime) dates.add(row[1] as DateTime);
    }
  }
  if (dates.isEmpty) return const [];
  dates.sort();
  final monthly = dates.last.difference(dates.first).inDays > 62;
  final buckets = <DateTime, SalesRevenueBucket>{};
  final format = DateFormat(monthly ? 'MM/yyyy' : 'dd/MM');
  for (final group in SalesCharts.groups) {
    for (final row in byGroup[group] ?? const <List<dynamic>>[]) {
      if (row.length < 2 || row[1] is! DateTime) continue;
      final date = row[1] as DateTime;
      final key = monthly
          ? DateTime(date.year, date.month)
          : DateTime(date.year, date.month, date.day);
      final bucket = buckets.putIfAbsent(
        key,
        () => SalesRevenueBucket(format.format(key)),
      );
      final revenue = row.length > 6 && row[6] is num && (row[6] as num).isFinite
          ? row[6] as num
          : null;
      if (revenue == null || bucket.amounts[group] == null) {
        bucket.amounts[group] = null;
      } else {
        bucket.amounts[group] = bucket.amounts[group]! + revenue;
      }
    }
  }
  final keys = buckets.keys.toList()..sort();
  return [for (final key in keys) buckets[key]!];
}

List<List<(Color, num)>> _stacks(List<SalesRevenueBucket> buckets) => [
  for (final bucket in buckets)
    [
      for (final group in SalesCharts.groups)
        if (bucket.amounts[group] != null && bucket.amounts[group]! > 0)
          (SalesCharts.colors[group]!, bucket.amounts[group]!),
    ],
];

class _StackedBarPainter extends CustomPainter {
  const _StackedBarPainter(this.stacks);
  final List<List<(Color, num)>> stacks;

  @override
  void paint(Canvas canvas, Size size) {
    if (stacks.isEmpty || size.width <= 0 || size.height <= 0) return;
    final totals = [
      for (final stack in stacks)
        stack.fold<num>(0, (sum, part) => sum + part.$2),
    ];
    final maxTotal = totals.fold<num>(0, (max, total) => total > max ? total : max);
    if (maxTotal <= 0) return;
    final width = size.width / stacks.length;
    final fill = Paint();
    final divider = Paint()
      ..color = const Color(0xFFF7FBFA)
      ..strokeWidth = 1;
    final scale = size.height / maxTotal;
    for (var i = 0; i < stacks.length; i++) {
      final left = i * width;
      var y = size.height;
      for (var part = 0; part < stacks[i].length; part++) {
        final height = stacks[i][part].$2 * scale;
        y -= height;
        fill.color = stacks[i][part].$1;
        canvas.drawRect(Rect.fromLTWH(left, y, width, height), fill);
        if (part < stacks[i].length - 1) {
          canvas.drawLine(
            Offset(left, y),
            Offset(left + width, y),
            divider,
          );
        }
      }
      if (i > 0) {
        final lineTop =
            size.height - math.max(totals[i], totals[i - 1]) * scale;
        canvas.drawLine(
          Offset(left, lineTop),
          Offset(left, size.height),
          divider,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StackedBarPainter oldDelegate) =>
      oldDelegate.stacks != stacks;
}

class _GroupLegend extends StatelessWidget {
  const _GroupLegend();
  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final group in SalesCharts.groups)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: SalesCharts.colors[group],
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                group.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: SalesCharts.colors[group],
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

class GroupShareChart extends StatelessWidget {
  const GroupShareChart({
    super.key,
    required this.chartKey,
    required this.title,
    required this.emptyMessage,
    required this.keyPrefix,
    required this.groups,
    required this.values,
    this.selected,
    this.onSelected,
    this.fill = false,
  });

  final Key chartKey;
  final String title, emptyMessage, keyPrefix;
  final List<ReportProductGroup> groups;
  final Map<ReportProductGroup, num?> values;
  final ReportProductGroup? selected;
  final ValueChanged<ReportProductGroup?>? onSelected;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final slices = [for (final group in groups) (group, values[group])];
    final known = [
      for (final slice in slices)
        if (slice.$2 != null && slice.$2! > 0) (slice.$1, slice.$2!),
    ];
    final total = known.fold<num>(0, (sum, slice) => sum + slice.$2);
    final chart = Row(
      children: [
        SizedBox(
          width: 96,
          height: 96,
          child: known.isEmpty
              ? _EmptyChart(emptyMessage)
              : GestureDetector(
                  onTapUp: onSelected == null
                      ? null
                      : (details) => _selectAngle(details.localPosition, known, total),
                  child: CustomPaint(
                    painter: _PiePainter([
                      for (final slice in known)
                        (SalesCharts.colors[slice.$1]!, slice.$2),
                    ]),
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final slice in slices) _legend(slice.$1, slice.$2, total),
            ],
          ),
        ),
      ],
    );
    return Container(
      key: chartKey,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBFA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5EAED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onSelected != null)
                TextButton(
                  key: ValueKey('$keyPrefix-all'),
                  onPressed: () => onSelected!(null),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: selected == null
                        ? const Color(0xFF176455)
                        : const Color(0xFF6E7D83),
                  ),
                  child: const Text('Tất cả'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (fill) Expanded(child: chart) else chart,
        ],
      ),
    );
  }

  void _selectAngle(
    Offset position,
    List<(ReportProductGroup, num)> known,
    num total,
  ) {
    const size = 96.0;
    final delta = position - const Offset(size / 2, size / 2);
    if (delta.distance > size / 2 || total <= 0) return;
    var angle = math.atan2(delta.dy, delta.dx) + math.pi / 2;
    if (angle < 0) angle += math.pi * 2;
    var cursor = 0.0;
    for (final slice in known) {
      final sweep = slice.$2 / total * math.pi * 2;
      if (angle <= cursor + sweep) {
        onSelected?.call(selected == slice.$1 ? null : slice.$1);
        return;
      }
      cursor += sweep;
    }
  }

  Widget _legend(ReportProductGroup group, num? value, num total) {
    final active = selected == group;
    final share = value == null || total == 0 ? null : value / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: active ? const Color(0xFFE7F3EF) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: ValueKey('$keyPrefix-${group.name}'),
          borderRadius: BorderRadius.circular(8),
          onTap: onSelected == null
              ? null
              : () => onSelected!(active ? null : group),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: SalesCharts.colors[group],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    group.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    value == null
                        ? 'Chưa đủ dữ liệu'
                        : share == null
                        ? money(value)
                        : '${money(value)} · ${(share * 100).round()}%',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 88,
    child: Center(
      child: Text(message, style: const TextStyle(color: Color(0xFF6E7D83))),
    ),
  );
}

class _PiePainter extends CustomPainter {
  const _PiePainter(this.slices);
  final List<(Color, num)> slices;
  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<num>(0, (sum, slice) => sum + slice.$2);
    if (total <= 0) return;
    final radius = size.shortestSide / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);
    var start = -math.pi / 2;
    for (final slice in slices) {
      final sweep = slice.$2 / total * math.pi * 2;
      final paint = Paint()..color = slice.$1;
      if ((sweep - math.pi * 2).abs() < 0.001) {
        canvas.drawCircle(center, radius, paint);
      } else {
        canvas.drawArc(rect, start, sweep.toDouble(), true, paint);
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter oldDelegate) =>
      oldDelegate.slices != slices;
}
