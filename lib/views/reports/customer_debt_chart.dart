import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/formatters/inventory_formatters.dart';

enum CustomerDebtTiming { within, overdue, undated }

CustomerDebtTiming customerDebtTiming(List<dynamic> row) {
  if (row.length < 9 || row[8] is! DateTime) return CustomerDebtTiming.undated;
  final days = row.length > 9 ? row[9] : null;
  return days is num && days > 0
      ? CustomerDebtTiming.overdue
      : CustomerDebtTiming.within;
}

class CustomerDebtAgingChart extends StatelessWidget {
  const CustomerDebtAgingChart({
    super.key,
    required this.rows,
    required this.selected,
    required this.onSelected,
  });
  final List<List<dynamic>> rows;
  final CustomerDebtTiming? selected;
  final ValueChanged<CustomerDebtTiming?> onSelected;

  static const _order = [
    CustomerDebtTiming.within,
    CustomerDebtTiming.overdue,
    CustomerDebtTiming.undated,
  ];
  static const _labels = {
    CustomerDebtTiming.within: 'Trong hạn',
    CustomerDebtTiming.overdue: 'Quá hạn',
    CustomerDebtTiming.undated: 'Chưa có ngày hẹn',
  };
  static const _colors = {
    CustomerDebtTiming.within: Color(0xFF0E8A6A),
    CustomerDebtTiming.overdue: Color(0xFFD23B4A),
    CustomerDebtTiming.undated: Color(0xFFC9A227),
  };

  @override
  Widget build(BuildContext context) {
    final slices = [
      for (final timing in _order)
        if (timing != CustomerDebtTiming.undated || _amount(timing) != 0)
          (timing, _amount(timing)),
    ];
    final known = [
      for (final slice in slices)
        if (slice.$2 > 0) slice,
    ];
    final total = known.fold<num>(0, (sum, slice) => sum + slice.$2);
    return Container(
      key: const ValueKey('customer-debt-aging'),
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
          const Text(
            'Hạn nợ',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 96,
                height: 96,
                child: known.isEmpty
                    ? const Center(
                        child: Text(
                          'Chưa có khoản nợ.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF6E7D83)),
                        ),
                      )
                    : GestureDetector(
                        onTapUp: (details) => _selectAngle(details.localPosition, known, total),
                        child: CustomPaint(
                          painter: _DebtPiePainter([
                            for (final slice in known)
                              (_colors[slice.$1]!, slice.$2),
                          ]),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final slice in slices)
                      _legend(slice.$1, slice.$2, total),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  num _amount(CustomerDebtTiming timing) {
    var sum = 0.0;
    for (final row in rows) {
      if (customerDebtTiming(row) != timing || row.length < 8) continue;
      final due = row[7];
      if (due is num && due.isFinite) sum += due;
    }
    return sum;
  }

  void _selectAngle(
    Offset position,
    List<(CustomerDebtTiming, num)> known,
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
        onSelected(selected == slice.$1 ? null : slice.$1);
        return;
      }
      cursor += sweep;
    }
  }

  Widget _legend(CustomerDebtTiming timing, num amount, num total) {
    final active = selected == timing;
    final share = total == 0 ? null : amount / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: active ? const Color(0xFFE7F3EF) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: ValueKey('customer-debt-${timing.name}'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => onSelected(active ? null : timing),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _colors[timing],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _labels[timing]!,
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
                    share == null
                        ? money(amount)
                        : '${money(amount)} · ${(share * 100).round()}%',
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

class _DebtPiePainter extends CustomPainter {
  const _DebtPiePainter(this.slices);
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
  bool shouldRepaint(covariant _DebtPiePainter oldDelegate) =>
      oldDelegate.slices != slices;
}
