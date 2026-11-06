import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/controllers/product_list_controller.dart';
import 'package:xemay_app/models/dashboard/dashboard_module.dart';
import 'package:xemay_app/models/inventory/inventory_models.dart';
import 'support/fake_inventory_repository.dart';

void main() {
  test('Each product tab requests its own category', () async {
    for (final module in [
      DashboardModule.newVehicles,
      DashboardModule.usedVehicles,
      DashboardModule.parts,
    ]) {
      final repository = FakeInventoryRepository();
      final controller = ProductListController(repository, module);
      await controller.load();
      expect(controller.error, isNull);
      expect(repository.lastAvailability, 'available');
      expect(
        repository.lastSection,
        module == DashboardModule.parts
            ? InventorySection.parts
            : InventorySection.vehicles,
      );
      expect(
        repository.lastCondition,
        module == DashboardModule.newVehicles
            ? 'moi'
            : module == DashboardModule.usedVehicles
            ? 'cu'
            : '',
      );
      expect(
        controller.data!.rows.length,
        module == DashboardModule.parts ? 0 : 1,
      );
      controller.dispose();
    }
  });
  test('Failed connection can be retried without losing category', () async {
    final repository = FakeInventoryRepository()..fail = true;
    final controller = ProductListController(
      repository,
      DashboardModule.usedVehicles,
    );
    await controller.load();
    expect(controller.error, isNotNull);
    repository.fail = false;
    await controller.load();
    expect(controller.error, isNull);
    expect(controller.data!.rows.single['TinhTrangXe'], 'cu');
    controller.dispose();
  });
  test(
    'Product lists request all matching rows and retain availability filtering',
    () async {
      final repository = FakeInventoryRepository()
        ..productRows = [
          for (var i = 0; i < 35; i++) {'IdXe': i},
        ];
      final controller = ProductListController(
        repository,
        DashboardModule.newVehicles,
      );
      await controller.load();
      expect(repository.lastPageSize, 0);
      expect(controller.data!.rows.length, 35);
      controller.setAvailability('all');
      await Future<void>.delayed(Duration.zero);
      expect(repository.lastAvailability, 'all');
      expect(repository.lastPageSize, 0);
      controller.dispose();
    },
  );
}
