class OrderDetails {
  const OrderDetails({
    required this.header,
    required this.customer,
    required this.lines,
    required this.debts,
    required this.payments,
  });
  final Map<String, dynamic> header;
  final Map<String, dynamic>? customer;
  final List<Map<String, dynamic>> lines, debts, payments;
  num? get paid =>
      debts.length == 1 ? debts.single['SoTienDaTra'] as num? : null;
  num? get due =>
      debts.length == 1 ? debts.single['SoTienConNo'] as num? : null;
  static num? unitPrice(Map<String, dynamic> line) =>
      (line['DonGiaHienThi'] ?? line['DonGia']) as num?;
  num? get goodsTotal =>
      header['TongTienHang'] as num? ??
      (lines.isNotEmpty &&
              lines.every((l) => unitPrice(l) != null && l['SoLuong'] is num)
          ? lines.fold<num>(
              0,
              (sum, l) => sum + unitPrice(l)! * (l['SoLuong'] as num),
            )
          : null);
  num get discount => header['GiamGia'] as num? ?? 0;
  num? get total =>
      header['TongThanhToan'] as num? ??
      (goodsTotal == null ? null : goodsTotal! - discount);
  static DateTime day(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  DateTime? get interestStart {
    final start = header['NgayTinhLai'];
    if (start is! DateTime) return null;
    var result = day(start);
    for (final payment in payments) {
      final date = payment['NgayTra'];
      if (date is DateTime &&
          (payment['LaiThu'] as num? ?? 0) > 0 &&
          day(date).isAfter(result)) {
        result = day(date);
      }
    }
    return result;
  }

  DateTime? nextAppointmentAt(DateTime today) {
    final current = header['NgayHen'];
    if (current is! DateTime) return null;
    final now = day(today);
    if (!day(current).isBefore(now)) return day(current);
    final lastDay = DateTime.utc(now.year, now.month + 2, 0).day;
    return DateTime.utc(
      now.year,
      now.month + 1,
      now.day > lastDay ? lastDay : now.day,
    );
  }

  /// Lãi 2%/tháng, quy đổi 30 ngày; tách kỳ khi có trả bớt gốc.
  int interestAt(DateTime date) {
    final start = interestStart;
    final end = day(date);
    if (start == null || due == null || due! <= 0 || !end.isAfter(start)) {
      return 0;
    }
    final repayments =
        payments
            .where(
              (p) =>
                  p['NgayTra'] is DateTime &&
                  day(p['NgayTra'] as DateTime).isAfter(start) &&
                  (p['SotienTra'] as num? ?? 0) > 0,
            )
            .toList()
          ..sort(
            (a, b) =>
                (a['NgayTra'] as DateTime).compareTo(b['NgayTra'] as DateTime),
          );
    num principal =
        due! +
        repayments.fold<num>(0, (sum, p) => sum + (p['SotienTra'] as num));
    var cursor = start;
    double accrued = 0;
    for (final payment in repayments) {
      final paidOn = day(payment['NgayTra'] as DateTime);
      if (paidOn.isAfter(end)) break;
      accrued += principal * .02 / 30 * paidOn.difference(cursor).inDays;
      principal -= payment['SotienTra'] as num;
      cursor = paidOn;
    }
    accrued += principal * .02 / 30 * end.difference(cursor).inDays;
    return accrued.round();
  }

  bool get separateTotal =>
      discount != 0 || (goodsTotal != null && total != goodsTotal);
  bool get canPay =>
      debts.length == 1 &&
      paid != null &&
      due != null &&
      due! > 0 &&
      paid! >= 0;
}

class OrderException implements Exception {
  const OrderException(this.message);
  final String message;
  @override
  String toString() => message;
}
