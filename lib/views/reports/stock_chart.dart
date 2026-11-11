import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/formatters/inventory_formatters.dart';

class StockValueChart extends StatelessWidget {
  const StockValueChart({super.key, required this.rows});
  final List<List<dynamic>> rows;

  static const labels = ['Xe mới', 'Xe cũ', 'Phụ tùng'];
  static const colors = [
    Color(0xFF176455),
    Color(0xFF3E8F78),
    Color(0xFFC4A35A),
  ];

  @override
  Widget build(BuildContext context) {
    final slices = [
      for (var i = 0; i < labels.length; i++)
        (labels[i], colors[i], _value(labels[i])),
    ];
    final known = [
      for (final slice in slices)
        if (slice.$3 != null && slice.$3! > 0) (slice.$2, slice.$3!),
    ];
    final total = known.fold<num>(0, (sum, slice) => sum + slice.$2);
    return Container(
      key: const ValueKey('stock-value-pie'),
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
            'Giá trị tồn kho',
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
                          'Chưa có giá trị tồn kho.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF6E7D83)),
                        ),
                      )
                    : CustomPaint(painter: _StockPiePainter(known)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final slice in slices)
                      _legend(slice.$1, slice.$2, slice.$3, total),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  num? _value(String label) {
    for (final row in rows) {
      if (row.isEmpty || row.first != label || row.length < 3) continue;
      final value = row[2];
      return value is num && value.isFinite ? value : null;
    }
    return null;
  }

  Widget _legend(String label, Color color, num? value, num total) {
    final share = value == null || total == 0 ? null : value / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
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
}

class _StockPiePainter extends CustomPainter {
  const _StockPiePainter(this.slices);
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
  bool shouldRepaint(covariant _StockPiePainter oldDelegate) =>
      oldDelegate.slices != slices;
}
