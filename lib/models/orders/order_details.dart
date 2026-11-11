import '../sales/sale_models.dart';
import '../printing/sales_invoice_data.dart';

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

  /// Reprint of this saved order. Collected money and debt follow the ledger.
  SalesInvoiceData toInvoice(int orderId) {
    final lines = <SaleLine>[];
    final vehicles = <int, Map<String, dynamic>>{};
    for (final line in this.lines) {
      final kind = _lineKind(line);
      final vehicleId = _intOrNull(line['IdXe']);
      final productId = _intOrNull(line['IdSanPham']);
      final serviceId = '${line['IdDichVu'] ?? ''}'.trim();
      final quantity = _intOrNull(line['SoLuong']) ?? 1;
      final price = _intOrNull(line['DonGiaHienThi'] ?? line['DonGia']) ?? 0;
      lines.add(
        SaleLine(
          kind: kind,
          name: '${line['TenSanPham'] ?? ''}',
          quantity: quantity < 1 ? 1 : quantity,
          price: price < 0 ? 0 : price,
          productId: kind == 'dich_vu' ? null : productId,
          vehicleId: kind == 'xe' ? vehicleId : null,
          serviceId: kind == 'dich_vu'
              ? (serviceId.isEmpty ? 'dich-vu' : serviceId)
              : null,
        ),
      );
      if (kind == 'xe' && vehicleId != null) {
        vehicles[vehicleId] = {
          'SoKhung': line['SoKhung'],
          'SoMay': line['SoMay'],
          'BienSo': line['BienSo'],
          'MauSon': line['MauSon'] ?? line['MauSac'] ?? line['Mau'],
        };
      }
    }
    final discountAmount = _intOrNull(discount) ?? 0;
    final subtotal = lines.fold<int>(0, (sum, line) => sum + line.total);
    final safeDiscount = discountAmount < 0 || discountAmount > subtotal
        ? 0
        : discountAmount;
    final invoiceTotal = subtotal - safeDiscount;
    final recordedDue = _intOrNull(due);
    final recordedPaid =
        _intOrNull(paid) ?? _intOrNull(header['SoTienKhachDua']);
    final collectedAmount =
        recordedDue != null && recordedDue >= 0 && recordedDue <= invoiceTotal
        ? invoiceTotal - recordedDue
        : (recordedPaid ?? 0).clamp(0, invoiceTotal).toInt();
    final owes = invoiceTotal - collectedAmount;
    final sold = header['NgayMua'];
    return SalesInvoiceData(
      allowIncomplete: true,
      invoiceId: orderId,
      draft: SaleDraft(
        lines: lines,
        date: sold is DateTime ? sold : DateTime.now(),
        discount: safeDiscount,
        paid: collectedAmount,
        customerId: _intOrNull(header['IdKH'] ?? customer?['IdKH']),
        paymentDueDate: owes > 0 && header['NgayHen'] is DateTime
            ? header['NgayHen'] as DateTime
            : null,
        interestDate: owes > 0 && header['NgayTinhLai'] is DateTime
            ? header['NgayTinhLai'] as DateTime
            : null,
        notes: '${header['GhiChu'] ?? ''}',
      ),
      customer: customer ?? const {},
      vehicles: vehicles,
    );
  }

  static String _lineKind(Map<String, dynamic> line) {
    final kind = '${line['LoaiSanPham'] ?? ''}'.trim();
    if (kind == 'xe' || kind == 'phu_tung' || kind == 'dich_vu') return kind;
    if (line['IdXe'] != null) return 'xe';
    if ('${line['IdDichVu'] ?? ''}'.trim().isNotEmpty) return 'dich_vu';
    return 'phu_tung';
  }

  static int? _intOrNull(dynamic value) {
    if (value is int) return value;
    if (value is num && value.isFinite) return value.round();
    return null;
  }

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
