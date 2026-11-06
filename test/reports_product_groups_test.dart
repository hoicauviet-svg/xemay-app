import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/models/reports/report_models.dart';
import 'package:xemay_app/views/reports/reports_view.dart';
import 'support/fake_reports_repository.dart';

Map<String, List<Map<String, dynamic>>> fixture(DateTime date) => {
  'HoaDonBan': [
    {
      'IdHoaDon': 1,
      'NgayMua': date,
      'PhienBanBanHang': 3,
      'TongTienHang': 150000,
      'GiamGia': 15000,
      'TongThanhToan': 135000,
    },
  ],
  'SoNo': [
    {'IdHoaDon': 1, 'SoTienDaTra': 90000, 'SoTienConNo': 45000},
  ],
  'Xe': [
    {'IdXe': 1, 'TinhTrangXe': 'moi', 'GiaNhap': 50000, 'TenXe': 'Xe mới A'},
    {'IdXe': 2, 'TinhTrangXe': 'cu', 'GiaNhap': 10000, 'TenXe': 'Xe cũ B'},
  ],
  'SanPham': [
    {'IdSanPham': 3, 'LoaiSanPham': 'phu_tung', 'TenSanPham': 'Phụ tùng C'},
  ],
  'ChiTietHoaDonBan': [
    {
      'IdHoaDon': 1,
      'IdXe': 1,
      'TenSanPham': 'Xe mới A',
      'SoLuong': 1,
      'DonGia': 100000,
    },
    {
      'IdHoaDon': 1,
      'IdXe': 2,
      'TenSanPham': 'Xe cũ B',
      'SoLuong': 1,
      'DonGia': 20000,
    },
    {
      'IdHoaDon': 1,
      'IdSanPham': 3,
      'TenSanPham': 'Phụ tùng C',
      'LoaiSanPham': 'phu_tung',
      'SoLuong': 2,
      'DonGia': 10000,
      'GiaNhap': 5000,
    },
    {
      'IdHoaDon': 1,
      'TenSanPham': 'Dịch vụ D',
      'LoaiSanPham': 'dich_vu',
      'SoLuong': 1,
      'DonGia': 10000,
    },
  ],
  'NhapHang': [
    {
      'IdNhapHang': 1,
      'NgayNhap': date,
      'SoLuong': 1,
      'SoTien': 50000,
      'SoTienDaTra': 50000,
      'SoTienConNo': 0,
    },
    {
      'IdNhapHang': 2,
      'NgayNhap': date,
      'LoaiSanPham': 'xe_cu',
      'SoLuong': 1,
      'SoTien': 10000,
      'SoTienDaTra': 5000,
      'SoTienConNo': 5000,
    },
    {
      'IdNhapHang': 3,
      'NgayNhap': date,
      'LoaiSanPham': 'phu_tung',
      'SoLuong': 2,
      'SoTien': 10000,
      'SoTienDaTra': 10000,
      'SoTienConNo': 0,
    },
  ],
};
ReportsData build(Map<String, List<Map<String, dynamic>>> source) =>
    ReportCalculator.build(range: ReportRange(), source: source);
