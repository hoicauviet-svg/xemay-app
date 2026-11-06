class CashCategory {
  const CashCategory(this.id, this.name, this.income);
  final String id, name;
  final bool income;
  Map<String, dynamic> toFields() => {
    '_id': id,
    'TenDanhMuc': name,
    'ThuChi': income,
    'HoatDong': true,
  };
  static const defaults = [
    CashCategory('product-cost', 'Chi phí sản phẩm', false),
    CashCategory('customer-interest', 'Lãi khách hàng trả nợ', true),
    CashCategory('store-cost', 'Chi phí cửa hàng', false),
    CashCategory('utilities', 'Điện nước', false),
    CashCategory('salary', 'Lương nhân viên', false),
    CashCategory('transport', 'Vận chuyển', false),
    CashCategory('other-income', 'Thu khác', true),
    CashCategory('other-expense', 'Chi khác', false),
  ];
  static String nameFor(Map<String, dynamic> row) {
    final explicit = row['TenDanhMuc'];
    if (explicit is String && explicit.isNotEmpty) return explicit;
    final reason = '${row['LyDo'] ?? ''}'.toLowerCase();
    if (row['ThuChi'] == true &&
        reason.contains('lãi') &&
        reason.contains('khách') &&
        !reason.contains('cầm') &&
        !reason.contains('vay vốn')) {
      return 'Lãi khách hàng trả nợ';
    }
    return row['ThuChi'] == true ? 'Thu khác' : 'Chi khác';
  }
}
