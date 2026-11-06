import 'support/fake_sales_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/app.dart';
import 'package:xemay_app/controllers/cart_controller.dart';
import 'support/fake_inventory_repository.dart';
import 'support/fake_service_repository.dart';

void main() {
  testWidgets(
    'Service form validates name and price, retries save and searches description',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeServiceRepository();
      await tester.pumpWidget(
        StoreApp(
          salesRepositoryFactory: FakeSalesRepository.new,
          inventoryRepositoryFactory: FakeInventoryRepository.new,
          serviceRepositoryFactory: () => repository,
        ),
      );
      await tester.tap(find.text('Sản phẩm').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'Dịch vụ'));
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('service-search'));
      final add = find.byKey(const ValueKey('service-add'));
      expect(tester.getSize(search).height, 48);
      expect(tester.getSize(add).height, 48);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNWidgets(3));
      await tester.tap(find.text('Lưu dịch vụ'));
      await tester.pumpAndSettle();
      expect(find.text('Vui lòng nhập tên dịch vụ'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('service-name')),
        'Thay dầu',
      );
      await tester.enterText(
        find.byKey(const ValueKey('service-description')),
        'Dầu động cơ',
      );
      await tester.enterText(
        find.byKey(const ValueKey('service-price')),
        '-100',
      );
      await tester.tap(find.text('Lưu dịch vụ'));
      await tester.pumpAndSettle();
      expect(repository.items, isEmpty);
      expect(
        find.text('Nhập giá tiền từ 0 đồng, chỉ gồm chữ số'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('service-price')),
        '150000',
      );
      repository.failSave = true;
      await tester.tap(find.text('Lưu dịch vụ'));
      await tester.pumpAndSettle();
      expect(
        find.text('Không lưu được dịch vụ. Vui lòng thử lại.'),
        findsOneWidget,
      );
      repository.failSave = false;
      await tester.tap(find.text('Lưu dịch vụ'));
      await tester.pumpAndSettle();
      expect(find.text('Thay dầu'), findsOneWidget);
      expect(find.text('150.000 đ'), findsNWidgets(2));
      expect(repository.items.single.description, 'Dầu động cơ');
      await tester.tap(find.byTooltip('Thêm dịch vụ vào đơn bán hàng'));
      await tester.pumpAndSettle();
      expect(CartController.shared.items.single.service, isTrue);
      expect(CartController.shared.items.single.unitPrice, 150000);
      CartController.shared.clear();
      await tester.enterText(
        find.descendant(of: search, matching: find.byType(TextField)),
        'động cơ',
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.text('Thay dầu'), findsOneWidget);
      await tester.enterText(
        find.descendant(of: search, matching: find.byType(TextField)),
        'không có',
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.text('Không tìm thấy dịch vụ.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
