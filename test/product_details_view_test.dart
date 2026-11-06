import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/core/theme/app_theme.dart';
import 'package:xemay_app/models/products/product_details.dart';
import 'package:xemay_app/models/repositories/product_details_repository.dart';
import 'package:xemay_app/views/products/product_details_screen.dart';

class _Repository extends ProductDetailsRepository {
  final costs = <Map<String, dynamic>>[];
  int saves = 0;
  @override
  Future<ProductDetails> load(ProductReference product) async => ProductDetails(
    information: {
      'IdXe': 7,
      'TenXe': 'Xe chi tiết',
      'TinhTrangXe': 'moi',
      'TinhTrang': true,
      'GiaNhap': 10000000,
      'SoKhung': 'KHUNG-7',
    },
    sales: [
      {'Ma': 12, 'Loai': 'Đơn bán', 'SoLuong': 1, 'SoTien': 12000000},
    ],
    receipts: [
      {
        'Ma': 42,
        'Loai': 'Lô hàng',
        'DoiTac': 'Đối tác thử',
        'SoLuong': 1,
        'SoTien': 10000000,
      },
    ],
    costs: List.of(costs),
  );
  @override
  Future<void> addCost(
    ProductReference product, {
    required DateTime date,
    required int amount,
    required String notes,
    required String requestId,
  }) async {
    saves++;
    costs.add({'Ngay': date, 'SoTien': amount, 'GhiChu': notes});
  }

  @override
  Future<void> update(ProductReference product, ProductEditDraft draft) async {}
  @override
  Future<void> delete(ProductReference product) async {}
  @override
  Future<void> close() async {}
}

void main() {
  testWidgets(
    'Product has five tabs; separate expense form saves and refreshes cost list',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _Repository();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ProductDetailsScreen(
            product: const ProductReference(id: 7, vehicle: true),
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Tab), findsNWidgets(5));
      expect(find.text('Xe chi tiết'), findsOneWidget);
      await tester.tap(find.widgetWithText(Tab, 'Đơn bán'));
      await tester.pumpAndSettle();
      expect(find.text('#12'), findsOneWidget);
      await tester.tap(find.widgetWithText(Tab, 'Đơn nhập'));
      await tester.pumpAndSettle();
      expect(find.text('#42'), findsOneWidget);
      expect(find.text('ĐỐI TÁC'), findsOneWidget);
      expect(find.text('Đối tác thử'), findsOneWidget);
      await tester.tap(find.widgetWithText(Tab, 'Thêm chi phí'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lưu chi phí'));
      await tester.pumpAndSettle();
      expect(repo.saves, 0);
      await tester.enterText(
        find.byKey(const ValueKey('product-cost-amount')),
        '150000',
      );
      await tester.enterText(
        find.byKey(const ValueKey('product-cost-notes')),
        'Vận chuyển xe',
      );
      await tester.tap(find.text('Lưu chi phí'));
      await tester.pumpAndSettle();
      expect(repo.saves, 1);
      expect(find.text('Thêm chi phí thành công'), findsOneWidget);
      expect(find.text('Tổng chi phí: 150.000 đ'), findsOneWidget);
      expect(find.text('Vận chuyển xe'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Cost form fits narrow windows', (tester) async {
    tester.view.physicalSize = const Size(420, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProductDetailsScreen(
          product: const ProductReference(id: 7, vehicle: true),
          repository: _Repository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(Tab, 'Thêm chi phí'));
    await tester.tap(find.widgetWithText(Tab, 'Thêm chi phí'));
    await tester.pumpAndSettle();
    expect(find.text('Lưu chi phí'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
