import '../reports/report_models.dart';
import '../services/service_models.dart';

class ProductListReport {
  static num? _sum(Iterable<dynamic> values) {
    num total = 0;
    for (final v in values) {
      if (v is! num || !v.isFinite) return null;
      total += v;
    }
    return total;
  }

  static ReportSection products(
    List<Map<String, dynamic>> rows, {
    required bool vehicle,
    String search = '',
    String availability = 'available',
  }) => ReportSection(
    columns: vehicle
        ? const [
            ReportColumn('Mã xe'),
            ReportColumn('Tên xe'),
            ReportColumn('Số khung'),
            ReportColumn('Số máy'),
            ReportColumn('Biển số'),
            ReportColumn('Màu sơn'),
            ReportColumn('Giá nhập', money: true),
            ReportColumn('Chi phí', money: true),
            ReportColumn('Giá bán', money: true),
            ReportColumn('Tồn kho'),
          ]
        : const [
            ReportColumn('Mã sản phẩm'),
            ReportColumn('Tên phụ tùng'),
            ReportColumn('Đơn vị'),
            ReportColumn('Tồn kho'),
            ReportColumn('Giá tham khảo', money: true),
            ReportColumn('Chi phí', money: true),
          ],
    rows: [
      for (final r in rows)
        if (vehicle)
          [
            r['IdXe'],
            r['TenXe'],
            r['SoKhung'],
            r['SoMay'],
            r['BienSo'],
            r['MauSon'],
            r['GiaNhap'],
            r['TongChiPhi'] ?? 0,
            r['GiaBan'],
            r['SoLuongTon'],
          ]
        else
          [
            r['MaSanPham'] ?? r['IdSanPham'],
            r['TenSanPham'],
            r['DonViTinh'],
            r['SoLuongTon'],
            r['GiaBanThamKhao'],
            r['TongChiPhi'] ?? 0,
          ],
    ],
    totals: {
      if (vehicle) 'Giá nhập': _sum(rows.map((r) => r['GiaNhap'])),
      'Chi phí': _sum(rows.map((r) => r['TongChiPhi'] ?? 0)),
      if (vehicle) 'Giá bán': _sum(rows.map((r) => r['GiaBan'])),
      'Tồn kho': _sum(rows.map((r) => r['SoLuongTon'])),
    },
    notes: [
      'Bộ lọc: ${availability == 'available'
          ? 'Chưa bán / còn hàng'
          : availability == 'sold'
          ? 'Đã bán / hết hàng'
          : 'Tất cả'}${search.trim().isEmpty ? '' : '; Tìm kiếm: ${search.trim()}'}',
    ],
  );
  static ReportSection services(
    List<ServiceItem> rows, {
    String search = '',
  }) => ReportSection(
    columns: const [
      ReportColumn('Tên dịch vụ'),
      ReportColumn('Mô tả', width: 300),
      ReportColumn('Giá tiền', money: true),
      ReportColumn('Giá vốn', money: true),
    ],
    rows: [
      for (final r in rows) [r.name, r.description, r.price, r.cost],
    ],
    totals: {
      'Giá tiền': _sum(rows.map((r) => r.price)),
      'Giá vốn': _sum(rows.map((r) => r.cost)),
    },
    notes: [
      'Tổng giá niêm yết của các dịch vụ đang hiển thị.${search.trim().isEmpty ? '' : ' Tìm kiếm: ${search.trim()}'}',
    ],
  );
}
