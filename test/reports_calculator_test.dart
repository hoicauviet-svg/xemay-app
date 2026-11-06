import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/models/reports/report_models.dart';

void main() {
  Map<String, List<Map<String, dynamic>>> fixture() {
    final date = DateTime.utc(2026, 1, 1, 23, 59);
    return {
      'HoaDonBan': [
        {'IdHoaDon': 1, 'IdXe': 1, 'NgayMua': date, 'NgayHen': date},
        {
          'IdHoaDon': 2,
          'NgayMua': date,
          'PhienBanBanHang': 3,
          'TongTienHang': 2000,
          'GiamGia': 200,
          'TongThanhToan': 1800,
        },
        {
          'IdHoaDon': 3,
          'NgayMua': date,
          'TrangThaiLuu': 'dang_luu',
          'TongTienHang': 999999,
          'TongThanhToan': 999999,
        },
        {
          'IdHoaDon': 4,
          'NgayMua': DateTime.utc(2026, 1, 2),
          'TongTienHang': 99999,
          'TongThanhToan': 99999,
        },
      ],
      'ChiTietHoaDonBan': [
        {
          'IdHoaDon': 1,
          'IdXe': 1,
          'SoLuong': 1,
          'DonGia': null,
          'DonGiaNguon': 1000,
        },
        {'IdHoaDon': 2, 'SoLuong': 1, 'DonGia': 2000, 'LoaiSanPham': 'dich_vu'},
      ],
      'SoNo': [
        {'IdHoaDon': 1, 'SoTienDaTra': 500, 'SoTienConNo': 500},
        {'IdHoaDon': 2, 'SoTienDaTra': 1800, 'SoTienConNo': 0},
        {'IdHoaDon': 3, 'SoTienDaTra': 999999, 'SoTienConNo': 999999},
      ],
      'Xe': [
        {'IdXe': 1, 'GiaBan': 1000, 'GiaNhap': 600, 'TinhTrang': false},
        {'IdXe': 2, 'TinhTrang': true, 'TinhTrangXe': 'moi', 'GiaNhap': 700},
        {
          'IdXe': 3,
          'TinhTrang': true,
          'TinhTrangXe': 'cu',
          'GiaNhap': 500,
          'GiuChoBanHang': 'reserved',
        },
        {
          'IdXe': 4,
          'TinhTrang': true,
          'TinhTrangXe': 'chua_xac_dinh',
          'GiaNhap': 100,
        },
        {
          'IdXe': 5,
          'TinhTrang': true,
          'TinhTrangXe': 'moi',
          'GiaNhap': 9999,
          'DangNhapHang': 'pending',
        },
      ],
      'NhapHang': [
        {
          'NgayNhap': date,
          'SoLuong': 2,
          'SoTien': 3000,
          'SoTienDaTra': 2000,
          'SoTienConNo': 500,
        },
      ],
      'SanPham': [
        {'IdSanPham': 10, 'LoaiSanPham': 'phu_tung'},
      ],
      'TonKhoPhuTung': [
        {'IdSanPham': 10, 'SoLuongTon': 2, 'GiaVonThamKhao': 10},
      ],
      'NoCu': [
        {'SoCoNo': 300, 'NgayHen': date},
      ],
      'VayVon': [
        {'TongConNo': 400, 'NgayHen': DateTime.utc(2027)},
      ],
      'CamDo': [
        {
          'IdCamDo': 1,
          'TrangThai': false,
          'SoTienVay': 1000,
          'NgayVay': date,
          'NgayHan': date,
        },
      ],
      'TraNoCamDo': [
        {'IdCamDo': 1, 'TienGoc': 300, 'LaiThu': 50, 'NgayTra': date},
      ],
      'ThuChiKhac': [
        {'NgayThang': date, 'ThuChi': true, 'SoTien': 100},
        {'NgayThang': date, 'ThuChi': false, 'SoTien': 40},
        {'NgayThang': DateTime.utc(2026, 1, 2), 'ThuChi': true, 'SoTien': 999},
      ],
    };
  }

  ReportsData build(Map<String, List<Map<String, dynamic>>> source) =>
      ReportCalculator.build(
        range: ReportRange(
          from: DateTime(2026, 1, 1),
          to: DateTime(2026, 1, 1),
        ),
        source: source,
        now: DateTime(2026, 2, 1),
      );
  test(
    'Reports honor whole end day, legacy prices, service discounts and pending exclusion',
    () {
      final data = build(fixture());
      final sales = data.sections[ReportKind.sales]!;
      expect(sales.totals, {
        'Số đơn': 2,
        'Tiền hàng': 3000,
        'Giảm giá': 200,
        'Doanh thu': 2800,
        'Đã thu': 2300,
        'Còn nợ': 500,
        'Chi phí': 0,
        'Giá nhập': 600,
        'Lợi nhuận': 2200,
      });
      expect(sales.rows.length, 2);
      expect(sales.rows.map((r) => r[0]), [2, 1]);
      expect(sales.rows.first[1], DateTime.utc(2026, 1, 1, 23, 59));
      final receipts = data.sections[ReportKind.receipts]!;
      expect(receipts.totals['Số lô'], 1);
      expect(receipts.columns.any((c) => c.label == 'Chênh lệch'), false);
      expect(
        receipts.rows.first[receipts.columns.indexWhere(
          (c) => c.label == 'Tiền nhập',
        )],
        3000,
      );
      expect(receipts.notes.any((n) => n.contains('1 lô')), true);
      expect(data.sections[ReportKind.cash]!.totals, {'Thu': 100, 'Chi': 40});
    },
  );
  test('Stock and debt use current balances independently of date range', () {
    final data = build(fixture());
    final stock = data.sections[ReportKind.stock]!;
    expect(stock.totals, {'Xe mới': 1, 'Xe cũ': 0, 'Phụ tùng': 2});
    expect(stock.rows.first[2], 700);
    expect(stock.rows.last[2], 20);
    final debt = data.sections[ReportKind.debts]!;
    expect(debt.totals, {
      'Khách nợ bán hàng': 500,
      'Nợ cũ': 300,
      'Nợ nhà cung cấp': 500,
      'Vay vốn': 400,
    });
    expect(debt.rows[0][3], 1);
    expect(data.sections[ReportKind.pawnDebt]!.totals['Còn nợ'], 700);
    expect(data.sections[ReportKind.pawnDebt]!.rows.length, 1);
    expect(data.sections[ReportKind.pawn]!.totals, {
      'Phiếu mới': 1,
      'Tiền cho vay': 1000,
    });
  });
  test('Unknown legacy values remain blank instead of inventing zeros', () {
    final source = fixture();
    source['ChiTietHoaDonBan']!.first.remove('DonGiaNguon');
    source['Xe']!.first.remove('GiaBan');
    source['TonKhoPhuTung']!.clear();
    source['TraNoCamDo']!.first['LaiThu'] = null;
    final data = build(source);
    expect(data.sections[ReportKind.sales]!.totals['Doanh thu'], isNull);
    expect(data.sections[ReportKind.sales]!.totals['Giảm giá'], 200);
    expect(data.sections[ReportKind.stock]!.totals['Phụ tùng'], isNull);
    expect(
      data.sections[ReportKind.pawnCollections]!.totals['Lãi thực thu'],
      isNull,
    );
  });
  test('Modern sales never use unconfirmed source prices', () {
    final source = fixture();
    source['HoaDonBan']!.first['PhienBanBanHang'] = 3;
    source['ChiTietHoaDonBan']!.first['DonGiaNguon'] = 9000;
    expect(
      build(source).sections[ReportKind.sales]!.totals['Doanh thu'],
      isNull,
    );
  });
  test('Empty data yields empty period tables and zero totals', () {
    final data = build({});
    expect(data.sections[ReportKind.sales]!.rows, isEmpty);
    expect(data.sections[ReportKind.sales]!.totals['Doanh thu'], 0);
    expect(data.sections.length, 14);
  });
  test('Same-day vouchers remain separate with original codes and amounts', () {
    final date = DateTime.utc(2026, 1, 1);
    final source = fixture();
    source['NhapHang'] = [
      for (final id in [10, 11])
        {
          'IdNhapHang': id,
          'NgayNhap': date,
          'SoLuong': 1,
          'SoTien': 100,
          'SoTienDaTra': 100,
          'SoTienConNo': 0,
        },
    ];
    source['ThuChiKhac'] = [
      {
        'ThuChiId': 20,
        'NgayThang': date,
        'ThuChi': true,
        'LyDo': 'Thu A',
        'SoTien': 100,
      },
      {
        'ThuChiId': 21,
        'NgayThang': date,
        'ThuChi': false,
        'LyDo': 'Chi B',
        'SoTien': 40,
      },
      {'ThuChiId': 22, 'NgayThang': null, 'SoTien': 10},
    ];
    source['TraNoCamDo'] = [
      for (final id in [30, 31])
        {
          'IdTraNoCamDo': id,
          'IdCamDo': 1,
          'NgayTra': date,
          'TienGoc': 100,
          'LaiThu': 5,
        },
    ];
    final data = build(source);
    expect(data.sections[ReportKind.receipts]!.rows.map((r) => r[0]), [11, 10]);
    expect(data.sections[ReportKind.receipts]!.totals['Số lô'], 2);
    final cash = data.sections[ReportKind.cash]!;
    expect(cash.rows, [
      [21, date, 'Chi', 'Chi B', 40, 'Chi khác'],
      [20, date, 'Thu', 'Thu A', 100, 'Thu khác'],
    ]);
    expect(cash.totals.containsKey('Chênh lệch'), false);
    final pawn = data.sections[ReportKind.pawn]!;
    expect(pawn.rows.length, 1);
    final collections = data.sections[ReportKind.pawnCollections]!;
    expect(collections.rows.map((r) => r[0]), [31, 30]);
    expect(collections.totals['Gốc đã thu'], 200);
    expect(collections.totals['Lãi thực thu'], 10);
    final all = ReportCalculator.build(range: ReportRange(), source: source);
    expect(all.sections[ReportKind.cash]!.rows.last[0], 22);
    expect(all.sections[ReportKind.cash]!.rows.last[2], isNull);
  });
  test(
    'Sales show customer, legacy vehicle and saved product/service names with quantities',
    () {
      final source = fixture();
      source['HoaDonBan']![0]['IdKH'] = '55';
      source['HoaDonBan']![1]['IdKH'] = 56;
      source['KhachHang'] = [
        {'IdKH': 55, 'TenKhachHang': 'Anh An'},
        {'IdKH': 56, 'TenKhachHang': 'Chị Bình'},
      ];
      source['Xe']!.first['TenXe'] = 'Elegant';
      source['SanPham']!.add({'IdSanPham': 99, 'TenSanPham': 'Tên mới'});
      source['ChiTietHoaDonBan']!.removeWhere((l) => l['IdHoaDon'] == 2);
      source['ChiTietHoaDonBan']!.addAll([
        {
          'IdHoaDon': 2,
          'IdSanPham': 99,
          'TenSanPham': 'Phụ tùng A',
          'SoLuong': 1,
          'DonGia': 1000,
          'DongSo': 2,
        },
        {
          'IdHoaDon': 2,
          'LoaiSanPham': 'dich_vu',
          'TenSanPham': 'Thay dầu',
          'SoLuong': 2,
          'DonGia': 500,
          'DongSo': 1,
        },
      ]);
      final sales = build(source).sections[ReportKind.sales]!;
      expect(sales.rows.first[2], 'Chị Bình');
      expect(sales.rows.first[3], 'Dịch vụ: Thay dầu × 2\nPhụ tùng A × 1');
      expect(sales.rows.last[2], 'Anh An');
      expect(sales.rows.last[3], 'Elegant × 1');
      expect(sales.totals['Doanh thu'], 2800);
      source['ChiTietHoaDonBan']!.removeWhere((l) => l['IdHoaDon'] == 1);
      expect(
        build(source).sections[ReportKind.sales]!.rows.last[3],
        'Elegant × 1',
      );
      source['KhachHang']!.clear();
      expect(build(source).sections[ReportKind.sales]!.rows.first[2], isNull);
    },
  );
  test(
    'Sales costs use vehicle expenses once and do not allocate shared part costs to every sale',
    () {
      final source = fixture();
      source['Xe']!.first['ChiPhi'] = [
        {'SoTien': 100},
        {'SoTien': 50},
      ];
      source['Xe']!.first['TongChiPhi'] = 150;
      source['ChiTietNhapHang'] = [
        {
          'IdXe': 1,
          'IdSanPham': 1,
          'ChiPhi': [
            {'SoTien': 150},
          ],
        },
      ];
      var sales = build(source).sections[ReportKind.sales]!;
      expect(
        sales.rows.last[sales.columns.indexWhere((c) => c.label == 'Chi phí')],
        150,
      );
      expect(sales.totals['Chi phí'], 150);
      source['ChiTietHoaDonBan']!.add({
        'IdHoaDon': 2,
        'IdSanPham': 10,
        'LoaiSanPham': 'phu_tung',
        'SoLuong': 2,
        'DonGia': 100,
      });
      source['ChiTietNhapHang']!.add({
        'IdXe': null,
        'IdSanPham': 10,
        'ChiPhi': [
          {'SoTien': 80},
        ],
      });
      sales = build(source).sections[ReportKind.sales]!;
      expect(
        sales.rows.first[sales.columns.indexWhere((c) => c.label == 'Chi phí')],
        isNull,
      );
      expect(sales.totals['Chi phí'], isNull);
      source['ChiTietNhapHang']!.last['ChiPhi'] = [];
      expect(build(source).sections[ReportKind.sales]!.totals['Chi phí'], 150);
    },
  );
  test(
    'Profit deducts actual purchase totals and expenses after discount, including losses and unknown costs',
    () {
      final source = fixture();
      source['Xe']!.first['ChiPhi'] = [
        {'SoTien': 150},
      ];
      var sales = build(source).sections[ReportKind.sales]!;
      int column(String label) =>
          sales.columns.indexWhere((c) => c.label == label);
      expect(sales.rows.last[column('Giá nhập')], 600);
      expect(sales.rows.last[column('Lợi nhuận')], 250);
      expect(sales.rows.first[column('Lợi nhuận')], 1800);
      expect(sales.totals['Lợi nhuận'], 2050);
      source['Xe']!.first['GiaNhap'] = 1200;
      expect(
        build(source).sections[ReportKind.sales]!.rows.last[column(
          'Lợi nhuận',
        )],
        -350,
      );
      source['Xe']!.first.remove('GiaNhap');
      expect(
        build(source).sections[ReportKind.sales]!.totals['Lợi nhuận'],
        isNull,
      );
      source['Xe']!.first['GiaNhap'] = 600;
      source['ChiTietHoaDonBan']!.add({
        'IdHoaDon': 2,
        'LoaiSanPham': 'phu_tung',
        'IdSanPham': 10,
        'SoLuong': 2,
        'DonGia': 100,
        'GiaNhap': 40,
      });
      sales = build(source).sections[ReportKind.sales]!;
      expect(sales.rows.first[column('Giá nhập')], 80);
      expect(sales.rows.first[column('Lợi nhuận')], 1720);
      source['ChiTietHoaDonBan']!.last.remove('GiaNhap');
      expect(
        build(source).sections[ReportKind.sales]!.rows.first[column(
          'Lợi nhuận',
        )],
        isNull,
      );
    },
  );
  test(
    'Receipts show linked partner/carrier with legacy text fallback and no difference column',
    () {
      final source = fixture();
      source['DoiTac'] = [
        {'_id': 'partner-1', 'TenDoiTac': 'Nhà cung cấp A'},
      ];
      source['VanChuyen'] = [
        {'_id': 'carrier-1', 'TenVanChuyen': 'Vận chuyển B'},
      ];
      source['NhapHang']!.first.addAll({
        'IdDoiTac': 'partner-1',
        'IdVanChuyen': 'carrier-1',
        'NoiNhap': 'Tên cũ',
        'NguoiCho': 'Người cũ',
      });
      var receipts = build(source).sections[ReportKind.receipts]!;
      expect(receipts.rows.first[2], 'Nhà cung cấp A');
      expect(receipts.rows.first[3], 'Vận chuyển B');
      expect(receipts.rows.first.length, receipts.columns.length);
      expect(receipts.columns.any((c) => c.label == 'Chênh lệch'), false);
      source['DoiTac']!.clear();
      source['VanChuyen']!.clear();
      receipts = build(source).sections[ReportKind.receipts]!;
      expect(receipts.rows.first[2], 'Tên cũ');
      expect(receipts.rows.first[3], 'Người cũ');
    },
  );
  test(
    'Negative and missing balances do not hide positive customer debt or include orphan orders',
    () {
      final source = fixture();
      source['HoaDonBan']!.add({
        'IdHoaDon': 5,
        'NgayMua': DateTime.utc(2025, 1, 1),
      });
      source['SoNo']!.addAll([
        {'IdHoaDon': 4, 'SoTienConNo': -50},
        {'IdHoaDon': 5, 'SoTienConNo': null},
        {'IdHoaDon': 999, 'SoTienConNo': 99999},
      ]);
      final section = build(source).sections[ReportKind.debts]!;
      expect(section.totals['Khách nợ bán hàng'], 500);
      expect(section.rows.first, ['Khách nợ bán hàng', 1, 500, 1]);
      expect(
        section.columns.any(
          (c) => ['Số dư âm', 'Chưa rõ số dư'].contains(c.label),
        ),
        false,
      );
      expect(section.notes.any((n) => n.contains('mã đơn 4')), true);
      expect(section.rows.any((r) => '${r[0]}'.contains('cầm đồ')), false);
    },
  );
  test(
    'Cash type filter preserves date scope and sums only selected vouchers',
    () {
      final source = fixture();
      var cash = build(source).sections[ReportKind.cash]!;
      final income = ReportCalculator.filterCash(cash, 'income');
      expect(income.rows.length, 1);
      expect(income.rows.single[2], 'Thu');
      expect(income.totals, {'Thu': 100, 'Chi': 0});
      final expense = ReportCalculator.filterCash(cash, 'expense');
      expect(expense.rows.length, 1);
      expect(expense.totals, {'Thu': 0, 'Chi': 40});
      expect(ReportCalculator.filterCash(cash, 'all').rows.length, 2);
      source['ThuChiKhac']![1]['SoTien'] = null;
      cash = build(source).sections[ReportKind.cash]!;
      expect(
        ReportCalculator.filterCash(cash, 'expense').totals['Chi'],
        isNull,
      );
      expect(
        () => ReportCalculator.filterCash(cash, 'invalid'),
        throwsArgumentError,
      );
    },
  );
  test(
    'Detailed debt reports show current positive balances, contacts, deadlines and matching totals',
    () {
      final source = fixture();
      source['HoaDonBan']!.first.addAll({
        'IdKH': 55,
        'NgayMua': DateTime.utc(2025, 1, 1),
      });
      source['KhachHang'] = [
        {
          'IdKH': 55,
          'TenKhachHang': 'Khách A',
          'SoDienThoai': '091111',
          'DiaChiChiTiet': 'Nhà 1',
          'IdXa': 7,
        },
      ];
      source['Xa'] = [
        {'IdXa': 7, 'TenXa': 'Phường A'},
      ];
      source['NhapHang']!.first.addAll({
        'IdNhapHang': 100,
        'IdDoiTac': 'p1',
        'NgayHen': DateTime.utc(2026, 1, 20),
      });
      source['DoiTac'] = [
        {
          '_id': 'p1',
          'TenDoiTac': 'Nhà cung cấp B',
          'SoDienThoai': '092222',
          'DiaChi': 'Địa chỉ B',
        },
      ];
      source['NhapHang']!.addAll([
        {'IdNhapHang': 101, 'SoTienConNo': 0},
        {'IdNhapHang': 102, 'SoTienConNo': 9999, 'TrangThaiLuu': 'dang_luu'},
      ]);
      final data = build(source);
      final customers = data.sections[ReportKind.customerDebt]!;
      expect(customers.rows.length, 1);
      expect(customers.rows.single[0], 1);
      expect(customers.rows.single.sublist(2, 8), [
        'Khách A',
        '091111',
        'Nhà 1, Phường A',
        1000,
        500,
        500,
      ]);
      expect(customers.rows.single[9], 31);
      expect(
        customers.totals['Còn nợ'],
        data.sections[ReportKind.debts]!.totals['Khách nợ bán hàng'],
      );
      final suppliers = data.sections[ReportKind.supplierDebt]!;
      expect(suppliers.rows.length, 1);
      expect(suppliers.rows.single.sublist(2, 5), [
        'Nhà cung cấp B',
        '092222',
        'Địa chỉ B',
      ]);
      expect(suppliers.rows.single[9], 12);
      expect(suppliers.totals['Còn nợ'], 500);
      expect(
        ReportCalculator.filterDebtDetail(customers, '091111').rows.length,
        1,
      );
      final empty = ReportCalculator.filterDebtDetail(customers, 'Không khớp');
      expect(empty.rows, isEmpty);
      expect(empty.totals['Còn nợ'], 0);
    },
  );
  test(
    'Repayment reports join the correct parents and use payment dates and actual interest',
    () {
      final source = fixture(), date = DateTime.utc(2026, 1, 1, 23, 59);
      source['HoaDonBan']!.first['IdKH'] = 55;
      source['KhachHang'] = [
        {'IdKH': 55, 'TenKhachHang': 'Khách A'},
      ];
      source['SoNo']!.first['IdSoNo'] = 11;
      source['SoNo']![2]['IdSoNo'] = 33;
      source['NhapHang']!.first.addAll({
        'IdNhapHang': 100,
        'NoiNhap': 'Nhà cung cấp B',
      });
      source['NoCu']!.first.addAll({'Id': 200, 'IdKH': '55'});
      source['VayVon']!.first.addAll({
        'IdVayVon': 9,
        'DoiTac': 'Người cho vay C',
      });
      source['TraNo'] = [
        {
          'IdTraNo': 1,
          'IdSoNo': 11,
          'NgayTra': date,
          'SotienTra': 100,
          'LaiThu': 10,
          'SoTienLai': 999,
          'SoCoNo': 400,
        },
        {
          'IdTraNo': 2,
          'IdSoNo': 11,
          'NgayTra': DateTime.utc(2026, 1, 2),
          'SotienTra': 999,
          'LaiThu': 999,
        },
        {
          'IdTraNo': 3,
          'IdSoNo': 33,
          'NgayTra': date,
          'SotienTra': 999,
          'LaiThu': 999,
        },
      ];
      source['TraNoNhapHang'] = [
        {
          'IdTraNoNhapHang': 2,
          'IdNhapHang': 100,
          'NgayTra': date,
          'SoTienTra': 200,
          'SoCoNo': 300,
        },
      ];
      source['TraNoCu'] = [
        {
          'Id': 3,
          'IdNoCu': 200,
          'NgayTra': date,
          'SoTienTra': 300,
          'LaiThu': 0,
          'TienLai': 999,
          'ConNo': 0,
        },
      ];
      source['TraNoVayVon'] = [
        {
          'IdTraNoVayVon': 4,
          'IdVayVon': 9,
          'NgayTra': date,
          'SoTienTraGoc': 400,
          'SoTienTraLai': 40,
          'ConNoGoc': 0,
        },
      ];
      final data = build(source);
      final customer = data.sections[ReportKind.customerRepayments]!;
      expect(customer.rows.length, 1);
      expect(customer.rows.single.sublist(2, 7), [1, 'Khách A', 100, 10, 400]);
      expect(customer.totals, {'Tiền trả nợ': 100, 'Lãi thực thu': 10});
      final supplier = data.sections[ReportKind.supplierRepayments]!;
      expect(supplier.rows.single[3], 'Nhà cung cấp B');
      expect(supplier.totals, {'Số tiền trả': 200});
      expect(
        data.sections[ReportKind.oldDebtRepayments]!.rows.single[3],
        'Khách A',
      );
      expect(data.sections[ReportKind.oldDebtRepayments]!.totals, {
        'Tiền trả nợ': 300,
        'Lãi thực thu': 0,
      });
      expect(
        data.sections[ReportKind.fundingRepayments]!.rows.single[3],
        'Người cho vay C',
      );
      expect(data.sections[ReportKind.fundingRepayments]!.totals, {
        'Trả gốc': 400,
        'Trả lãi': 40,
      });
      source['TraNoCu']!.first['LaiThu'] = null;
      expect(
        build(
          source,
        ).sections[ReportKind.oldDebtRepayments]!.totals['Lãi thực thu'],
        isNull,
      );
    },
  );
  test('Invalid date ranges are rejected', () {
    expect(
      () => ReportRange(from: DateTime(2026, 2, 1), to: DateTime(2026, 1, 1)),
      throwsArgumentError,
    );
  });
}
