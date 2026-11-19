import 'package:intl/intl.dart';
import '../../models/inventory/inventory_models.dart';

/// Trims a display name and drops invisible characters that are often
/// introduced by spreadsheet imports (zero-width/bidi marks and BOM).
String cleanName(Object? value) => '${value ?? ''}'
    .replaceAll(RegExp(r'[\u200B-\u200F\u202A-\u202E\u2060\uFEFF]'), '')
    .trim();

String quantity(num n) => NumberFormat.decimalPattern('vi').format(n);
String money(dynamic v) => v == null
    ? 'Chưa ghi nhận'
    : v is num
    ? '${NumberFormat('#,##0.##', 'vi').format(v)} đ'
    : '$v đ';
String conditionName(dynamic v) => switch (v) {
  'moi' => 'Xe mới',
  'cu' => 'Xe cũ',
  _ => 'Chưa phân loại',
};
String viewName(InventorySection v) => switch (v) {
  InventorySection.products => 'Sản phẩm',
  InventorySection.vehicles => 'Danh sách xe',
  InventorySection.parts => 'Phụ tùng',
};