void main() {
  testWidgets(
    'overview puts summary above divider and details; stock shows quantity and value',
    (t) async {
      t.view.physicalSize = const Size(1400, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final source = fixture(DateTime.now());
      for (final vehicle in source['Xe']!) {
        vehicle['TinhTrang'] = true;
      }
      source['TonKhoPhuTung'] = [
        {'IdSanPham': 3, 'SoLuongTon': 2, 'GiaVonThamKhao': 5000},
      ];
      source['ThuChiKhac'] = [
        {
          'ThuChiId': 1,
          'NgayThang': DateTime.now(),
          'ThuChi': false,
          'SoTien': 100,
          'TenDanhMuc': 'Điện nước',
        },
      ];
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportsView(
              repository: FakeReportsRepository()..source = source,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      for (final kind in [
        ReportKind.sales,
        ReportKind.receipts,
        ReportKind.stock,
        ReportKind.customerDebt,
        ReportKind.supplierDebt,
        ReportKind.cash,
        ReportKind.pawn,
        ReportKind.customerRepayments,
        ReportKind.supplierRepayments,
      ]) {
        final summary = t.getRect(
          find.byKey(ValueKey('overview-summary-${kind.name}')),
        );
        final divider = t.getRect(
          find.byKey(ValueKey('overview-divider-${kind.name}')),
        );
        final detail = t.getRect(
          find.byKey(ValueKey('overview-details-${kind.name}')),
        );
        expect(summary.bottom, lessThanOrEqualTo(divider.top));
        expect(divider.bottom, lessThanOrEqualTo(detail.top));
      }
      final stock = find.byKey(const ValueKey('overview-card-stock'));
      expect(
        find.descendant(of: stock, matching: find.text('Số lượng')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: stock, matching: find.text('Giá trị')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: stock, matching: find.textContaining('70.000 đ')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: stock, matching: find.textContaining('50.000 đ')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: stock, matching: find.textContaining('10.000 đ')),
        findsNWidgets(2),
      );
      expect(t.takeException(), isNull);
    },
  );

  test('aging treats due today as within and keeps missing dates separate', () {
    final result = ReportCalculator.debtAging(
      [
        {'Amount': 100, 'Due': DateTime.utc(2026, 11, 4, 23, 59)},
        {'Amount': 200, 'Due': DateTime(2026, 11, 5)},
        {'Amount': 300, 'Due': DateTime(2026, 11, 6)},
        {'Amount': 400},
        {'Amount': 0, 'Due': DateTime(2026, 1, 1)},
        {'Amount': -100, 'Due': DateTime(2026, 1, 1)},
      ],
      amountKey: 'Amount',
      dateKey: 'Due',
      today: DateTime(2026, 11, 5),
    );
    expect(result.within, 500);
    expect(result.overdue, 100);
    expect(result.undated, 400);
    final unknown = ReportCalculator.debtAging(
      [
        {'Amount': null, 'Due': DateTime(2026, 11, 4)},
      ],
      amountKey: 'Amount',
      dateKey: 'Due',
      today: DateTime(2026, 11, 5),
      includeUnknownAmounts: true,
    );
    expect(unknown.overdue, isNull);
  });
  test(
    'customer aging includes old debts; pawn aging ignores settled contracts',
    () {
      final source = fixture(DateTime(2026, 11, 5));
      source['HoaDonBan']!.single['NgayHen'] = DateTime(2026, 11, 5);
      source['NoCu'] = [
        {'Id': 'old', 'SoCoNo': 1000, 'NgayHen': DateTime(2026, 11, 4)},
      ];
      source['CamDo'] = [
        {
          'IdCamDo': 1,
          'TrangThai': false,
          'SoTienVay': 5000,
          'NgayHan': DateTime(2026, 11, 4),
        },
        {
          'IdCamDo': 2,
          'TrangThai': false,
          'SoTienVay': 6000,
          'NgayHan': DateTime(2026, 11, 5),
        },
        {
          'IdCamDo': 3,
          'TrangThai': true,
          'SoTienVay': 999999,
          'NgayHan': DateTime(2026, 11, 4),
        },
      ];
      source['TraNoCamDo'] = [
        {'IdCamDo': 1, 'TienGoc': 1000},
      ];
      final data = ReportCalculator.build(
        range: ReportRange(),
        source: source,
        now: DateTime(2026, 11, 5),
      );
      expect(data.customerAging.within, 45000);
      expect(data.customerAging.overdue, 1000);
      expect(data.pawnAging.within, 6000);
      expect(data.pawnAging.overdue, 4000);
      source['SoNo']!.single['ThanhToanDangLuu'] = {'x': 1};
      final pending = ReportCalculator.build(
        range: ReportRange(),
        source: source,
        now: DateTime(2026, 11, 5),
      );
      expect(pending.customerAging.overdue, 1000);
    },
  );
  testWidgets(
    'overview shows product groups, aging and cash categories in their own cards',
    (t) async {
      t.view.physicalSize = const Size(1400, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final now = DateTime.now();
      final source = fixture(now);
      source['HoaDonBan']!.single['NgayHen'] = now;
      source['ThuChiKhac'] = [
        {
          'ThuChiId': 1,
          'NgayThang': now,
          'ThuChi': false,
          'SoTien': 25000,
          'TenDanhMuc': 'Điện nước',
        },
      ];
      final repo = FakeReportsRepository()..source = source;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ReportsView(repository: repo)),
        ),
      );
      await t.pumpAndSettle();
      for (final kind in [ReportKind.sales, ReportKind.receipts]) {
        final card = find.byKey(ValueKey('overview-card-${kind.name}'));
        for (final label in ['Xe mới', 'Xe cũ', 'Phụ tùng', 'Dịch vụ']) {
          expect(
            find.descendant(of: card, matching: find.text(label)),
            findsOneWidget,
          );
        }
      }
      for (final kind in [ReportKind.customerDebt, ReportKind.pawn]) {
        final card = find.byKey(ValueKey('overview-card-${kind.name}'));
        expect(
          find.descendant(of: card, matching: find.text('Trong hạn')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: card, matching: find.text('Quá hạn')),
          findsOneWidget,
        );
      }
      final cash = find.byKey(const ValueKey('overview-card-cash'));
      expect(
        find.descendant(of: cash, matching: find.text('Điện nước')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: cash, matching: find.textContaining('25.000 đ')),
        findsWidgets,
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'overview splits customer and partner debts and opens corresponding report',
    (t) async {
      t.view.physicalSize = const Size(1400, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      ReportKind? exported;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportsView(
              repository: FakeReportsRepository()
                ..source = fixture(DateTime.now()),
              exportReport: (kind, section, range, time) async {
                exported = kind;
                return true;
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final overview = find.byKey(const ValueKey('reports-overview'));
      final customer = find.descendant(
        of: overview,
        matching: find.text('Khách hàng nợ'),
      );
      expect(customer, findsOneWidget);
      expect(
        find.descendant(of: overview, matching: find.text('Nợ đối tác')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: overview, matching: find.text('Công nợ')),
        findsNothing,
      );
      await t.ensureVisible(customer);
      await t.tap(customer);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('report-export-excel')));
      await t.pumpAndSettle();
      expect(exported, ReportKind.customerDebt);
      await t.tap(find.widgetWithText(Tab, 'Tổng quan'));
      await t.pumpAndSettle();
      final partner = find.descendant(
        of: overview,
        matching: find.text('Nợ đối tác'),
      );
      await t.ensureVisible(partner);
      await t.tap(partner);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('report-export-excel')));
      await t.pumpAndSettle();
      expect(exported, ReportKind.supplierDebt);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'overview separates collected debts from paid debts and opens supplier repayments',
    (t) async {
      t.view.physicalSize = const Size(1400, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      ReportKind? exported;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportsView(
              repository: FakeReportsRepository(),
              exportReport: (kind, section, range, time) async {
                exported = kind;
                return true;
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final expense = find.text('Chi trả nợ');
      await t.ensureVisible(expense);
      await t.tap(expense);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('report-export-excel')));
      await t.pumpAndSettle();
      expect(exported, ReportKind.supplierRepayments);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'overview fits a narrow window and keeps current balances separate',
    (t) async {
      t.view.physicalSize = const Size(420, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportsView(repository: FakeReportsRepository()),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('reports-overview')), findsOneWidget);
      expect(find.text('Hiện tại'), findsNothing);
      expect(find.text('Chi tiết'), findsNWidgets(4));
      expect(find.text('Thu trả nợ'), findsOneWidget);
      expect(find.text('Chi trả nợ'), findsOneWidget);
      await t.drag(
        find.byKey(const ValueKey('reports-overview')),
        const Offset(0, -1200),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );

  test(
    'mixed order splits product names, prices, costs and financial totals without duplication',
    () {
      final result = build(fixture(DateTime(2026, 11, 5)));
      final all = result.sections[ReportKind.sales]!;
      final groups = [
        ReportProductGroup.newVehicles,
        ReportProductGroup.usedVehicles,
        ReportProductGroup.parts,
        ReportProductGroup.services,
      ];
      for (final key in [
        'Tiền hàng',
        'Giảm giá',
        'Doanh thu',
        'Đã thu',
        'Còn nợ',
        'Giá nhập',
        'Chi phí',
        'Lợi nhuận',
      ]) {
        expect(
          groups.fold<num>(
            0,
            (s, g) => s + result.salesByGroup[g]!.totals[key]!,
          ),
          all.totals[key],
          reason: key,
        );
      }
      final services = result.salesByGroup[ReportProductGroup.services]!;
      expect(services.rows.single[3], contains('Dịch vụ D'));
      expect(services.rows.single[3], isNot(contains('Xe mới A')));
      expect(services.totals['Tiền hàng'], 10000);
      expect(services.totals['Giá nhập'], 0);
      expect(
        result.receiptsByGroup[ReportProductGroup.newVehicles]!.rows.single[0],
        1,
      );
      expect(
        result
            .receiptsByGroup[ReportProductGroup.usedVehicles]!
            .totals['Tiền nhập'],
        10000,
      );
      expect(
        result.receiptsByGroup[ReportProductGroup.parts]!.totals['Số lượng'],
        2,
      );
    },
  );
  test('currency rounding preserves both invoice and each group equations', () {
    final source = fixture(DateTime(2026, 11, 5));
    source['HoaDonBan']!.single.addAll({
      'TongTienHang': 4,
      'GiamGia': 1,
      'TongThanhToan': 3,
    });
    source['SoNo']!.single.addAll({'SoTienDaTra': 1, 'SoTienConNo': 2});
    for (final line in source['ChiTietHoaDonBan']!) {
      line['SoLuong'] = 1;
      line['DonGia'] = 1;
    }
    final result = build(source);
    num net = 0, paid = 0, due = 0;
    for (final group in result.salesByGroup.values.where(
      (s) => s.rows.isNotEmpty,
    )) {
      final t = group.totals;
      expect(t['Tiền hàng']! - t['Giảm giá']!, t['Doanh thu']);
      expect(t['Đã thu']! + t['Còn nợ']!, t['Doanh thu']);
      net += t['Doanh thu']!;
      paid += t['Đã thu']!;
      due += t['Còn nợ']!;
    }
    expect([net, paid, due], [3, 1, 2]);
  });
  test('missing price stays unknown and empty groups are zero', () {
    final source = fixture(DateTime(2026, 11, 5));
    source['ChiTietHoaDonBan']!.last.remove('DonGia');
    final result = build(source);
    expect(
      result.salesByGroup[ReportProductGroup.services]!.totals['Doanh thu'],
      isNull,
    );
    expect(
      result.salesByGroup[ReportProductGroup.newVehicles]!.totals['Doanh thu'],
      isNull,
    );
    expect(result.receiptsByGroup[ReportProductGroup.unknown]!.rows, isEmpty);
  });
  testWidgets(
    'overview opens by default; product group tabs filter rows and Excel snapshot',
    (t) async {
      t.view.physicalSize = const Size(1400, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final repo = FakeReportsRepository()..source = fixture(DateTime.now());
      ReportSection? exported;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportsView(
              repository: repo,
              exportReport: (kind, section, range, time) async {
                exported = section;
                return true;
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('reports-overview')), findsOneWidget);
      expect(find.text('Doanh thu'), findsOneWidget);
      await t.tap(
        find.descendant(
          of: find.byKey(const ValueKey('reports-overview')),
          matching: find.text('Bán hàng'),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(Tab, 'Dịch vụ'));
      await t.pumpAndSettle();
      expect(find.textContaining('Xe mới A'), findsNothing);
      expect(find.textContaining('Dịch vụ D'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('report-export-excel')));
      await t.pumpAndSettle();
      expect(exported?.totals['Tiền hàng'], 10000);
      await t.tap(find.widgetWithText(Tab, 'Nhập hàng'));
      await t.pumpAndSettle();
      expect(find.widgetWithText(Tab, 'Dịch vụ'), findsNothing);
      await t.tap(find.widgetWithText(Tab, 'Xe cũ'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('report-export-excel')));
      await t.pumpAndSettle();
      expect(exported?.totals['Tiền nhập'], 10000);
      expect(t.takeException(), isNull);
    },
  );
}
