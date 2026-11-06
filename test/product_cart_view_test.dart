import 'support/fake_database_settings_repository.dart';
import 'support/fake_sales_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/controllers/cart_controller.dart';
import 'package:xemay_app/app.dart';
import 'support/fake_inventory_repository.dart';

void main() {
  testWidgets('Filter and row action update shared cart', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FakeInventoryRepository();
    await tester.pumpWidget(
      StoreApp(
        databaseSettingsRepositoryFactory: FakeDatabaseSettingsRepository.new,
        salesRepositoryFactory: FakeSalesRepository.new,
        inventoryRepositoryFactory: () => repository,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Mở bán hàng'), findsOneWidget);
    await tester.tap(find.text('Sản phẩm').first);
    await tester.pumpAndSettle();
    expect(repository.lastAvailability, 'available');
    expect(find.text('TỒN KHO'), findsOneWidget);
    expect(find.text('THÔNG TIN'), findsOneWidget);
    expect(find.text('CHI PHÍ'), findsOneWidget);
    expect(find.text('Số khung: KHUNG-TEST'), findsOneWidget);
    final horizontal = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('fixed-table-horizontal')),
    );
    expect(horizontal.controller!.position.maxScrollExtent, 0);

    await tester.tap(find.byTooltip('Lọc sản phẩm'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is CheckedPopupMenuItem<String> && widget.value == 'all',
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.lastAvailability, 'all');
    await tester.tap(find.byTooltip('Thêm vào đơn bán hàng'));
    await tester.pumpAndSettle();
    expect(CartController.shared.count, 1);
    await tester.tap(find.text('Cài đặt').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mở bán hàng'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Tab, 'Bán hàng'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Xe kiểm thử'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('sales-price-xe-7')),
      '1000000',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cài đặt').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mở bán hàng'));
    await tester.pumpAndSettle();
    expect(CartController.shared.count, 1);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('sales-price-xe-7')))
          .initialValue,
      '1000000',
    );
    await tester.tap(find.byTooltip('Bỏ khỏi đơn'));
    await tester.pumpAndSettle();
    expect(CartController.shared.count, 0);
  });
}
