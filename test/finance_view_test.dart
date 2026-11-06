import 'support/fake_finance_repository.dart';
import 'package:xemay_app/controllers/finance_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/views/finance/finance_tab.dart';
import 'package:xemay_app/views/finance/funding_details_screen.dart';

void main() {
  test(
    'Date range resets paging, preserves other filters and can be cleared',
    () async {
      final repo = FakeFinance();
      final controller = FinanceController(repo, loans: false);
      controller.search = 'Thu thử';
      controller.filter = 'income';
      controller.page = 2;
      controller.setDateRange(
        DateTime(2026, 2, 1, 12),
        DateTime(2026, 2, 2, 23),
      );
      await controller.load();
      expect(controller.page, 0);
      expect(controller.search, 'Thu thử');
      expect(repo.filter, 'income');
      expect(repo.from, DateTime.utc(2026, 2, 1));
      expect(repo.to, DateTime.utc(2026, 2, 2));
      controller.setDateRange(null, null);
      await controller.load();
      expect(repo.from, isNull);
      expect(repo.to, isNull);
      controller.dispose();
    },
  );

  testWidgets('Cash lists, filters and creates matching source fields', (
    t,
  ) async {
    t.view.physicalSize = const Size(1400, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final repo = FakeFinance();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FinanceTab(loans: false, repository: repo)),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Thu thử'), findsOneWidget);
    await t.tap(find.byTooltip('Lọc thu/chi'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(CheckedPopupMenuItem<String>, 'Chi'));
    await t.pumpAndSettle();
    expect(repo.filter, 'expense');
    await t.tap(find.byKey(const ValueKey('cash-add')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('cash-amount')), '125000');
    await t.enterText(find.byKey(const ValueKey('cash-reason')), 'Thu mới');
    await t.tap(find.text('Lưu'));
    await t.pumpAndSettle();
    expect(repo.saved?.amount, '125000');
    expect(repo.saved?.income, true);
    expect(find.text('Đã lưu khoản thu/chi #2'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'Funding default open and full detail payment blocks excess principal',
    (t) async {
      t.view.physicalSize = const Size(1400, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final repo = FakeFinance();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FinanceTab(loans: true, repository: repo)),
        ),
      );
      await t.pumpAndSettle();
      expect(repo.filter, 'open');
      await t.tap(find.text('Người cho vay'));
      await t.pumpAndSettle();
      expect(find.byType(FundingDetailsScreen), findsOneWidget);
      await t.tap(find.widgetWithText(Tab, 'Thanh toán'));
      await t.pumpAndSettle();
      final principal = find.byKey(const ValueKey('funding-payment-principal'));
      await t.enterText(principal, '1000001');
      await t.tap(find.widgetWithText(FilledButton, 'Thanh toán'));
      await t.pumpAndSettle();
      expect(find.text('Tiền trả gốc vượt số còn nợ'), findsOneWidget);
      expect(repo.paid, isNull);
      await t.enterText(principal, '100000');
      await t.enterText(
        find.byKey(const ValueKey('funding-payment-interest')),
        '5000',
      );
      await t.tap(find.widgetWithText(FilledButton, 'Thanh toán'));
      await t.pumpAndSettle();
      expect(repo.paid?.principal, 100000);
      expect(repo.paid?.interest, 5000);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('Cash and funding fit narrow screens', (t) async {
    t.view.physicalSize = const Size(420, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    for (final loans in [false, true]) {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FinanceTab(
              key: ValueKey(loans),
              loans: loans,
              repository: FakeFinance(),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    }
  });
}
