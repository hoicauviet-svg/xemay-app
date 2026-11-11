import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/core/theme/app_theme.dart';
import 'package:xemay_app/models/maintenance/record_maintenance.dart';
import 'package:xemay_app/models/products/product_details.dart';
import 'package:xemay_app/models/repositories/product_details_repository.dart';
import 'package:xemay_app/views/products/product_details_screen.dart';

class _Maintenance implements RecordMaintenance {
  final deleted = <Map<String, dynamic>>[];
  List<Map<String, dynamic>>? source;
  @override
  Future<void> deleteCost(
    bool vehicle,
    int productId,
    Map<String, dynamic> cost, {
    required String requestId,
  }) async {
    deleted.add(cost);
    source?.removeWhere((row) => row['GhiChu'] == cost['GhiChu']);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repository extends ProductDetailsRepository {
  _Repository(this.maintenance);
  @override
  final RecordMaintenance maintenance;
  final costs = <Map<String, dynamic>>[];
  @override
  Future<ProductDetails> load(ProductReference product) async {
    await Future<void>.delayed(Duration.zero);
    return ProductDetails(
      information: {
        'IdXe': 7,
        'TenXe': 'Xe chi tiết',
        'TinhTrangXe': 'moi',
        'TinhTrang': true,
      },
      sales: const [],
      receipts: const [],
      costs: [
        for (var i = 0; i < costs.length; i++)
          {
            ...costs[i],
            '_CostCollection': 'Xe',
            '_CostDocument': 7,
            '_CostIndex': i,
          },
      ],
    );
  }

  @override
  Future<void> addCost(
    ProductReference product, {
    required DateTime date,
    required int amount,
    required String notes,
    required String requestId,
  }) async {
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
    'A second product cost saves and an existing cost can be deleted',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final maintenance = _Maintenance();
      final repository = _Repository(maintenance);
      maintenance.source = repository.costs;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ProductDetailsScreen(
            product: const ProductReference(id: 7, vehicle: true),
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> addCost(String amount, String notes) async {
        await tester.tap(find.widgetWithText(Tab, 'Thêm chi phí'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('product-cost-amount')),
          amount,
        );
        await tester.enterText(
          find.byKey(const ValueKey('product-cost-notes')),
          notes,
        );
        await tester.tap(find.text('Lưu chi phí'));
        await tester.pumpAndSettle();
      }

      await addCost('150000', 'Chi phí một');
      expect(find.text('Thêm chi phí thành công'), findsOneWidget);
      expect(find.text('Chi phí một'), findsOneWidget);
      await addCost('50000', 'Chi phí hai');
      expect(
        find.text('Chưa xác nhận lưu chi phí. Bấm Lưu để thử lại.'),
        findsNothing,
      );
      expect(find.text('Chi phí hai'), findsOneWidget);
      expect(find.text('Tổng chi phí: 200.000 đ'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final deleteButton = find.byTooltip('Xóa chi phí').first;
      expect(
        tester.getRect(deleteButton).right,
        lessThanOrEqualTo(tester.view.physicalSize.width),
      );
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Xóa'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(maintenance.deleted, isNotEmpty);
      expect(repository.costs, hasLength(1));
      expect(find.byTooltip('Xóa chi phí'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
