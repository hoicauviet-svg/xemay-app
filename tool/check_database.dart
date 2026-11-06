import 'dart:io';
import 'package:xemay_app/models/inventory/inventory_models.dart';
import 'package:xemay_app/services/mongo_inventory_repository.dart';

Future<void> main() async {
  final repository = MongoInventoryRepository();
  try {
    await repository.connect();
    final summary = await repository.summary();
    final products = await repository.fetch(InventorySection.products);
    final vehicles = await repository.fetch(InventorySection.vehicles);
    final parts = await repository.fetch(InventorySection.parts);
    if (products.total != summary.products ||
        vehicles.total != summary.vehicles ||
        parts.total != summary.parts) {
      throw StateError('Số lượng không khớp');
    }
    if (vehicles.rows.isNotEmpty) {
      final vehicle = vehicles.rows.first;
      final details = await repository.details(
        InventorySection.vehicles,
        vehicle,
      );
      if (details['IdXe'] != vehicle['IdXe'] ||
          details['IdSanPham'] != vehicle['IdSanPham']) {
        throw StateError('Chi tiết xe sai liên kết');
      }
    }
    if (products.rows.isNotEmpty) {
      final details = await repository.details(
        InventorySection.products,
        products.rows.first,
      );
      if ((details['SoChiecLienKet'] as int) < 1) {
        throw StateError('Sản phẩm không có xe liên kết');
      }
    }
    final used = await repository.fetch(
      InventorySection.vehicles,
      condition: 'cu',
    );
    if (used.rows.any((row) => row['TinhTrangXe'] != 'cu')) {
      throw StateError('Bộ lọc tình trạng không đúng');
    }
    final fresh = await repository.fetch(
      InventorySection.vehicles,
      condition: 'moi',
    );
    if (fresh.rows.any((r) => r['TinhTrangXe'] != 'moi')) {
      throw StateError('Sai loại xe mới');
    }
    final frames = fresh.rows.where(
      (r) => (r['SoKhung']?.toString() ?? '').trim().isNotEmpty,
    );
    if (frames.isNotEmpty) {
      final sample = frames.first;
      final found = await repository.fetch(
        InventorySection.vehicles,
        condition: 'moi',
        search: sample['SoKhung'].toString(),
      );
      if (!found.rows.any((r) => r['IdXe'] == sample['IdXe'])) {
        throw StateError('Không tìm được số khung');
      }
    }
    stdout.writeln(
      'Product tabs: ${fresh.total} new, ${used.total} used, ${parts.total} parts; serial search verified.',
    );
    for (final condition in ['moi', 'cu']) {
      final available = await repository.fetch(
        InventorySection.vehicles,
        condition: condition,
        availability: 'available',
      );
      final sold = await repository.fetch(
        InventorySection.vehicles,
        condition: condition,
        availability: 'sold',
      );
      final all = await repository.fetch(
        InventorySection.vehicles,
        condition: condition,
      );
      if (available.total + sold.total != all.total ||
          available.rows.any((r) => r['SoLuongTon'] != 1) ||
          sold.rows.any((r) => r['SoLuongTon'] != 0)) {
        throw StateError('Bộ lọc bán/tồn không khớp');
      }
      stdout.writeln(
        '$condition: ${available.total} available, ${sold.total} sold',
      );
    }
    final page2 = await repository.fetch(InventorySection.products, page: 1);
    final ids = products.rows.map((r) => r['IdSanPham']).toSet();
    if (page2.rows.any((r) => ids.contains(r['IdSanPham']))) {
      throw StateError('Phân trang bị trùng');
    }
    stdout.writeln(
      'PASS: ${summary.products} products, ${summary.vehicles} vehicles, ${summary.parts} parts; pagination and detail links verified.',
    );
  } finally {
    await repository.close();
  }
}
