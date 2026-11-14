import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/controllers/cart_controller.dart';
import 'package:xemay_app/controllers/sales_controller.dart';
import 'package:xemay_app/core/theme/app_theme.dart';
import 'package:xemay_app/models/inventory/inventory_models.dart';
import 'package:xemay_app/models/services/service_models.dart';
import 'package:xemay_app/views/sales/sales_tab.dart';
import 'support/fake_customer_repository.dart';
import 'support/fake_inventory_repository.dart';
import 'support/fake_sales_repository.dart';
import 'support/fake_service_repository.dart';

void main() {
  testWidgets(
    'Sales view edits order, selects real customer and previews without committing',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeCustomerRepository();
      final cart = CartController()
        ..add({
          'IdXe': 7,
          'IdSanPham': 1,
          'TenXe': 'Xe bán thử',
          'SoLuongTon': 1,
          'SoKhung': 'KHUNG-7',
        }, vehicle: true);
      final sale = SalesController(cart, repository);
      addTearDown(sale.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: SalesTab(controller: sale)),
        ),
      );
      void expectCustomerAlignment() {
        final input = tester.getRect(
          find.byKey(const ValueKey('sales-customer-surface')),
        );
        final add = tester.getRect(
          find.byKey(const ValueKey('sales-customer-add')),
        );
        expect(add.top, closeTo(input.top, .01));
        expect(add.bottom, closeTo(input.bottom, .01));
        expect(add.height, closeTo(input.height, .01));
      }

      final originalCustomerSection = tester.getRect(
        find.byKey(const ValueKey('sales-customer-section')),
      );
      final originalOrderSection = tester.getRect(
        find.byKey(const ValueKey('sales-order-section')),
      );
      final originalListTop = tester
          .getTopLeft(find.byKey(const ValueKey('sales-product-list')))
          .dy;
      void expectFixedSections() {
        expect(
          tester.getRect(find.byKey(const ValueKey('sales-customer-section'))),
          originalCustomerSection,
        );
        expect(
          tester.getRect(find.byKey(const ValueKey('sales-order-section'))),
          originalOrderSection,
        );
        expect(
          tester
              .getTopLeft(find.byKey(const ValueKey('sales-product-list')))
              .dy,
          originalListTop,
        );
      }

      expectCustomerAlignment();
      expect(find.text('Thêm sản phẩm / dịch vụ'), findsNothing);
      expect(find.text('Sản phẩm & dịch vụ (1)'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('sales-price-xe-7')),
        '1000000',
      );
      expect(find.text('1.000.000'), findsWidgets);
      await tester.enterText(
        find.byKey(const ValueKey('sales-customer-search')),
        'Khách',
      );
      await tester.pumpAndSettle();
      final customerInput = tester.getRect(
        find.byKey(const ValueKey('sales-customer-surface')),
      );
      final customerMenu = tester.getRect(
        find
            .ancestor(
              of: find.text('Khách kiểm thử'),
              matching: find.byType(Material),
            )
            .first,
      );
      expect((customerMenu.top - customerInput.bottom).abs(), lessThan(12));
      expect((customerMenu.left - customerInput.left).abs(), lessThan(12));
      await tester.tap(find.text('Khách kiểm thử'));
      await tester.pumpAndSettle();
      expect(sale.customer?['IdKH'], 1);
      expect(find.text('Địa chỉ: Thôn 1, Xã kiểm thử'), findsOneWidget);
      expectCustomerAlignment();
      expectFixedSections();
      await tester.tap(find.byTooltip('Thêm khách hàng mới'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('customer-name')),
        'Khách mới',
      );
      await tester.enterText(
        find.byKey(const ValueKey('customer-phone')),
        '0900000002',
      );
      await tester.enterText(
        find.byKey(const ValueKey('customer-address')),
        'Thôn 2, Xã mới',
      );
      await tester.tap(find.text('Lưu khách hàng'));
      await tester.pumpAndSettle();
      expect(sale.customer?['IdKH'], 2);
      expect(sale.customerQuery, 'Khách mới');
      expect(find.text('Địa chỉ: Thôn 2, Xã mới'), findsOneWidget);
      expectCustomerAlignment();
      expectFixedSections();

      expect(
        tester.getTopLeft(find.text('Khách hàng')).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('sales-product-list')))
              .dy,
        ),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('sales-payment'))).dy,
        greaterThan(
          tester
              .getBottomLeft(find.byKey(const ValueKey('sales-product-list')))
              .dy,
        ),
      );
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byTooltip('Làm mới đơn'), findsNothing);
      expect(find.text('Khách lẻ'), findsNothing);
      expect(find.text('Phương thức thanh toán'), findsNothing);
      await tester.enterText(
        find.byKey(ValueKey('sales-discount-${sale.revision}')),
        '100000',
      );
      await tester.enterText(
        find.byKey(ValueKey('sales-paid-${sale.revision}')),
        '500000',
      );
      await tester.pumpAndSettle();
      expect(find.text('100.000'), findsWidgets);
      expect(find.text('500.000'), findsWidgets);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('sales-due-date-empty')),
            )
            .enabled,
        isTrue,
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('sales-interest-date-empty')),
            )
            .enabled,
        isTrue,
      );
      final paymentFields = [
        find.byKey(ValueKey('sales-discount-${sale.revision}')),
        find.byKey(ValueKey('sales-paid-${sale.revision}')),
        find.byKey(const ValueKey('sales-due-date-empty')),
        find.byKey(const ValueKey('sales-interest-date-empty')),
      ];
      final fieldRects = paymentFields.map(tester.getRect).toList();
      for (var i = 1; i < fieldRects.length; i++) {
        expect(fieldRects[i].top, closeTo(fieldRects.first.top, .01));
        expect(fieldRects[i].left, greaterThan(fieldRects[i - 1].right));
      }
      final saveButton = find
          .ancestor(
            of: find.text('Lưu đơn hàng'),
            matching: find.byWidgetPredicate(
              (widget) => widget is FilledButton,
            ),
          )
          .first;
      expect(
        tester.getRect(find.byKey(const ValueKey('sales-payment'))).right -
            tester.getRect(saveButton).right,
        closeTo(21, 1),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('sales-due-date-empty')),
      );
      await tester.tap(find.byKey(const ValueKey('sales-due-date-empty')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sales-interest-date-empty')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Thanh toán'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('sales-payment')),
          matching: find.text('Ngày hẹn thanh toán *'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('sales-payment')),
          matching: find.text('Ngày tính lãi *'),
        ),
        findsOneWidget,
      );
      expect(sale.paymentDueDate, isNotNull);
      expect(sale.interestDate, isNotNull);
      expect(find.text('Thanh toán đủ'), findsNothing);
      expect(sale.total, 900000);
      expect(sale.due, 400000);
      final preview = find.text('Xem trước đơn hàng');
      await tester.ensureVisible(preview);
      await tester.tap(preview);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Xem trước đơn bán hàng'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Hóa đơn'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Hợp đồng'), findsOneWidget);
      expect(find.byKey(const ValueKey('print-sales-invoice')), findsOneWidget);
      expect(find.text('400.000 đ'), findsWidgets);
      expect(cart.items.length, 1);
      expect(repository.rows.length, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Narrow sales layout keeps totals and services usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cart = CartController()
      ..addService(
        const ServiceItem(
          id: 's',
          name: 'Bảo dưỡng',
          description: '',
          price: 200000,
        ),
      );
    final saved = FakeSalesRepository();
    final sale = SalesController(
      cart,
      FakeCustomerRepository(),
      salesRepository: saved,
    );
    addTearDown(sale.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: SalesTab(controller: sale)),
      ),
    );
    final increase = find.descendant(
      of: find.byKey(const ValueKey('sales-line-dv-s')),
      matching: find.byIcon(Icons.add),
    );
    await tester.ensureVisible(increase);
    await tester.tap(increase);
    await tester.pumpAndSettle();
    expect(sale.subtotal, 400000);
    final payment = find.byKey(ValueKey('sales-paid-${sale.revision}'));
    await tester.ensureVisible(payment);
    await tester.enterText(payment, '400000');
    await tester.pumpAndSettle();
    expect(find.text('Thanh toán đủ'), findsNothing);
    expect(find.text('Ngày hẹn thanh toán *'), findsOneWidget);
    expect(find.text('Ngày tính lãi *'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('sales-due-date-empty')),
          )
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('sales-interest-date-empty')),
          )
          .enabled,
      isFalse,
    );
    expect(sale.paid, 400000);
    expect(sale.due, 0);
    await tester.ensureVisible(find.text('Lưu đơn hàng'));
    await tester.tap(find.text('Lưu đơn hàng'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(saved.lastDraft!.lines.single.kind, 'dich_vu');
    expect(saved.lastDraft!.paid, 400000);
    expect(cart.items, isEmpty);
    expect(sale.lastSavedId, 501);
    expect(find.text('Đơn hàng #501'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Hóa đơn'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Hợp đồng'), findsOneWidget);
    expect(find.byKey(const ValueKey('print-sales-invoice')), findsOneWidget);
    await tester.tap(find.widgetWithText(Tab, 'Hợp đồng'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('print-sale-contract')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sales catalog search adds a vehicle by frame number above services',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final inventory = _FrameSearchInventory();
      final services = FakeServiceRepository()
        ..items.add(
          const ServiceItem(
            id: 'dv-1',
            name: 'Thay nhớt',
            description: '',
            price: 80000,
          ),
        );
      final cart = CartController();
      final sale = SalesController(cart, FakeCustomerRepository());
      addTearDown(sale.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SalesTab(
              controller: sale,
              inventoryRepositoryFactory: () => inventory,
              serviceRepositoryFactory: () => services,
            ),
          ),
        ),
      );
      final productName = find.byKey(
        const ValueKey('sales-product-name-product-default'),
      );
      final serviceName = find.byKey(
        const ValueKey('sales-service-name-draft-default'),
      );
      expect(find.byKey(const ValueKey('sales-product-search')), findsNothing);
      expect(find.byKey(const ValueKey('sales-service-search')), findsNothing);
      expect(find.byTooltip('Thêm dòng sản phẩm'), findsOneWidget);
      expect(find.byTooltip('Thêm dòng dịch vụ'), findsOneWidget);
      expect(
        tester.getTopLeft(productName).dy,
        lessThan(tester.getTopLeft(serviceName).dy),
      );
      await tester.enterText(productName, 'không có');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(cart.items, isEmpty);
      await tester.enterText(productName, 'KHUNG-9');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.textContaining('Số khung: KHUNG-9'), findsOneWidget);
      await tester.tap(find.text('Wave'));
      await tester.pumpAndSettle();
      expect(cart.items.single.name, 'Wave');
      expect(cart.items.single.vehicle, isTrue);
      final name = tester.getRect(productName);
      final frame = tester.getRect(find.text('KHUNG-9'));
      expect(frame.center.dy, closeTo(name.center.dy, 2));
      expect(find.text('Số khung'), findsWidgets);
      expect(find.text('Đơn giá'), findsWidgets);
      final quantity = tester.getRect(
        find.byKey(const ValueKey('sales-qty-xe-9')),
      );
      final price = tester.getRect(
        find.byKey(const ValueKey('sales-price-xe-9')),
      );
      expect(quantity.width, lessThan(price.width));
      expect(quantity.height, closeTo(price.height, 1));
      final list = tester.getRect(
        find.byKey(const ValueKey('sales-product-list')),
      );
      final remove = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('sales-line-xe-9')),
          matching: find.byTooltip('Bỏ khỏi đơn'),
        ),
      );
      expect(remove.right, lessThanOrEqualTo(list.right + 1));
      expect(remove.left, greaterThan(price.left));
      final addProduct = tester.getRect(find.byTooltip('Thêm dòng sản phẩm'));
      expect(remove.center.dx, closeTo(addProduct.center.dx, 1));
      final addService = tester.getRect(find.byTooltip('Thêm dòng dịch vụ'));
      final serviceRemove = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('sales-line-draft-default')),
          matching: find.byTooltip('Bỏ khỏi đơn'),
        ),
      );
      expect(serviceRemove.center.dx, closeTo(addService.center.dx, 1));
      expect(
        tester.getTopLeft(productName).dy,
        lessThan(tester.getTopLeft(serviceName).dy),
      );
      await tester.enterText(serviceName, 'nhớt');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thay nhớt'));
      await tester.pumpAndSettle();
      expect(cart.items.map((item) => item.name), contains('Thay nhớt'));
      expect(find.text('80.000'), findsWidgets);
      expect(
        tester.getTopLeft(find.text('Thay nhớt')).dy,
        greaterThan(tester.getTopLeft(productName).dy),
      );
    },
  );

  testWidgets('an unknown service is created when the order is saved', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sales = FakeSalesRepository();
    final services = FakeServiceRepository();
    final sale = SalesController(
      CartController(),
      FakeCustomerRepository(),
      salesRepository: sales,
    );
    addTearDown(sale.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SalesTab(
            controller: sale,
            serviceRepositoryFactory: () => services,
            inventoryRepositoryFactory: FakeInventoryRepository.new,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('sales-service-name-draft-default')),
      'Rửa xe',
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('sales-price-draft-default-0')),
      '50000',
    );
    await tester.enterText(find.byKey(const ValueKey('sales-paid-0')), '50000');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Lưu đơn hàng'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(services.items.single.name, 'Rửa xe');
    expect(services.items.single.price, 50000);
    expect(sales.lastDraft?.lines.single.name, 'Rửa xe');
    expect(sales.lastDraft?.lines.single.serviceId, 'service-0');
  });

  testWidgets('sales product search skips unclassified vehicles', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final inventory = _ClassifiedInventory();
    final sale = SalesController(CartController(), FakeCustomerRepository());
    addTearDown(sale.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SalesTab(
            controller: sale,
            inventoryRepositoryFactory: () => inventory,
            serviceRepositoryFactory: FakeServiceRepository.new,
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('sales-product-name-product-default')),
      '2308',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Wave S'), findsNothing);
    expect(find.text('Xe mới'), findsOneWidget);
    expect(inventory.conditions, ['moi', 'cu']);
    expect(inventory.availabilities.toSet(), {'available'});
  });
}

