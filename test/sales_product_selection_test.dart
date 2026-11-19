import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/controllers/cart_controller.dart';
import 'package:xemay_app/controllers/sales_controller.dart';
import 'package:xemay_app/core/theme/app_theme.dart';
import 'package:xemay_app/models/inventory/inventory_models.dart';
import 'package:xemay_app/views/sales/product_name_field.dart';
import 'package:xemay_app/views/sales/sales_tab.dart';
import 'support/fake_customer_repository.dart';
import 'support/fake_inventory_repository.dart';
import 'support/fake_sales_repository.dart';
import 'support/fake_service_repository.dart';

class _SpaceNamePartInventory extends FakeInventoryRepository {
  @override
  Future<InventoryPage> fetch(
    InventorySection view, {
    String search = '',
    String condition = '',
    String availability = 'all',
    int page = 0,
    int pageSize = 30,
  }) async {
    if (view == InventorySection.parts) {
      return const InventoryPage([
        {
          '_id': 'p260838',
          'IdSanPham': 260838,
          'MaSanPham': '260838',
          'TenSanPham': 'Sản phẩm 260838 ',
          'LoaiSanPham': 'phu_tung',
          'SoLuongTon': 5,
          'GiaBanThamKhao': 100000,
        },
      ], 1);
    }
    return const InventoryPage([], 0);
  }
}

const _productField = ValueKey('sales-product-name-product-default');

Future<CartController> _pumpSalesTab(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final cart = CartController();
  final sale = SalesController(
    cart,
    FakeCustomerRepository(),
    salesRepository: FakeSalesRepository(),
  );
  addTearDown(sale.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SalesTab(
          controller: sale,
          inventoryRepositoryFactory: () => _SpaceNamePartInventory(),
          serviceRepositoryFactory: FakeServiceRepository.new,
        ),
      ),
    ),
  );
  return cart;
}

Future<void> _selectProduct(WidgetTester tester, String text) async {
  final field = find.byKey(_productField);
  await tester.enterText(field, text);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('Sản phẩm 260838'));
  await tester.pumpAndSettle();
}

void main() {
  test('cart and suggestion names ignore surrounding spaces', () {
    final part = CartItem({
      'IdSanPham': 260838,
      'TenSanPham': ' Sản phẩm 260838 ',
      'SoLuongTon': 5,
      'GiaBanThamKhao': 100000,
    }, false);
    expect(part.name, 'Sản phẩm 260838');
    final invisible = CartItem({
      'IdSanPham': 260839,
      'TenSanPham': 'Sản phẩm\u200B ',
      'SoLuongTon': 5,
      'GiaBanThamKhao': 100000,
    }, false);
    expect(invisible.name, 'Sản phẩm');
    final vehicle = CartItem({
      'IdXe': 9,
      'TenXe': ' Wave ',
      'SoLuongTon': 1,
    }, true);
    expect(vehicle.name, 'Wave');
    final service = CartItem({
      '_id': 'dv-1',
      'LoaiSanPham': 'dich_vu',
      'TenDichVu': ' Thay nhớt ',
      'GiaTien': 80000,
    }, false);
    expect(service.name, 'Thay nhớt');
    expect(
      const ProductSuggestion.part({'TenSanPham': ' Sản phẩm '}).name,
      'Sản phẩm',
    );
    expect(const ProductSuggestion.vehicle({'TenXe': ' Xe '}).name, 'Xe');
  });

  testWidgets(
    'selecting a part whose name has trailing spaces keeps it linked',
    (tester) async {
      final cart = await _pumpSalesTab(tester);
      await _selectProduct(tester, '260838');
      expect(cart.items, hasLength(1));
      expect(cart.items.single.name, 'Sản phẩm 260838');
      expect(
        tester.widget<TextField>(find.byKey(_productField)).controller!.text,
        'Sản phẩm 260838',
      );
      await tester.tap(find.text('Lưu đơn hàng'));
      await tester.pumpAndSettle();
      expect(find.text('Chọn sản phẩm từ gợi ý.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('typing a name without choosing a suggestion blocks saving', (
    tester,
  ) async {
    final cart = await _pumpSalesTab(tester);
    await tester.enterText(find.byKey(_productField), 'Sản phẩm 260838');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(cart.items, isEmpty);
    await tester.tap(find.text('Lưu đơn hàng'));
    await tester.pumpAndSettle();
    expect(find.text('Chọn sản phẩm từ gợi ý.'), findsOneWidget);
  });

  testWidgets('editing a selected name clears the product link', (
    tester,
  ) async {
    final cart = await _pumpSalesTab(tester);
    await _selectProduct(tester, '260838');
    expect(cart.items, hasLength(1));
    await tester.enterText(find.byKey(_productField), 'Tên khác');
    await tester.pumpAndSettle();
    expect(cart.items, isEmpty);
    await tester.tap(find.text('Lưu đơn hàng'));
    await tester.pumpAndSettle();
    expect(find.text('Chọn sản phẩm từ gợi ý.'), findsOneWidget);
  });
}
