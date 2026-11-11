import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/models/reports/report_models.dart';

Map<String, List<Map<String, dynamic>>> fixture() => {
  'HoaDonBan': [
    {
      'IdHoaDon': 152018,
      'NgayMua': DateTime.utc(2026, 11, 5),
      'PhienBanBanHang': 3,
      'TongTienHang': 25450000,
      'GiamGia': 450000,
      'TongThanhToan': 25000000,
    },
  ],
  'ChiTietHoaDonBan': [
    {
      'IdHoaDon': 152018,
      'LoaiSanPham': 'xe',
      'IdXe': 1,
      'IdSanPham': 1,
      'SoLuong': 1,
      'DonGia': 25000000,
    },
    {
      'IdHoaDon': 152018,
      'LoaiSanPham': 'phu_tung',
      'IdSanPham': 2,
      'SoLuong': 2,
      'DonGia': 150000,
    },
    {
      'IdHoaDon': 152018,
      'LoaiSanPham': 'dich_vu',
      'IdDichVu': 's',
      'SoLuong': 1,
      'DonGia': 150000,
    },
  ],
  'Xe': [
    {
      'IdXe': 1,
      'GiaNhap': 20000000,
      'TinhTrangXe': 'moi',
      'TongChiPhi': 500000,
    },
  ],
  'SanPham': [
    {'IdSanPham': 2, 'LoaiSanPham': 'phu_tung'},
  ],
  'SoNo': [
    {'IdHoaDon': 152018, 'SoTienDaTra': 15000000, 'SoTienConNo': 10000000},
  ],
  'NhapHang': [
    {'IdNhapHang': 3, 'NgayNhap': DateTime.utc(2026, 11, 5)},
  ],
  'ChiTietNhapHang': [
    {
      'IdNhapHang': 3,
      'IdSanPham': 2,
      'SoLuong': 10,
      'GiaNhap': 100000,
      'ChiPhi': [],
    },
  ],
  'TonKhoPhuTung': [
    {'IdSanPham': 2, 'GiaVonThamKhao': 999999},
  ],
};
ReportSection sales(Map<String, List<Map<String, dynamic>>> source) =>
    ReportCalculator.build(
      range: ReportRange(),
      source: source,
    ).sections[ReportKind.sales]!;

void main() {
  test(
    'Mixed historic sale derives part cost from its dated receipt, not stock reference',
    () {
      final source = fixture();
      final result = sales(source);
      expect(result.totals['Giá nhập'], 20200000);
      expect(result.totals['Chi phí'], 500000);
      expect(result.totals['Lợi nhuận'], 4300000);
      expect(result.totals['Đơn thiếu lợi nhuận'], 0);
      expect(source['ChiTietHoaDonBan']![1].containsKey('GiaNhap'), false);
      final groups = ReportCalculator.build(
        range: ReportRange(),
        source: source,
      ).salesByGroup;
      expect(groups[ReportProductGroup.parts]!.totals['Giá nhập'], 200000);
      expect(groups[ReportProductGroup.services]!.totals['Giá nhập'], 0);
    },
  );
  test('Later receipts do not change a historical sale cost', () {
    final source = fixture();
    source['NhapHang']!.add({
      'IdNhapHang': 4,
      'NgayNhap': DateTime.utc(2026, 11, 6),
    });
    source['ChiTietNhapHang']!.add({
      'IdNhapHang': 4,
      'IdSanPham': 2,
      'SoLuong': 10,
      'GiaNhap': 500000,
    });
    expect(sales(source).totals['Giá nhập'], 20200000);
  });
  test(
    'Ambiguous historic prices remain unknown unless a sale price was saved',
    () {
      final source = fixture();
      source['NhapHang']!.add({
        'IdNhapHang': 4,
        'NgayNhap': DateTime.utc(2026, 11, 4),
      });
      source['ChiTietNhapHang']!.add({
        'IdNhapHang': 4,
        'IdSanPham': 2,
        'SoLuong': 10,
        'GiaNhap': 200000,
      });
      expect(sales(source).totals['Giá nhập'], isNull);
      source['ChiTietHoaDonBan']![1]['GiaNhap'] = 110000;
      expect(sales(source).totals['Giá nhập'], 20220000);
    },
  );
  test(
    'Missing receipt dates and insufficient quantities cannot establish historic cost',
    () {
      final source = fixture();
      source['NhapHang']!.single.remove('NgayNhap');
      expect(sales(source).totals['Giá nhập'], isNull);
      source['NhapHang']!.single['NgayNhap'] = DateTime.utc(2026, 11, 5);
      source['ChiTietNhapHang']!.single['SoLuong'] = 1;
      expect(sales(source).totals['Giá nhập'], isNull);
    },
  );
}
