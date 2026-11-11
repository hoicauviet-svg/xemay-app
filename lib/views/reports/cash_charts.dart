import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/formatters/inventory_formatters.dart';

class CashCharts extends StatelessWidget {
  const CashCharts({
    super.key,
    required this.rows,
    required this.income,
    required this.expense,
  });

  final List<List<dynamic>> rows;
  final num? income, expense;

  static const incomeColor = Color(0xFF0E8A6A);
  static const expenseColor = Color(0xFFD23B4A);
  static const categoryColors = [
    Color(0xFF0E8A6A),
    Color(0xFFE36A1E),
    Color(0xFF2F6FE4),
    Color(0xFF8B45C4),
    Color(0xFFD23B4A),
    Color(0xFFC9A227),
    Color(0xFF1A9BB5),
    Color(0xFF6B7C3A),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final charts = [_split(), _categories('Thu'), _categories('Chi')];
      if (bounds.maxWidth < 980) {
        return Column(
          children: [
            for (var i = 0; i < charts.length; i++) ...[
              if (i > 0) const SizedBox(height: 4),
              charts[i],
            ],
          ],
        );
      }
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < charts.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: charts[i]),
            ],
          ],
        ),
      );
    },
  );

  Widget _split() {
    final slices = [
      ('Thu', incomeColor, income),
      ('Chi', expenseColor, expense),
    ];
    final known = [
      for (final slice in slices)
        if (slice.$3 != null && slice.$3! > 0) (slice.$2, slice.$3!),
    ];
    final total = known.fold<num>(0, (sum, slice) => sum + slice.$2);
    return _CashCard(
      chartKey: const ValueKey('cash-split-pie'),
      title: 'Thu và chi',
      child: rows.isEmpty
          ? const _CashEmpty('Chưa có phiếu thu chi.')
          : _pie(
              known: known,
              empty: 'Chưa có số tiền thu chi.',
              legends: [
                for (final slice in slices)
                  _legend(slice.$1, slice.$2, slice.$3, total),
              ],
            ),
    );
  }

  Widget _categories(String type) {
    final income = type == 'Thu';
    final totals = _categoryTotals(type);
    final names = totals.keys.toList()..sort();
    final known = [
      for (var i = 0; i < names.length; i++)
        if (totals[names[i]] != null && totals[names[i]]! > 0)
          (
            categoryColors[i % categoryColors.length],
            totals[names[i]]!,
          ),
    ];
    final total = known.fold<num>(0, (sum, slice) => sum + slice.$2);
    return _CashCard(
      chartKey: ValueKey(income ? 'cash-income-pie' : 'cash-expense-pie'),
      title: income ? 'Thu theo danh mục' : 'Chi theo danh mục',
      child: names.isEmpty
          ? _CashEmpty(income ? 'Chưa có khoản thu.' : 'Chưa có khoản chi.')
          : _pie(
              known: known,
              empty: income
                  ? 'Chưa có số tiền thu.'
                  : 'Chưa có số tiền chi.',
              legends: [
                for (var i = 0; i < names.length; i++)
                  _legend(
                    names[i],
                    categoryColors[i % categoryColors.length],
                    totals[names[i]],
                    total,
                  ),
              ],
            ),
    );
  }

  Widget _pie({
    required List<(Color, num)> known,
    required String empty,
    required List<Widget> legends,
  }) => Row(
    children: [
      SizedBox(
        width: 96,
        height: 96,
        child: known.isEmpty
            ? _CashEmpty(empty)
            : CustomPaint(painter: _CashPiePainter(known)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: legends,
        ),
      ),
    ],
  );

  Widget _legend(String label, Color color, num? value, num total) {
    final share = value == null || total == 0 ? null : value / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
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

  Map<String, num?> _categoryTotals(String type) {
    final totals = <String, num?>{};
    for (final row in rows) {
      if (row.length < 6 || row[2] != type) continue;
      final rawName = row[5];
      final name = rawName is String && rawName.trim().isNotEmpty
          ? rawName.trim()
          : type == 'Thu'
          ? 'Thu khác'
          : 'Chi khác';
      final amount = row[4];
      if (amount is! num || !amount.isFinite) {
        totals[name] = null;
      } else if (totals[name] != null || !totals.containsKey(name)) {
        totals[name] = (totals[name] ?? 0) + amount;
      }
    }
    return totals;
  }
}

class _CashCard extends StatelessWidget {
  const _CashCard({
    required this.chartKey,
    required this.title,
    required this.child,
  });

  final Key chartKey;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
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
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );
}

class _CashEmpty extends StatelessWidget {
  const _CashEmpty(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 88,
    child: Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFF6E7D83)),
      ),
    ),
  );
}

class _CashPiePainter extends CustomPainter {
  const _CashPiePainter(this.slices);
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
  bool shouldRepaint(covariant _CashPiePainter oldDelegate) =>
      oldDelegate.slices != slices;
}
