import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/app.dart';
import 'package:xemay_app/models/dashboard/dashboard_module.dart';
import 'package:xemay_app/models/reports/report_models.dart';
import 'package:xemay_app/models/services/service_models.dart';
import 'package:xemay_app/views/products/product_tab.dart';
import 'package:xemay_app/views/products/service_tab.dart';
import 'support/fake_inventory_repository.dart';
import 'support/fake_reports_repository.dart';
import 'support/fake_sales_repository.dart';
import 'support/fake_service_repository.dart';

void main() {
  testWidgets('Stock rows open the corresponding product tabs', (t) async {
    t.view.physicalSize = const Size(1400, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      StoreApp(
        reportsRepositoryFactory: FakeReportsRepository.new,
        inventoryRepositoryFactory: FakeInventoryRepository.new,
        salesRepositoryFactory: FakeSalesRepository.new,
        serviceRepositoryFactory: FakeServiceRepository.new,
      ),
    );
    await t.pumpAndSettle();
    for (final e in {'Xe mới': 0, 'Xe cũ': 1, 'Phụ tùng': 2}.entries) {
      await t.tap(find.text('Báo cáo').first);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(Tab, 'Tồn kho'));
      await t.pumpAndSettle();
      await t.tap(find.text(e.key));
      await t.pumpAndSettle();
      expect(
        DefaultTabController.of(t.element(find.byType(TabBar))).index,
        e.value,
      );
    }
    expect(t.takeException(), isNull);
  });
  testWidgets('All product tabs list and export all rows with aligned totals', (
    t,
  ) async {
    t.view.physicalSize = const Size(1400, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    for (final module in [
      DashboardModule.newVehicles,
      DashboardModule.usedVehicles,
      DashboardModule.parts,
    ]) {
      final part = module == DashboardModule.parts;
      final repo = FakeInventoryRepository()
        ..productRows = [
          for (var i = 1; i <= 35; i++)
            {
              'IdXe': i,
              'IdSanPham': i,
              'TenXe': 'Xe $i',
              'TenSanPham': 'Phụ tùng $i',
              'GiaNhap': 100,
              'GiaBan': 150,
              'GiaBanThamKhao': 150,
              'TongChiPhi': 10,
              'SoLuongTon': part ? 2 : 1,
            },
        ];
      ReportSection? exported;
      await t.pumpWidget(
        MaterialApp(
          key: ValueKey(module),
          home: Scaffold(
            body: ProductTab(
              module: module,
              repository: repo,
              exportReport: (title, section, time) async {
                exported = section;
                return true;
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(repo.lastPageSize, 0);
      expect(find.byTooltip('Trang sản phẩm sau'), findsNothing);
      expect(find.text('350 đ'), findsOneWidget);
      await t.drag(
        find.byKey(const ValueKey('fixed-table-body')),
        const Offset(0, -4000),
      );
      await t.pumpAndSettle();
      expect(find.text(part ? '35' : '#35'), findsWidgets);
      await t.tap(find.byKey(ValueKey('product-export-${module.name}')));
      await t.pumpAndSettle();
      expect(exported?.rows.length, 35);
      expect(exported?.totals['Tồn kho'], part ? 70 : 35);
      expect(exported?.totals['Chi phí'], 350);
      if (!part) expect(exported?.totals['Giá nhập'], 3500);
      expect(t.takeException(), isNull);
    }
  });
  testWidgets('Services export all listed prices without pagination', (
    t,
  ) async {
    t.view.physicalSize = const Size(1400, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final repo = FakeServiceRepository();
    repo.items.addAll([
      for (var i = 0; i < 35; i++)
        ServiceItem(id: 's$i', name: 'Dịch vụ $i', description: '', price: 100),
    ]);
    ReportSection? exported;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ServiceTab(
            repository: repo,
            exportReport: (title, section, time) async {
              exported = section;
              return true;
            },
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byTooltip('Trang dịch vụ sau'), findsNothing);
    expect(find.text('3.500 đ'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('service-export-excel')));
    await t.pumpAndSettle();
    expect(exported?.rows.length, 35);
    expect(exported?.totals['Giá tiền'], 3500);
    expect(t.takeException(), isNull);
  });
}
