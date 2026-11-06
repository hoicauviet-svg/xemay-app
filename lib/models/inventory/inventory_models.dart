enum InventorySection { products, vehicles, parts }

class InventoryPage {
  const InventoryPage(this.rows, this.total);
  final List<Map<String, dynamic>> rows;
  final int total;
}

class InventorySummary {
  const InventorySummary({
    required this.products,
    required this.vehicles,
    required this.parts,
    required this.unclassified,
  });
  final int products, vehicles, parts, unclassified;
}

class VehicleBrand {
  const VehicleBrand(this.id, this.name);
  final int id;
  final String name;
}
