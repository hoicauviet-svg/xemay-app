import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/models/products/product_list_report.dart';

void main() {
  test(
    'Product totals preserve missing prices and sum listed quantity and costs',
    () {
      final report = ProductListReport.products([
        {
          'IdXe': 1,
          'GiaNhap': 100,
          'GiaBan': 150,
          'TongChiPhi': 10,
          'SoLuongTon': 1,
        },
        {
          'IdXe': 2,
          'GiaNhap': 200,
          'GiaBan': null,
          'TongChiPhi': 20,
          'SoLuongTon': 0,
        },
      ], vehicle: true);
      expect(report.totals, {
        'Giá nhập': 300,
        'Chi phí': 30,
        'Giá bán': null,
        'Tồn kho': 1,
      });
      final parts = ProductListReport.products(
        [
          {
            'IdSanPham': 1,
            'SoLuongTon': 3,
            'GiaBanThamKhao': 100,
            'TongChiPhi': 10,
          },
        ],
        vehicle: false,
        availability: 'all',
        search: 'Dầu',
      );
      expect(parts.totals, {'Chi phí': 10, 'Tồn kho': 3});
      expect(parts.rows.single[4], 100);
      expect(parts.notes.single.contains('Tất cả; Tìm kiếm: Dầu'), true);
    },
  );
}
