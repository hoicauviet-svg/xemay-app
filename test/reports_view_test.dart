import 'package:xemay_app/views/reports/reports_overview_view.dart';
import 'package:xemay_app/models/reports/report_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/views/reports/reports_view.dart';
import 'support/fake_reports_repository.dart';

void main() {
  testWidgets(
    'Overview and sales show known profit with incomplete cost warning',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.now();
      final repo = FakeReportsRepository()
        ..source = {
          'HoaDonBan': [
            {
              'IdHoaDon': 1,
              'NgayMua': now,
              'PhienBanBanHang': 3,
              'TongThanhToan': 1000,
              'TongTienHang': 1000,
            },
            {
              'IdHoaDon': 2,
              'NgayMua': now,
              'PhienBanBanHang': 3,
              'TongThanhToan': 100,
              'TongTienHang': 100,
            },
          ],
          'ChiTietHoaDonBan': [
            {'IdHoaDon': 1, 'IdXe': 1, 'SoLuong': 1, 'DonGia': 1000},
          ],
          'Xe': [
            {'IdXe': 1, 'GiaNhap': 600, 'TinhTrangXe': 'moi'},
          ],
        };
      final data = await repo.load(ReportRange());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportsOverviewView(data: data, onOpen: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Lợi nhuận đã xác định'), findsOneWidget);
      expect(find.text('Đơn chưa xác định lợi nhuận'), findsOneWidget);
      expect(find.text('400 đ'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportsView(initialKind: ReportKind.sales, repository: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('sales-profit-summary')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Lợi nhuận đã xác định: 400 đ'),
        findsOneWidget,
      );
      expect(find.textContaining('1 đơn chưa đủ dữ liệu'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Report time presets, current balances, refresh and retry', (
    t,
  ) async {
    t.view.physicalSize = const Size(1400, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final repo = FakeReportsRepository();
    final today = DateTime.now();
    repo.source = {
      'ThuChiKhac': [
        {
          'NgayThang': DateTime.utc(today.year, today.month, today.day),
          'ThuChi': true,
          'SoTien': 123456,
        },
      ],
    };
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportsView(initialKind: ReportKind.sales, repository: repo),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(repo.lastRange?.from?.day, 1);
    expect(find.byType(Tab), findsNWidgets(13));
    await t.tap(find.byTooltip('Chọn nhanh thời gian'));
    await t.pumpAndSettle();
    await t.tap(find.text('Tất cả thời gian'));
    await t.pumpAndSettle();
    expect(repo.lastRange?.from, isNull);
    expect(find.text('Tất cả thời gian'), findsNWidgets(2));
    await t.tap(find.widgetWithText(Tab, 'Thu chi'));
    await t.pumpAndSettle();
    expect(find.textContaining('123.456 đ'), findsWidgets);
    for (final key in [
      'report-date-range',
      'report-quick-range-all',
      'report-cash-type',
    ]) {
      expect(t.getSize(find.byKey(ValueKey(key))).height, 48);
    }
    await t.tap(find.widgetWithText(Tab, 'Tồn kho'));
    await t.pumpAndSettle();
    expect(find.text('Số dư hiện tại'), findsNothing);
    expect(find.byKey(const ValueKey('report-date-range')), findsNothing);
    await t.tap(find.widgetWithText(Tab, 'Công nợ'));
    await t.pumpAndSettle();
    expect(find.text('Gốc cầm đồ đang cầm'), findsNothing);
    await t.tap(find.widgetWithText(Tab, 'Cầm đồ'));
    await t.pumpAndSettle();
    expect(find.text('Dư nợ'), findsOneWidget);
    final pawnTabsBefore = t.getRect(find.byType(SegmentedButton<ReportKind>));
    expect(pawnTabsBefore.height, 48);
    expect(find.byKey(const ValueKey('report-date-range')), findsNothing);
    await t.tap(find.text('Phát sinh'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('report-date-range')), findsOneWidget);
    final tabRect = t.getRect(find.text('Phát sinh'));
    final dateRect = t.getRect(find.byKey(const ValueKey('report-date-range')));
    final pawnTabsAfter = t.getRect(find.byType(SegmentedButton<ReportKind>));
    expect(pawnTabsAfter.height, dateRect.height);
    expect(pawnTabsAfter.top, pawnTabsBefore.top);
    final quickRect = t.getRect(
      find.byKey(const ValueKey('report-quick-range-all')),
    );
    expect(dateRect.center.dy, closeTo(tabRect.center.dy, 1));
    expect(quickRect.center.dy, closeTo(tabRect.center.dy, 1));
    await t.tap(find.text('Dư nợ'));
    await t.pumpAndSettle();
    expect(find.byTooltip('Cập nhật báo cáo'), findsNothing);
    await t.tap(find.widgetWithText(Tab, 'Tồn kho'));
    await t.pumpAndSettle();
    repo.fail = true;
    await t.tap(find.byTooltip('Cập nhật báo cáo'));
    await t.pumpAndSettle();
    expect(
      find.text('Chưa tải được báo cáo. Vui lòng thử lại.'),
      findsOneWidget,
    );
    repo.fail = false;
    await t.tap(find.text('Thử lại'));
    await t.pumpAndSettle();
    expect(find.text('Số dư hiện tại'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('All report layouts fit a narrow window', (t) async {
    t.view.physicalSize = const Size(420, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final repo = FakeReportsRepository();
    repo.source = {
      'ThuChiKhac': [
        {'NgayThang': DateTime.now(), 'ThuChi': true, 'SoTien': 1000},
      ],
    };
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportsView(initialKind: ReportKind.sales, repository: repo),
        ),
      ),
    );
    await t.pumpAndSettle();
    for (final title in [
      'Bán hàng',
      'Nhập hàng',
      'Tồn kho',
      'Công nợ',
      'Thu chi',
      'Cầm đồ',
    ]) {
      final tab = find.widgetWithText(Tab, title);
      await t.ensureVisible(tab);
      await t.tap(tab);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    }
  });
  testWidgets(
    'Sales customer and all product lines remain visible in expanding rows',
    (t) async {
      t.view.physicalSize = const Size(1400, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final repo = FakeReportsRepository();
      repo.source = {
        'HoaDonBan': [
          {
            'IdHoaDon': 12345,
            'IdKH': 1,
            'NgayMua': DateTime.now(),
            'TongTienHang': 12000,
            'TongThanhToan': 12000,
            'PhienBanBanHang': 3,
          },
        ],
        'KhachHang': [
          {'IdKH': 1, 'TenKhachHang': 'Nguyễn Văn An'},
        ],
        'ChiTietHoaDonBan': [
          for (var i = 1; i <= 12; i++)
            {
              'IdHoaDon': 12345,
              'TenSanPham': 'Dịch vụ bảo dưỡng số $i',
              'LoaiSanPham': 'dich_vu',
              'SoLuong': 1,
              'DonGia': 1000,
              'DongSo': i,
            },
        ],
        'SoNo': [
          {'IdHoaDon': 12345, 'SoTienDaTra': 12000, 'SoTienConNo': 0},
        ],
      };
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportsView(initialKind: ReportKind.sales, repository: repo),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('Nguyễn Văn An'), findsOneWidget);
      expect(find.text('Mã: 12345'), findsOneWidget);
      final names = find.textContaining('Dịch vụ bảo dưỡng số 12');
      expect(names, findsOneWidget);
      expect(t.getSize(names).height, greaterThan(64));
      expect(t.takeException(), isNull);
      for (final width in [900.0, 760.0, 420.0]) {
        t.view.physicalSize = Size(width, 1000);
        await t.pumpAndSettle();
        expect(find.textContaining('Nguyễn Văn An'), findsOneWidget);
        expect(find.textContaining('Dịch vụ bảo dưỡng số 12'), findsOneWidget);
        expect(t.takeException(), isNull);
      }
    },
  );
  testWidgets('Sales totals stay below their matching columns', (t) async {
    t.view.physicalSize = const Size(1400, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final repo = FakeReportsRepository();
    repo.source = {
      'HoaDonBan': [
        {
          'IdHoaDon': 1,
          'NgayMua': DateTime.now(),
          'TongTienHang': 1000,
          'GiamGia': 100,
          'TongThanhToan': 900,
        },
      ],
      'ChiTietHoaDonBan': [
        {'IdHoaDon': 1, 'IdXe': 1, 'SoLuong': 1, 'DonGia': 1000},
      ],
      'Xe': [
        {'IdXe': 1, 'GiaNhap': 500, 'GiaBan': 1000, 'ChiPhi': []},
      ],
      'SoNo': [
        {'IdHoaDon': 1, 'SoTienDaTra': 600, 'SoTienConNo': 300},
      ],
    };
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportsView(initialKind: ReportKind.sales, repository: repo),
        ),
      ),
    );
    await t.pumpAndSettle();
    for (final entry in {
      'Tiền hàng': 'Bán hàng',
      'Giảm giá': 'Bán hàng',
      'Doanh thu': 'Bán hàng',
      'Đã thu': 'Thanh toán',
      'Còn nợ': 'Thanh toán',
      'Giá nhập': 'Giá vốn',
      'Chi phí': 'Giá vốn',
      'Lợi nhuận': 'Lợi nhuận',
    }.entries) {
      final heading = t.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('fixed-table-heading')),
          matching: find.text(entry.value),
        ),
      );
      final total = t.getRect(
        find.byKey(ValueKey('report-total-${entry.key}')),
      );
      expect(total.left, closeTo(heading.left, 0.1));
      expect(total.top, greaterThan(heading.bottom));
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('fixed-table-heading')),
        matching: find.text('Số đơn'),
      ),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('sales-order-chart')), findsOneWidget);
    expect(find.byKey(const ValueKey('sales-revenue-pie')), findsOneWidget);
    expect(
      t.getSize(find.byKey(const ValueKey('sales-order-chart'))).height,
      t.getSize(find.byKey(const ValueKey('sales-revenue-pie'))).height,
    );
    for (final label in ['Xe mới', 'Xe cũ', 'Phụ tùng', 'Dịch vụ']) {
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('sales-revenue-pie')),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'Customer debt stays visible and pawn balances are shown only in pawn tab',
    (t) async {
      t.view.physicalSize = const Size(1400, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final repo = FakeReportsRepository();
      ReportKind? exportedKind;
      ReportSection? exported;
      repo.source = {
        'HoaDonBan': [
          {'IdHoaDon': 1},
          {'IdHoaDon': 2},
        ],
        'SoNo': [
          {'IdHoaDon': 1, 'SoTienConNo': 100000},
          {'IdHoaDon': 2, 'SoTienConNo': -5000},
        ],
        'KhachHang': [
          {'IdKH': 1, 'TenKhachHang': 'Khách cầm đồ'},
        ],
        'CamDo': [
          {
            'IdCamDo': 10,
            'IdKhachHang': 1,
            'TaiSanTheChap': 'Xe kiểm tra',
            'NgayVay': DateTime(2025, 1, 1),
            'SoTienVay': 500000,
            'TrangThai': false,
          },
        ],
        'TraNoCamDo': [
          {
            'IdTraNoCamDo': 123,
            'IdCamDo': 10,
            'TienGoc': 100000,
            'LaiThu': 5000,
            'NgayTra': DateTime.now(),
          },
        ],
      };
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportsView(
              initialKind: ReportKind.sales,
              repository: repo,
              exportReport: (kind, section, range, time) async {
                exportedKind = kind;
                exported = section;
                return true;
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(Tab, 'Công nợ'));
      await t.pumpAndSettle();
      expect(find.text('100.000 đ'), findsOneWidget);
      expect(find.text('Số dư âm'), findsNothing);
      expect(find.text('Chưa rõ số dư'), findsNothing);
      expect(find.text('Gốc cầm đồ đang cầm'), findsNothing);
      await t.tap(find.widgetWithText(Tab, 'Cầm đồ'));
      await t.pumpAndSettle();
      expect(find.text('Khách cầm đồ'), findsOneWidget);
      expect(find.text('Xe kiểm tra'), findsOneWidget);
      expect(find.text('400.000 đ'), findsWidgets);
      expect(find.text('Số dư hiện tại'), findsNothing);
      await t.tap(find.text('Phát sinh'));
      await t.pumpAndSettle();
      expect(find.text('Khách cầm đồ'), findsNothing);
      await t.tap(find.text('Thu nợ cầm đồ'));
      await t.pumpAndSettle();
      expect(find.text('Khách cầm đồ'), findsOneWidget);
      expect(find.text('123'), findsOneWidget);
      expect(find.text('100.000 đ'), findsWidgets);
      expect(find.text('5.000 đ'), findsWidgets);
      await t.tap(find.byKey(const ValueKey('report-export-excel')));
      await t.pumpAndSettle();
      expect(exportedKind, ReportKind.pawnCollections);
      expect(exported?.rows.length, 1);
      expect(exported?.totals['Gốc đã thu'], 100000);
      expect(exported?.totals['Lãi thực thu'], 5000);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('Cash select updates rows, footer and exported snapshot', (
    t,
  ) async {
    t.view.physicalSize = const Size(1400, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final repo = FakeReportsRepository();
    final date = DateTime.now();
    repo.source = {
      'ThuChiKhac': [
        {
          'ThuChiId': 1,
          'NgayThang': date,
          'ThuChi': true,
          'SoTien': 1000,
          'LyDo': 'Khoản thu A',
        },
        {
          'ThuChiId': 2,
          'NgayThang': date,
          'ThuChi': false,
          'SoTien': 400,
          'LyDo': 'Khoản chi B',
        },
      ],
    };
    ReportSection? exported;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportsView(
            initialKind: ReportKind.sales,
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
    await t.tap(find.widgetWithText(Tab, 'Thu chi'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('report-cash-type')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('report-cash-type')));
    await t.pumpAndSettle();
    await t.tap(find.text('Chi').last);
    await t.pumpAndSettle();
    expect(find.text('Khoản thu A'), findsNothing);
    expect(find.text('Khoản chi B'), findsOneWidget);
    expect(find.textContaining('Chi: 400 đ'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('report-export-excel')));
    await t.pumpAndSettle();
    expect(exported?.rows.length, 1);
    expect(exported?.rows.single[2], 'Chi');
    expect(exported?.totals['Chi'], 400);
    await t.tap(find.byKey(const ValueKey('report-cash-type')));
    await t.pumpAndSettle();
    await t.tap(find.text('Thu').last);
    await t.pumpAndSettle();
    expect(find.text('Khoản thu A'), findsOneWidget);
    expect(find.text('Khoản chi B'), findsNothing);
    await t.tap(find.byKey(const ValueKey('report-cash-type')));
    await t.pumpAndSettle();
    await t.tap(find.text('Tất cả').last);
    await t.pumpAndSettle();
    expect(find.text('Khoản thu A'), findsOneWidget);
    expect(find.text('Khoản chi B'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'Detailed customer and supplier debt tabs export current balances without search',
    (t) async {
      t.view.physicalSize = const Size(1400, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final repo = FakeReportsRepository();
      repo.source = {
        'HoaDonBan': [
          {
            'IdHoaDon': 1,
            'IdKH': 1,
            'NgayMua': DateTime(2024, 1, 1),
            'TongThanhToan': 1000000,
          },
        ],
        'KhachHang': [
          {
            'IdKH': 1,
            'TenKhachHang': 'Khách A',
            'SoDienThoai': '091111',
            'DiaChiChiTiet': 'Địa chỉ A',
          },
        ],
        'SoNo': [
          {'IdHoaDon': 1, 'SoTienDaTra': 700000, 'SoTienConNo': 300000},
        ],
        'NhapHang': [
          {
            'IdNhapHang': 10,
            'NgayNhap': DateTime(2024, 1, 1),
            'IdDoiTac': 'p1',
            'SoTien': 2000000,
            'SoTienDaTra': 1200000,
            'SoTienConNo': 800000,
          },
        ],
        'DoiTac': [
          {
            '_id': 'p1',
            'TenDoiTac': 'Nhà cung cấp B',
            'SoDienThoai': '092222',
            'DiaChi': 'Địa chỉ B',
          },
        ],
      };
      ReportKind? exportedKind;
      ReportSection? exported;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportsView(
              initialKind: ReportKind.sales,
              repository: repo,
              exportReport: (kind, section, range, time) async {
                exportedKind = kind;
                exported = section;
                return true;
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(Tab, 'Công nợ'));
      await t.pumpAndSettle();
      await t.tap(find.text('Khách nợ bán hàng'));
      await t.pumpAndSettle();
      expect(find.textContaining('Khách A'), findsOneWidget);
      expect(find.byKey(const ValueKey('report-date-range')), findsNothing);
      expect(find.byKey(const ValueKey('report-debt-search')), findsNothing);
      await t.tap(find.byKey(const ValueKey('report-export-excel')));
      await t.pumpAndSettle();
      expect(exportedKind, ReportKind.customerDebt);
      expect(exported?.totals['Còn nợ'], 300000);
      await t.tap(find.text('Nợ nhà cung cấp'));
      await t.pumpAndSettle();
      expect(find.textContaining('Nhà cung cấp B'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('report-export-excel')));
      await t.pumpAndSettle();
      expect(exportedKind, ReportKind.supplierDebt);
      expect(exported?.rows.single[0], 10);
      expect(exported?.totals['Còn nợ'], 800000);
      t.view.physicalSize = const Size(420, 1000);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Repayment parent tab switches four reports and exports each independently',
    (t) async {
      t.view.physicalSize = const Size(1400, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final repo = FakeReportsRepository(), date = DateTime.now();
      repo.source = {
        'HoaDonBan': [
          {'IdHoaDon': 1, 'IdKH': 1},
        ],
        'SoNo': [
          {'IdSoNo': 11, 'IdHoaDon': 1},
        ],
        'KhachHang': [
          {'IdKH': 1, 'TenKhachHang': 'Khách A'},
        ],
        'NhapHang': [
          {'IdNhapHang': 2, 'NoiNhap': 'Nhà cung cấp B'},
        ],
        'NoCu': [
          {'Id': 3, 'IdKH': '1'},
        ],
        'VayVon': [
          {'IdVayVon': 4, 'DoiTac': 'Người cho vay C'},
        ],
        'TraNo': [
          {
            'IdTraNo': 1,
            'IdSoNo': 11,
            'NgayTra': date,
            'SotienTra': 100,
            'LaiThu': 10,
            'SoCoNo': 0,
          },
        ],
        'TraNoNhapHang': [
          {
            'IdTraNoNhapHang': 2,
            'IdNhapHang': 2,
            'NgayTra': date,
            'SoTienTra': 200,
            'SoCoNo': 0,
          },
        ],
        'TraNoCu': [
          {
            'Id': 3,
            'IdNoCu': 3,
            'NgayTra': date,
            'SoTienTra': 300,
            'LaiThu': 30,
            'ConNo': 0,
          },
        ],
        'TraNoVayVon': [
          {
            'IdTraNoVayVon': 4,
            'IdVayVon': 4,
            'NgayTra': date,
            'SoTienTraGoc': 400,
            'SoTienTraLai': 40,
            'ConNoGoc': 0,
          },
        ],
      };
      ReportKind? exportedKind;
      ReportSection? exported;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportsView(
              initialKind: ReportKind.sales,
              repository: repo,
              exportReport: (kind, section, range, time) async {
                exportedKind = kind;
                exported = section;
                return true;
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final parent = find.widgetWithText(Tab, 'Trả nợ');
      await t.ensureVisible(parent);
      await t.tap(parent);
      await t.pumpAndSettle();
      for (final kind in [
        ReportKind.customerRepayments,
        ReportKind.supplierRepayments,
        ReportKind.oldDebtRepayments,
        ReportKind.fundingRepayments,
      ]) {
        final selector = find.text(kind.label);
        await t.ensureVisible(selector);
        await t.tap(selector);
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('report-date-range')), findsOneWidget);
        expect(find.byTooltip('Cập nhật báo cáo'), findsNothing);
        await t.tap(find.byKey(const ValueKey('report-export-excel')));
        await t.pumpAndSettle();
        expect(exportedKind, kind);
        expect(exported?.rows.length, 1);
        expect(exported?.totals.containsKey('Còn nợ sau trả'), false);
      }
      t.view.physicalSize = const Size(420, 1000);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('Report lists every voucher and exports all filtered rows', (
    t,
  ) async {
    t.view.physicalSize = const Size(1400, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final repo = FakeReportsRepository();
    ReportSection? exported;
    ReportRange? exportedRange;
    repo.source = {
      'ThuChiKhac': [
        for (var i = 0; i < 35; i++)
          {
            'ThuChiId': i + 1,
            'NgayThang': DateTime(2025, 1, 1),
            'ThuChi': true,
            'SoTien': 1000,
          },
      ],
    };
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportsView(
            initialKind: ReportKind.sales,
            repository: repo,
            exportReport: (kind, section, range, time) async {
              expect(kind, ReportKind.cash);
              exported = section;
              exportedRange = range;
              return true;
            },
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Chọn nhanh thời gian'));
    await t.pumpAndSettle();
    await t.tap(find.text('Tất cả thời gian'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(Tab, 'Thu chi'));
    await t.pumpAndSettle();
    expect(find.byTooltip('Trang sau'), findsNothing);
    expect(find.text('35 dòng'), findsNothing);
    expect(find.textContaining('35.000 đ'), findsWidgets);
    final footerBefore = t.getRect(
      find.byKey(const ValueKey('fixed-table-footer')),
    );
    final exportRect = t.getRect(
      find.byKey(const ValueKey('report-export-excel')),
    );
    expect(exportRect.right, greaterThan(1300));
    final dateRect = t.getRect(find.byKey(const ValueKey('report-date-range')));
    expect(exportRect.center.dy, closeTo(dateRect.center.dy, 2));
    expect(find.textContaining('Doanh thu ='), findsNothing);
    await t.drag(
      find.byKey(const ValueKey('fixed-table-body')),
      const Offset(0, -3000),
    );
    await t.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    expect(
      t.getRect(find.byKey(const ValueKey('fixed-table-footer'))),
      footerBefore,
    );
    await t.tap(find.byKey(const ValueKey('report-export-excel')));
    await t.pumpAndSettle();
    expect(exported?.rows.length, 35);
    expect(exportedRange?.from, isNull);
    expect(find.text('Xuất Excel thành công'), findsOneWidget);
    expect(find.textContaining('35.000 đ'), findsWidgets);
    expect(t.takeException(), isNull);
  });
}
