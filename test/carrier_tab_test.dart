import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/models/dashboard/dashboard_group.dart';
import 'package:xemay_app/models/dashboard/dashboard_module.dart';
import 'package:xemay_app/views/directory/carrier_tab.dart';
import 'support/fake_directory_repository.dart';

void main() {
  testWidgets('Vận chuyển có tab riêng, tìm kiếm và xóa khỏi danh sách', (
    tester,
  ) async {
    expect(DashboardGroup.partners.modules, contains(DashboardModule.carriers));
    final repository = FakeDirectoryRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CarrierTab(repository: repository)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Người giao thử'), findsOneWidget);
    expect(find.textContaining('TEST-01'), findsOneWidget);
    expect(find.text('Nơi nhập thử'), findsNothing);
    await tester.enterText(find.byType(TextField), 'không có');
    await tester.pump();
    expect(find.text('Người giao thử'), findsNothing);
    await tester.enterText(find.byType(TextField), 'TEST-01');
    await tester.pump();
    await tester.tap(find.byTooltip('Xóa'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Xóa'));
    await tester.pumpAndSettle();
    expect(find.text('Người giao thử'), findsNothing);
    expect(repository.entries.where((e) => e.id == 'carrier-test'), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
