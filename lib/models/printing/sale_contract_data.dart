import 'package:intl/intl.dart';
import '../customers/customer_models.dart';
import '../sales/sale_models.dart';
import 'pawn_contract_data.dart';
import 'sales_invoice_data.dart';

/// Print fields for the Toàn Hợp vehicle sale contract. Printing does not
/// change the order being entered.
class SaleContractData {
  SaleContractData(this.invoice);
  final SalesInvoiceData invoice;
  static const blank = '……………………';

  String get fileName => invoice.saved
      ? 'hop-dong-mua-ban-${invoice.invoiceId}.pdf'
      : 'hop-dong-mua-ban-${SaleDraft.dateText(invoice.draft.date)}.pdf';

  Map<String, String> get values {
    final draft = invoice.draft;
    final customer = invoice.customer;
    final cccd = '${customer['SoCCCD'] ?? ''}'.trim();
    final cmnd = '${customer['SoCMND'] ?? ''}'.trim();
    final paidKnown = !invoice.blankFields.contains('paid');
    final dueKnown =
        paidKnown &&
        !invoice.blankFields.contains('due') &&
        !invoice.blankFields.contains('total');
    String part(DateTime? date, int Function(DateTime) read) =>
        date == null ? '……' : '${read(date)}';
    final start = draft.date;
    final end = draft.storedDueDate;
    return {
      'day': '${start.day}',
      'month': '${start.month}',
      'year': '${start.year}',
      'buyerName': _filled(invoice.customerName),
      'phone': _filled('${customer['SoDienThoai'] ?? ''}'),
      'address': _filled(invoice.address),
      'identityNumber': _filled(cccd.isNotEmpty ? cccd : cmnd),
      'identityDate': _filled(
        CustomerDraft.formatIssueDate(customer['NgayCap']),
      ),
      'identityPlace': _filled('${customer['NoiCap'] ?? ''}'),
      'paidAmount': paidKnown ? _money(draft.collected) : blank,
      'paidWords': paidKnown ? vietnameseMoneyWords(draft.collected) : blank,
      'dueAmount': dueKnown ? _money(draft.due) : blank,
      'dueWords': dueKnown ? vietnameseMoneyWords(draft.due) : blank,
      'fromDay': part(start, (d) => d.day),
      'fromMonth': part(start, (d) => d.month),
      'fromYear': part(start, (d) => d.year),
      'toDay': part(end, (d) => d.day),
      'toMonth': part(end, (d) => d.month),
      'toYear': part(end, (d) => d.year),
      'commitment': _filled(draft.notes),
    };
  }

  /// One printed row. Each segment is followed by a dot leader, and the
  /// leaders together run to the right edge of the page.
  List<List<String>> get goodsRows {
    final rows = <List<String>>[];
    final extras = <String>[];
    for (final line in invoice.draft.lines) {
      if (line.kind == 'xe') {
        final info = line.vehicleId == null
            ? const <String, dynamic>{}
            : invoice.vehicles[line.vehicleId] ?? const {};
        final color = _first(info, const ['MauSon', 'MauSac', 'Mau']);
        rows.add(['Tên xe: ${_plain(line.name)}', 'màu sơn: ${_plain(color)}']);
        rows.add([
          'Số máy: ${_plain('${info['SoMay'] ?? ''}')}',
          'Số khung: ${_plain('${info['SoKhung'] ?? ''}')}',
          'Biển số: ${_plain('${info['BienSo'] ?? ''}')}',
        ]);
      } else if (line.name.trim().isNotEmpty) {
        extras.add('${line.name.trim()} × ${line.quantity}');
      }
    }
    if (rows.isEmpty) {
      rows.add(['Tên xe:', 'màu sơn:']);
      rows.add(['Số máy:', 'Số khung:', 'Biển số:']);
    }
    if (extras.isNotEmpty) rows.add(['Hàng kèm theo: ${extras.join('; ')}']);
    return rows;
  }

  List<String> get goodsLines => [
    for (final row in goodsRows) row.join('     '),
  ];

  static String _filled(String value) =>
      value.trim().isEmpty ? blank : value.trim();
  static String _plain(String value) => value.trim();
  static String _money(int value) =>
      NumberFormat('#,##0', 'vi_VN').format(value);
  static String _first(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = '${row[key] ?? ''}'.trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }
}
