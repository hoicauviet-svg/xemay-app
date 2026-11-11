import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/controllers/cart_controller.dart';
import 'package:xemay_app/controllers/sales_controller.dart';
import 'package:xemay_app/core/theme/app_theme.dart';
import 'package:xemay_app/models/services/service_models.dart';
import 'package:xemay_app/views/sales/sales_tab.dart';
import 'support/fake_customer_repository.dart';
import 'support/fake_sales_repository.dart';

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
          home: Scaffold(
            body: SalesTab(
              controller: sale,
              onAddProducts: () {},
              onAddServices: () {},
            ),
          ),
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
      expect(find.text('Thêm sản phẩm / dịch vụ'), findsOneWidget);
      expect(
        tester.getSize(find.byTooltip('Thêm sản phẩm / dịch vụ')).height,
        greaterThanOrEqualTo(48),
      );
      await tester.enterText(
        find.byKey(const ValueKey('sales-price-xe-7')),
        '1000000',
      );
      await tester.enterText(
        find.byKey(const ValueKey('sales-customer-search')),
        'Khách',
      );
      await tester.pumpAndSettle();
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
      expect(find.byTooltip('Thêm sản phẩm / dịch vụ'), findsOneWidget);
      await tester.enterText(
        find.byKey(ValueKey('sales-discount-${sale.revision}')),
        '100000',
      );
      await tester.enterText(
        find.byKey(ValueKey('sales-paid-${sale.revision}')),
        '500000',
      );
      await tester.pumpAndSettle();
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
    var serviceOpened = false;
    addTearDown(sale.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SalesTab(
            controller: sale,
            onAddProducts: () {},
            onAddServices: () => serviceOpened = true,
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.byTooltip('Thêm sản phẩm / dịch vụ'));
    await tester.tap(find.byTooltip('Thêm sản phẩm / dịch vụ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thêm dịch vụ'));
    await tester.pumpAndSettle();
    expect(serviceOpened, isTrue);
    await tester.ensureVisible(find.byTooltip('Tăng số lượng Bảo dưỡng'));
    await tester.tap(find.byTooltip('Tăng số lượng Bảo dưỡng'));
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
}
