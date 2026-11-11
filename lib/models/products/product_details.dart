class ProductEditDraft {
  String name = '',
      code = '',
      unit = '',
      salePrice = '',
      notes = '',
      frame = '',
      engine = '',
      plate = '',
      color = '';
  ProductEditDraft.fromInformation(Map<String, dynamic> row, bool vehicle) {
    name = '${row[vehicle ? 'TenXe' : 'TenSanPham'] ?? ''}';
    code = '${row['MaSanPham'] ?? ''}';
    unit = '${row['DonViTinh'] ?? ''}';
    final price = row[vehicle ? 'GiaBan' : 'GiaBanThamKhao'];
    salePrice = price is num && price % 1 == 0
        ? '${price.toInt()}'
        : price?.toString() ?? '';
    notes = '${row['GhiChu'] ?? ''}';
    frame = '${row['SoKhung'] ?? ''}';
    engine = '${row['SoMay'] ?? ''}';
    plate = '${row['BienSo'] ?? ''}';
    color = '${row['MauSon'] ?? row['MauSac'] ?? row['Mau'] ?? ''}';
  }
  String? validate() {
    if (name.trim().isEmpty) return 'Vui lòng nhập tên sản phẩm.';
    if (salePrice.trim().isNotEmpty) {
      final n = int.tryParse(salePrice);
      if (n == null || n < 0 || n > 1000000000000000) {
        return 'Giá bán không hợp lệ.';
      }
    }
    return null;
  }
}

class ProductReference {
  const ProductReference({required this.id, required this.vehicle});
  final int id;
  final bool vehicle;
}

class ProductDetails {
  const ProductDetails({
    required this.information,
    required this.sales,
    required this.receipts,
    required this.costs,
  });
  final Map<String, dynamic> information;
  final List<Map<String, dynamic>> sales, receipts, costs;
  num get totalCosts =>
      costs.fold<num>(0, (sum, cost) => sum + (cost['SoTien'] as num? ?? 0));
}
