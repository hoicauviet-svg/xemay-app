class ServiceItem {
  const ServiceItem({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
  });
  final String id, name, description;
  final int price;
  factory ServiceItem.fromMap(Map<String, dynamic> row) => ServiceItem(
    id: row['_id'] as String,
    name: row['TenDichVu'] as String,
    description: row['MoTa'] as String? ?? '',
    price: (row['GiaTien'] as num).toInt(),
  );
}

class ServicePage {
  const ServicePage(this.rows, this.total);
  final List<ServiceItem> rows;
  final int total;
}

class ServiceDraft {
  String name = '', description = '', price = '';
  int? get parsedPrice => RegExp(r'^\d+$').hasMatch(price.trim())
      ? int.tryParse(price.trim())
      : null;
  String? get priceError => parsedPrice == null || parsedPrice! < 0
      ? 'Nhập giá tiền từ 0 đồng, chỉ gồm chữ số'
      : null;
}

class ServiceException implements Exception {
  const ServiceException(this.message);
  final String message;
}
