import 'package:xemay_app/core/config/database_config.dart';
import 'support/fake_batch_repository.dart';
import 'support/fake_directory_repository.dart';
import 'support/fake_database_settings_repository.dart';
import 'support/fake_reports_repository.dart';
import 'support/fake_sales_repository.dart';
import 'support/fake_inventory_repository.dart';
import 'support/fake_service_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/app.dart';

void main() {
  testWidgets('changing saved Mongo connection reloads active repositories', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final instances = <FakeInventoryRepository>[];
    await tester.pumpWidget(
      StoreApp(
        databaseSettingsRepositoryFactory: FakeDatabaseSettingsRepository.new,
        salesRepositoryFactory: FakeSalesRepository.new,
        inventoryRepositoryFactory: () {
          final repo = FakeInventoryRepository();
          instances.add(repo);
          return repo;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sản phẩm').first);
    await tester.pumpAndSettle();
    final first = instances.first;
    DatabaseConfig.useMongo('mongodb://127.0.0.1:27017/XM_configuration_test');
    await tester.pumpAndSettle();
    expect(first.closed, true);
    expect(instances.length, greaterThan(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    DatabaseConfig.useMongo(DatabaseConfig.defaultMongoUri);
  });

  testWidgets(
    'Groups open child tabs and preserve the selected tab on return',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        StoreApp(
          databaseSettingsRepositoryFactory: FakeDatabaseSettingsRepository.new,
          reportsRepositoryFactory: FakeReportsRepository.new,
          salesRepositoryFactory: FakeSalesRepository.new,
          inventoryRepositoryFactory: FakeInventoryRepository.new,
          serviceRepositoryFactory: FakeServiceRepository.new,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Mở bán hàng'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Bán hàng'), findsOneWidget);
      expect(find.text('Tổng quan'), findsNothing);
      expect(
        tester.getTopLeft(find.byTooltip('Mở bán hàng')).dy,
        lessThan(tester.getTopLeft(find.text('Sản phẩm').first).dy),
      );
      await tester.tap(find.text('Sản phẩm').first);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(Tab, 'Xe mới'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Xe cũ'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Dịch vụ'), findsOneWidget);
      await tester.tap(find.widgetWithText(Tab, 'Dịch vụ'));
      await tester.pumpAndSettle();
      expect(find.text('Chưa có dịch vụ.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.widgetWithText(Tab, 'Phụ tùng'));
      await tester.pumpAndSettle();
      expect(
        DefaultTabController.of(tester.element(find.byType(TabBar))).index,
        2,
      );
      await tester.tap(find.text('Báo cáo').first);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(Tab, 'Công nợ'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Bán hàng'), findsOneWidget);
      await tester.tap(find.text('Sản phẩm').first);
      await tester.pumpAndSettle();
      expect(
        DefaultTabController.of(tester.element(find.byType(TabBar))).index,
        2,
      );
      await tester.tap(find.text('Cài đặt').first);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(Tab, 'MongoDB'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'SQL Server'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Nhập hàng opens receipt tabs for each product type', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      StoreApp(
        databaseSettingsRepositoryFactory: FakeDatabaseSettingsRepository.new,
        salesRepositoryFactory: FakeSalesRepository.new,
        inventoryRepositoryFactory: FakeInventoryRepository.new,
        serviceRepositoryFactory: FakeServiceRepository.new,
        directoryRepositoryFactory: FakeDirectoryRepository.new,
        batchRepositoryFactory: FakeBatchRepository.new,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nhập hàng'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Tab, 'Nhập xe mới'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Mua xe cũ'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Nhập phụ tùng'), findsOneWidget);
    expect(find.text('Tìm mã lô, vận chuyển, đối tác…'), findsOneWidget);
    expect(find.text('#42'), findsOneWidget);
    final table = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('fixed-table-heading')),
    );
    final viewport = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('fixed-table-horizontal')),
    );
    expect(table.size.width, viewport.size.width);
    await tester.tap(find.byTooltip('Nhập hàng'));
    await tester.pumpAndSettle();
    expect(find.text('Nhập lẻ'), findsOneWidget);
    expect(find.text('Nhập lô'), findsOneWidget);
    await tester.tap(find.text('Nhập lẻ'));
    await tester.pumpAndSettle();
    expect(find.text('Thông tin phiếu nhập'), findsOneWidget);
    expect(find.text('Tên xe'), findsOneWidget);
    await tester.tap(find.byTooltip('Đóng'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Nhập hàng'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nhập lô'));
    await tester.pumpAndSettle();
    expect(find.text('Thông tin lô nhập'), findsOneWidget);
    await tester.tap(find.byTooltip('Đóng'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Nhập phụ tùng'));
    await tester.pumpAndSettle();
    expect(find.text('Chưa có lô hàng.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Narrow windows can open a group through the drawer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      StoreApp(
        databaseSettingsRepositoryFactory: FakeDatabaseSettingsRepository.new,
        salesRepositoryFactory: FakeSalesRepository.new,
        inventoryRepositoryFactory: FakeInventoryRepository.new,
        serviceRepositoryFactory: FakeServiceRepository.new,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mở bán hàng'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Tab, 'Bán hàng'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    await tester.tap(find.byType(DrawerButton));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(Drawer), matching: find.text('Sản phẩm')),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Tab, 'Xe mới'), findsOneWidget);
    await tester.tap(find.widgetWithText(Tab, 'Xe cũ'));
    await tester.pumpAndSettle();
    expect(
      DefaultTabController.of(tester.element(find.byType(TabBar))).index,
      1,
    );
    expect(tester.takeException(), isNull);
  });
}
