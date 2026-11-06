import 'package:xemay_app/views/reports/reports_view.dart';
import 'package:xemay_app/controllers/reports_controller.dart';
import 'support/fake_reports_repository.dart';
import 'package:xemay_app/models/reports/report_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/core/theme/app_theme.dart';
import 'package:xemay_app/models/finance/cash_category.dart';
import 'package:xemay_app/views/finance/cash_categories_popup.dart';
import 'package:xemay_app/views/finance/finance_editor_popup.dart';
import 'support/fake_finance_repository.dart';

void main() {
  testWidgets(
    'cash report opens category totals in a separate page and returns to vouchers',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.now();
      final repo = FakeReportsRepository()
        ..source = {
          'ThuChiKhac': [
            {
              'ThuChiId': 1,
              'NgayThang': now,
              'ThuChi': false,
              'SoTien': 150000,
              'TenDanhMuc': 'Chi phí sản phẩm',
              'LyDo': 'Sửa xe',
            },
            {
              'ThuChiId': 2,
              'NgayThang': now,
              'ThuChi': false,
              'SoTien': 50000,
              'TenDanhMuc': 'Chi phí sản phẩm',
              'LyDo': 'Sơn xe',
            },
          ],
        };
      ReportSection? exported;
      await tester.pumpWidget(
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
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'Thu chi'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cash-category-summary')), findsNothing);
      expect(find.text('Sửa xe'), findsOneWidget);
      final buttonRect = tester.getRect(
        find.byKey(const ValueKey('cash-category-details')),
      );
      final footerRect = tester.getRect(
        find.byKey(const ValueKey('fixed-table-footer')),
      );
      expect(footerRect.contains(buttonRect.center), true);
      final totalsRect = tester.getRect(
        find.byKey(const ValueKey('report-total-Số tiền')),
      );
      expect(buttonRect.center.dy, closeTo(totalsRect.center.dy, 2));
      await tester.tap(find.byKey(const ValueKey('cash-category-details')));
      await tester.pumpAndSettle();
      final summary = find.byKey(const ValueKey('cash-category-summary'));
      expect(summary, findsOneWidget);
      expect(
        find.descendant(of: summary, matching: find.text('Thu')),
        findsNothing,
      );
      expect(
        find.descendant(of: summary, matching: find.text('Chi')),
        findsNothing,
      );
      expect(find.text('Chi phí sản phẩm'), findsOneWidget);
      expect(find.textContaining('200.000 đ'), findsOneWidget);
      expect(find.text('Sửa xe'), findsNothing);
      await tester.tap(find.byTooltip('Quay lại'));
      await tester.pumpAndSettle();
      expect(find.text('Chi phí sản phẩm'), findsWidgets);
      expect(find.text('Sửa xe'), findsOneWidget);
      expect(find.textContaining('200.000 đ'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('report-export-excel')));
      await tester.pumpAndSettle();
      expect(exported?.rows.length, 2);
      expect(
        exported?.rows.map((r) => r[3]),
        containsAll(['Sửa xe', 'Sơn xe']),
      );
      expect(find.text('Sửa xe'), findsOneWidget);
      expect(find.text('Sơn xe'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'category totals sum vouchers, keep types separate and preserve unknown amounts',
    () {
      final section = ReportSection(
        columns: const [],
        rows: [
          [1, null, 'Chi', 'Sửa', 150000, 'Chi phí sản phẩm'],
          [2, null, 'Chi', 'Sơn', 50000, 'Chi phí sản phẩm'],
          [3, null, 'Thu', 'Lãi A', 40000, 'Lãi khách hàng trả nợ'],
          [4, null, 'Thu', 'Lãi B', 60000, 'Lãi khách hàng trả nợ'],
          [5, null, 'Chi', 'Chưa rõ tiền', null, 'Điện nước'],
        ],
        totals: const {'Thu': 100000, 'Chi': null},
      );
      final grouped = ReportCalculator.cashCategoryTotals(section);
      expect(grouped.rows.firstWhere((r) => r[0] == 'Chi phí sản phẩm'), [
        'Chi phí sản phẩm',
        0,
        200000,
      ]);
      expect(grouped.rows.firstWhere((r) => r[0] == 'Lãi khách hàng trả nợ'), [
        'Lãi khách hàng trả nợ',
        100000,
        0,
      ]);
      expect(grouped.rows.firstWhere((r) => r[0] == 'Điện nước')[2], isNull);
      expect(grouped.totals, section.totals);
      expect(
        ReportCalculator.cashCategoryTotals(
          ReportSection(
            columns: const [],
            rows: const [],
            totals: const {'Thu': 0, 'Chi': 0},
          ),
        ).rows,
        isEmpty,
      );
    },
  );

  test(
    'report categories follow voucher type and reset when parent changes',
    () async {
      final repo = FakeReportsRepository()
        ..source = {
          'ThuChiKhac': [
            {
              'ThuChiId': 1,
              'NgayThang': DateTime(2026, 11, 4),
              'ThuChi': true,
              'SoTien': 10,
              'TenDanhMuc': 'Thu dịch vụ',
            },
            {
              'ThuChiId': 2,
              'NgayThang': DateTime(2026, 11, 4),
              'ThuChi': false,
              'SoTien': 20,
              'TenDanhMuc': 'Điện nước',
            },
          ],
        };
      final controller = ReportsController(repo, now: DateTime(2026, 11, 5));
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.cashCategories, isEmpty);
      controller.setCashType('expense');
      expect(controller.cashCategories, ['Điện nước']);
      controller.setCashCategory('Điện nước');
      controller.setCashType('income');
      expect(controller.cashCategory, isNull);
      expect(controller.cashCategories, ['Thu dịch vụ']);
      expect(controller.section(ReportKind.cash)!.totals['Thu'], 10);
    },
  );

  test(
    'cash category filter separates income/expense totals and removes difference',
    () {
      final source = ReportCalculator.build(
        range: ReportRange(
          from: DateTime(2026, 11, 1),
          to: DateTime(2026, 11, 30),
        ),
        source: {
          'ThuChiKhac': [
            {
              'ThuChiId': 1,
              'NgayThang': DateTime(2026, 11, 4),
              'ThuChi': false,
              'SoTien': 150000,
              'TenDanhMuc': 'Chi phí sản phẩm',
            },
            {
              'ThuChiId': 2,
              'NgayThang': DateTime(2026, 11, 4),
              'ThuChi': true,
              'SoTien': 40000,
              'LyDo': 'Thu tiền lãi nợ quá hạn khách hàng : A',
            },
            {
              'ThuChiId': 3,
              'NgayThang': DateTime(2026, 11, 4),
              'ThuChi': false,
              'SoTien': 500000,
            },
          ],
        },
      ).sections[ReportKind.cash]!;
      final selected = ReportCalculator.filterCash(
        source,
        'all',
        category: 'Chi phí sản phẩm',
      );
      expect(selected.rows.length, 1);
      expect(selected.totals, {'Thu': 0, 'Chi': 150000});
      expect(source.totals.containsKey('Chênh lệch'), false);
      expect(
        ReportCalculator.filterCash(
          source,
          'income',
          category: 'Lãi khách hàng trả nợ',
        ).totals,
        {'Thu': 40000, 'Chi': 0},
      );
    },
  );

  test('legacy interest classified without confusing pawn receipts', () {
    expect(
      CashCategory.nameFor({
        'ThuChi': true,
        'LyDo': 'Thu tiền lãi nợ quá hạn khách hàng : A',
      }),
      'Lãi khách hàng trả nợ',
    );
    expect(
      CashCategory.nameFor({
        'ThuChi': true,
        'LyDo': 'Thu tiền lãi cầm đồ khách hàng A',
      }),
      'Thu khác',
    );
  });
  testWidgets('cash editor selects and saves expense category', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeFinance();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: FinanceEditorPopup(loans: false, repository: repo),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cash-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chi').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate((w) => w is DropdownButtonFormField<String>),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Điện nước').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('cash-amount')), '200000');
    await tester.enterText(
      find.byKey(const ValueKey('cash-reason')),
      'Tháng 11',
    );
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(repo.saved?.categoryId, 'utilities');
    expect(repo.saved?.income, false);
  });
  testWidgets('category management adds a category', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeFinance();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: CashCategoriesPopup(repository: repo)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Điện nước'), findsOneWidget);
    expect(find.text('Lãi khách hàng trả nợ'), findsNothing);
    await tester.tap(find.text('Thu'));
    await tester.pumpAndSettle();
    expect(find.text('Điện nước'), findsNothing);
    expect(find.text('Lãi khách hàng trả nợ'), findsOneWidget);
    await tester.tap(find.text('Chi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thêm danh mục chi'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Thuê kho');
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(
      repo.categoryRows.any((c) => c.name == 'Thuê kho' && !c.income),
      true,
    );
    expect(find.text('Thuê kho'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
