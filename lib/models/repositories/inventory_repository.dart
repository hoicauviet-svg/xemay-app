import '../inventory/inventory_models.dart';

abstract class InventoryRepository {
  Future<void> connect();
  Future<InventorySummary> summary();
  Future<InventoryPage> fetch(
    InventorySection view, {
    String search = '',
    String condition = '',
    String availability = 'all',
    int page = 0,
    // Zero returns every matching product.
    int pageSize = 30,
  });
  Future<Map<String, dynamic>> details(
    InventorySection view,
    Map<String, dynamic> row,
  );
  Future<void> close();
}
