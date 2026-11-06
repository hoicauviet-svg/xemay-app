import 'package:intl/intl.dart';
import '../../models/inventory/inventory_models.dart';

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
