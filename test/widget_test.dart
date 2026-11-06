import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:xemay_app/controllers/inventory_controller.dart';
import 'package:xemay_app/core/theme/app_theme.dart';
import 'package:xemay_app/views/inventory/inventory_screen.dart';
import 'package:xemay_app/models/inventory/inventory_models.dart';
import 'package:xemay_app/services/mongo_inventory_repository.dart';
import 'support/fake_inventory_repository.dart';

Future<void> pumpInventory(
  WidgetTester tester,
  FakeInventoryRepository repo,
) async {
  final controller = InventoryController(repo);
  addTearDown(controller.dispose);
  await controller.load(refreshSummary: true);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AppTheme.light,
      home: InventoryScreen(controller: controller),
    ),
  );
}

void main() {
  test(
    'Search treats regex syntax as literal text and retains type/condition filters',
    () {
      final f = MongoInventoryRepository.filterFor(
        InventorySection.parts,
        '  .*  ',
        '',
      );
      expect(f['LoaiSanPham'], 'phu_tung');
      expect((f[r'$or'] as List).first['TenSanPham'][r'$regex'], r'\.\*');
      expect(
        MongoInventoryRepository.filterFor(
          InventorySection.vehicles,
          '7',
          'cu',
        )['TinhTrangXe'],
        'cu',
      );
    },
  );

  testWidgets('Navigation, pagination, search and details use the repository', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeInventoryRepository();
    await pumpInventory(tester, repo);
    await tester.pumpAndSettle();
    expect(find.text('Sản phẩm kiểm thử'), findsOneWidget);
    await tester.tap(find.byTooltip('Trang sau'));
    await tester.pumpAndSettle();
    expect(repo.lastPage, 1);
    await tester.tap(find.text('Danh sách xe'));
    await tester.pumpAndSettle();
    expect(find.text('Xe kiểm thử'), findsOneWidget);
    await tester.tap(find.text('Xe kiểm thử'));
    await tester.pumpAndSettle();
    expect(find.text('KHUNG-TEST'), findsOneWidget);
    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'không tìm thấy');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(repo.lastSearch, 'không tìm thấy');
    expect(repo.lastPage, 0);
    expect(find.text('Không có kết quả'), findsOneWidget);
    await tester.tap(find.text('Phụ tùng'));
    await tester.pumpAndSettle();
    expect(find.text('Chưa có phụ tùng'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Connection failure offers a working retry', (tester) async {
    final repo = FakeInventoryRepository()..fail = true;
    await pumpInventory(tester, repo);
    await tester.pumpAndSettle();
    expect(find.text('Chưa mở được dữ liệu'), findsOneWidget);
    repo.fail = false;
    await tester.tap(find.text('Thử kết nối lại'));
    await tester.pumpAndSettle();
    expect(find.text('Sản phẩm kiểm thử'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