class _ClassifiedInventory extends FakeInventoryRepository {
  final conditions = <String>[];
  final availabilities = <String>[];

  @override
  Future<InventoryPage> fetch(
    InventorySection view, {
    String search = '',
    String condition = '',
    String availability = 'all',
    int page = 0,
    int pageSize = 30,
  }) async {
    if (view == InventorySection.vehicles) {
      conditions.add(condition);
      availabilities.add(availability);
      if (condition == 'moi') {
        return const InventoryPage([
          {
            'IdXe': 11,
            'TenXe': 'Xe mới',
            'TinhTrangXe': 'moi',
            'SoLuongTon': 1,
          },
        ], 1);
      }
      return const InventoryPage([], 0);
    }
    availabilities.add(availability);
    return const InventoryPage([], 0);
  }
}

class _FrameSearchInventory extends FakeInventoryRepository {
  bool connected = false;

  @override
  Future<void> connect() async {
    connected = true;
  }

  @override
  Future<InventoryPage> fetch(
    InventorySection view, {
    String search = '',
    String condition = '',
    String availability = 'all',
    int page = 0,
    int pageSize = 30,
  }) async {
    if (!connected) throw StateError('offline');
    if (view == InventorySection.vehicles && search.contains('KHUNG')) {
      return const InventoryPage([
        {
          'IdXe': 9,
          'TenXe': 'Wave',
          'SoKhung': 'KHUNG-9',
          'SoMay': 'MAY-9',
          'SoLuongTon': 1,
        },
      ], 1);
    }
    return const InventoryPage([], 0);
  }
}
