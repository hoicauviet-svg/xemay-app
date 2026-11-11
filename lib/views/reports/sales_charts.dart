import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/formatters/inventory_formatters.dart';
import '../../models/reports/report_models.dart';

class SalesCharts extends StatelessWidget {
  const SalesCharts({super.key, required this.orders, required this.revenue});
  final List<List<dynamic>> orders;
  final Map<ReportProductGroup, num?> revenue;

  static const groups = [
    ReportProductGroup.newVehicles,
    ReportProductGroup.usedVehicles,
    ReportProductGroup.parts,
    ReportProductGroup.services,
  ];
  static const colors = {
    ReportProductGroup.newVehicles: Color(0xFF176455),
    ReportProductGroup.usedVehicles: Color(0xFF3E8F78),
    ReportProductGroup.parts: Color(0xFFC4A35A),
    ReportProductGroup.services: Color(0xFF4C6B8A),
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final charts = [_orders(compact: bounds.maxWidth < 760), _revenue()];
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
            Expanded(child: _orders(compact: false, fill: true)),
            const SizedBox(width: 12),
            Expanded(child: _revenue(fill: true)),
          ],
        ),
      );
    },
  );

  Widget _orders({required bool compact, bool fill = false}) {
    final buckets = _orderBuckets(orders);
    final total = orders.length;
    final bars = buckets.isEmpty
        ? const _EmptyChart('Chưa có đơn trong kỳ.')
        : CustomPaint(painter: _BarPainter(buckets.map((b) => b.$2).toList()));
    return _card(
      key: const ValueKey('sales-order-chart'),
      title: 'Số đơn',
      subtitle: 'Tổng: ${quantity(total)}',
      fill: fill,
      child: buckets.isEmpty
          ? bars
          : Column(
              children: [
                fill
                    ? Expanded(
                        child: SizedBox(width: double.infinity, child: bars),
                      )
                    : SizedBox(
                        height: compact ? 44 : 88,
                        width: double.infinity,
                        child: bars,
                      ),
                const SizedBox(height: 6),
                _bucketLabels(buckets),
              ],
            ),
    );
  }

  Widget _revenue({bool fill = false}) {
    final slices = [for (final group in groups) (group, revenue[group])];
    final known = [
      for (final slice in slices)
        if (slice.$2 != null && slice.$2! > 0) (slice.$1, slice.$2!),
    ];
    return _card(
      key: const ValueKey('sales-revenue-pie'),
      title: 'Doanh thu theo nhóm',
      fill: fill,
      child: Row(
        children: [
          SizedBox(
            width: 96,
            height: 96,
            child: known.isEmpty
                ? const _EmptyChart('Chưa có doanh thu.')
                : CustomPaint(
                    painter: _PiePainter([
                      for (final slice in known) (colors[slice.$1]!, slice.$2),
                    ]),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final slice in slices) _legend(slice.$1, slice.$2, known),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(
    ReportProductGroup group,
    num? value,
    List<(ReportProductGroup, num)> known,
  ) {
    final total = known.fold<num>(0, (sum, slice) => sum + slice.$2);
    final share = value == null || total == 0 ? null : value / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: colors[group],
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              group.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
    );
  }

  Widget _bucketLabels(List<(String, int)> buckets) {
    if (buckets.length > 8) {
      return Text(
        '${buckets.first.$1} – ${buckets.last.$1}',
        style: const TextStyle(fontSize: 12, color: Color(0xFF6E7D83)),
      );
    }
    return Row(
      children: [
        for (final bucket in buckets)
          Expanded(
            child: Text(
              bucket.$1,
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
    required String title,
    required Widget child,
    String? subtitle,
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
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: Color(0xFF6E7D83)),
          ),
        ],
        const SizedBox(height: 8),
        if (fill) Expanded(child: child) else child,
      ],
    ),
  );
}

List<(String, int)> _orderBuckets(List<List<dynamic>> rows) {
  final dates = [
    for (final row in rows)
      if (row.length > 1 && row[1] is DateTime) row[1] as DateTime,
  ]..sort();
  if (dates.isEmpty) return const [];
  final monthly = dates.last.difference(dates.first).inDays > 62;
  final counts = <DateTime, int>{};
  for (final date in dates) {
    final key = monthly
        ? DateTime(date.year, date.month)
        : DateTime(date.year, date.month, date.day);
    counts[key] = (counts[key] ?? 0) + 1;
  }
  final keys = counts.keys.toList()..sort();
  final format = DateFormat(monthly ? 'MM/yyyy' : 'dd/MM');
  return [for (final key in keys) (format.format(key), counts[key]!)];
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

class _BarPainter extends CustomPainter {
  const _BarPainter(this.values);
  final List<int> values;
  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxValue = values.reduce(math.max);
    final paint = Paint()..color = const Color(0xFF176455);
    final gap = values.length == 1 ? 0.0 : 8.0;
    final width = (size.width - gap * (values.length - 1)) / values.length;
    for (var i = 0; i < values.length; i++) {
      final height = maxValue == 0 ? 0.0 : size.height * values[i] / maxValue;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          i * (width + gap),
          size.height - height,
          width.clamp(0, size.width),
          height,
        ),
        const Radius.circular(4),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter oldDelegate) =>
      oldDelegate.values != values;
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
