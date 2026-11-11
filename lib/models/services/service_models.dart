class ServiceItem {
  const ServiceItem({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    this.cost = 0,
  });
  final String id, name, description;
  final int price, cost;
  factory ServiceItem.fromMap(Map<String, dynamic> row) => ServiceItem(
    id: row['_id'] as String,
    name: row['TenDichVu'] as String,
    description: row['MoTa'] as String? ?? '',
    price: (row['GiaTien'] as num).toInt(),
    cost: row['GiaVon'] is num ? (row['GiaVon'] as num).toInt() : 0,
  );
}

class ServicePage {
  const ServicePage(this.rows, this.total);
  final List<ServiceItem> rows;
  final int total;
}

class ServiceDraft {
  String name = '', description = '', price = '', cost = '0';
  int? get parsedPrice => RegExp(r'^\d+$').hasMatch(price.trim())
      ? int.tryParse(price.trim())
      : null;
  String? get priceError => parsedPrice == null || parsedPrice! < 0
      ? 'Nhập giá tiền từ 0 đồng, chỉ gồm chữ số'
      : null;
  int? get parsedCost {
    final text = cost.trim();
    if (text.isEmpty) return 0;
    return RegExp(r'^\d+$').hasMatch(text) ? int.tryParse(text) : null;
  }

  String? get costError =>
      parsedCost == null ? 'Nhập giá vốn từ 0 đồng, chỉ gồm chữ số' : null;
}

class ServiceException implements Exception {
  const ServiceException(this.message);
  final String message;
}
