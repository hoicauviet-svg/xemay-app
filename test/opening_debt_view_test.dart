import 'support/fake_opening_debt_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/views/finance/opening_debt_tab.dart';

void main() {
  testWidgets(
    'Old debt has no create action; filters and repays with source fields',
    (t) async {
      t.view.physicalSize = const Size(1400, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final repo = FakeDebts();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: OpeningDebtTab(repository: repo)),
        ),
      );
      await t.pumpAndSettle();
      expect(repo.status, 'open');
      expect(find.byIcon(Icons.add), findsNothing);
      await t.enterText(
        find.byKey(const ValueKey('opening-debt-search')),
        'Khách',
      );
      await t.pump(const Duration(milliseconds: 350));
      await t.pumpAndSettle();
      expect(repo.search, 'Khách');
      await t.tap(find.byTooltip('Lọc nợ cũ'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(CheckedPopupMenuItem<String>, 'Tất cả'));
      await t.pumpAndSettle();
      expect(repo.status, 'all');
      await t.tap(find.text('17'));
      await t.pumpAndSettle();
      expect(find.text('Nợ cũ #17'), findsOneWidget);
      await t.tap(find.widgetWithText(Tab, 'Trả nợ'));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('opening-payment-principal')),
        '800001',
      );
      await t.tap(find.widgetWithText(FilledButton, 'Trả nợ'));
      await t.pumpAndSettle();
      expect(find.text('Tiền trả nợ vượt số còn nợ'), findsOneWidget);
      expect(repo.saved, isNull);
      await t.enterText(
        find.byKey(const ValueKey('opening-payment-principal')),
        '100000',
      );
      await t.enterText(
        find.byKey(const ValueKey('opening-payment-interest')),
        '10000',
      );
      await t.enterText(
        find.byKey(const ValueKey('opening-payment-collected')),
        '5000',
      );
      await t.tap(find.widgetWithText(FilledButton, 'Trả nợ'));
      await t.pumpAndSettle();
      expect(repo.saved?.principal, 100000);
      expect(repo.saved?.interest, 10000);
      expect(repo.saved?.collectedInterest, 5000);
      expect(repo.debt['SoCoNo'], 700000);
      expect(find.text('Trả nợ thành công'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('Old debt list fits narrow window', (t) async {
    t.view.physicalSize = const Size(420, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: OpeningDebtTab(repository: FakeDebts())),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('#17 · Khách thử'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
