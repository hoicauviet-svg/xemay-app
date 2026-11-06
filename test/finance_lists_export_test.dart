import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/app.dart';
import 'package:xemay_app/models/reports/report_models.dart';
import 'package:xemay_app/views/finance/finance_tab.dart';
import 'package:xemay_app/views/finance/opening_debt_tab.dart';
import 'support/fake_finance_repository.dart';
import 'support/fake_opening_debt_repository.dart';
import 'support/fake_reports_repository.dart';
import 'support/fake_inventory_repository.dart';
import 'support/fake_sales_repository.dart';
import 'support/fake_service_repository.dart';

void main() {
  testWidgets('Debt report opens the corresponding finance tab', (t) async {
    t.view.physicalSize = const Size(1400, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      StoreApp(
        reportsRepositoryFactory: FakeReportsRepository.new,
        financeRepositoryFactory: FakeFinance.new,
        openingDebtRepositoryFactory: FakeDebts.new,
        inventoryRepositoryFactory: FakeInventoryRepository.new,
        salesRepositoryFactory: FakeSalesRepository.new,
        serviceRepositoryFactory: FakeServiceRepository.new,
      ),
    );
    await t.pumpAndSettle();
    for (final entry in {'Vay vốn': 1, 'Nợ cũ': 2}.entries) {
      await t.tap(find.text('Báo cáo').first);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(Tab, 'Công nợ'));
      await t.pumpAndSettle();
      await t.tap(find.text(entry.key));
      await t.pumpAndSettle();
      expect(
        DefaultTabController.of(t.element(find.byType(TabBar))).index,
        entry.value,
      );
      expect(
        find.byKey(
          ValueKey(entry.value == 1 ? 'funding-search' : 'opening-debt-search'),
        ),
        findsOneWidget,
      );
    }
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'Unpaged funding and old debt lists total and export all 35 rows',
    (t) async {
      t.view.physicalSize = const Size(1400, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      for (final funding in [true, false]) {
        final loans = FakeFinance()
          ..fundingRows = [
            for (var i = 1; i <= 35; i++)
              {
                'IdVayVon': i,
                'DoiTac': 'Đối tác $i',
                'SoTienVay': 1000000,
                'TongConNo': 800000,
              },
          ];
        final debts = FakeDebts()
          ..debtRows = [
            for (var i = 1; i <= 35; i++)
              {
                'Id': i,
                'KhachHang': {'TenKhachHang': 'Khách $i'},
                'TongNo': 1000000,
                'SoTienDaTra': 200000,
                'SoCoNo': 800000,
              },
          ];
        ReportSection? exported;
        String? title;
        Future<bool> save(
          String name,
          ReportSection section,
          DateTime date,
        ) async {
          title = name;
          exported = section;
          return true;
        }

        await t.pumpWidget(
          MaterialApp(
            key: ValueKey(funding),
            home: Scaffold(
              body: funding
                  ? FinanceTab(
                      key: const ValueKey('loans'),
                      loans: true,
                      repository: loans,
                      exportReport: save,
                    )
                  : OpeningDebtTab(
                      key: const ValueKey('old-debts'),
                      repository: debts,
                      exportReport: save,
                    ),
            ),
          ),
        );
        await t.pumpAndSettle();
        final searchRect = t.getRect(
          find.byKey(
            ValueKey(funding ? 'funding-search' : 'opening-debt-search'),
          ),
        );
        final exportRect = t.getRect(
          find.byKey(
            ValueKey(
              funding ? 'funding-export-excel' : 'opening-debt-export-excel',
            ),
          ),
        );
        expect(exportRect.center.dy, closeTo(searchRect.center.dy, 0.1));
        expect(exportRect.height, searchRect.height);
        expect(find.byTooltip('Trang sau'), findsNothing);
        expect(find.byTooltip('Trang trước'), findsNothing);
        expect(find.text('35.000.000 đ'), findsOneWidget);
        expect(find.text('28.000.000 đ'), findsOneWidget);
        if (!funding) expect(find.text('7.000.000 đ'), findsOneWidget);
        await t.drag(
          find.byKey(const ValueKey('fixed-table-body')),
          const Offset(0, -4000),
        );
        await t.pumpAndSettle();
        expect(find.text(funding ? '#35' : '35'), findsOneWidget);
        await t.tap(
          find.byKey(
            ValueKey(
              funding ? 'funding-export-excel' : 'opening-debt-export-excel',
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(exported?.rows.length, 35);
        expect(title, funding ? 'Vay vốn' : 'Nợ cũ');
        expect(exported?.totals[funding ? 'Số tiền vay' : 'Tổng nợ'], 35000000);
        expect(t.takeException(), isNull);
      }
    },
  );
}
