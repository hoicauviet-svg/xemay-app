import '../sales/sale_models.dart';

/// Frozen preview; printing never saves or reserves stock for the order.
class SalesInvoiceData {
  SalesInvoiceData({
    required SaleDraft draft,
    this.invoiceId,
    bool allowIncomplete = false,
    Set<String> blankFields = const {},
    Set<int> blankPriceLines = const {},
    Map<String, dynamic>? customer,
    Map<int, Map<String, dynamic>> vehicles = const {},
  }) : blankFields = Set.unmodifiable(blankFields),
       blankPriceLines = Set.unmodifiable(blankPriceLines),
       draft = SaleDraft.fromMap(draft.toMap()),
       customer = Map.unmodifiable({...?customer}),
       vehicles = Map.unmodifiable({
         for (final e in vehicles.entries)
           e.key: Map<String, dynamic>.unmodifiable(e.value),
       }) {
    final error = this.draft.error;
    if (!allowIncomplete && error != null) throw FormatException(error);
  }
  final Set<String> blankFields;
  final Set<int> blankPriceLines;
  final int? invoiceId;
  bool get saved => invoiceId != null;
  SalesInvoiceData asSaved(int id) => SalesInvoiceData(
    draft: draft,
    customer: customer,
    vehicles: vehicles,
    invoiceId: id,
  );
  final SaleDraft draft;
  final Map<String, dynamic> customer;
  final Map<int, Map<String, dynamic>> vehicles;
  String get customerName => '${customer['TenKhachHang'] ?? ''}'.trim();
  String get address => '${customer['DiaChiHienThi'] ?? ''}'.trim().isNotEmpty
      ? '${customer['DiaChiHienThi']}'.trim()
      : '${customer['DiaChiChiTiet'] ?? ''}'.trim();
  String get fileName => saved
      ? 'hoa-don-ban-hang-$invoiceId.pdf'
      : 'hoa-don-ban-hang-nhap-${SaleDraft.dateText(draft.date)}.pdf';
}
