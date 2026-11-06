import 'package:xemay_app/models/inventory/inventory_models.dart';
import 'package:xemay_app/models/repositories/inventory_repository.dart';

class FakeInventoryRepository implements InventoryRepository {
  bool fail = false;
  bool closed = false;
  int lastPage = 0;
  int lastPageSize = 30;
  List<Map<String, dynamic>>? productRows;
  int vehicleTotal = 1;
  String lastSearch = '';
  String lastCondition = '';
  String lastAvailability = '';
  InventorySection? lastSection;
  @override
  Future<void> connect() async {
    if (fail) throw StateError('offline');
  }

  @override
  Future<InventorySummary> summary() async => const InventorySummary(
    products: 60,
    vehicles: 100,
    parts: 0,
    unclassified: 1,
  );
  @override
  Future<InventoryPage> fetch(
    InventorySection view, {
    String search = '',
    String condition = '',
    String availability = 'all',
    int page = 0,
    int pageSize = 30,
  }) async {
    lastPage = page;
    lastPageSize = pageSize;
    lastCondition = condition;
    lastAvailability = availability;
    lastSection = view;
    lastSearch = search;
    if (productRows != null) {
      return InventoryPage(
        pageSize <= 0
            ? productRows!
            : productRows!.skip(page * pageSize).take(pageSize).toList(),
        productRows!.length,
      );
    }
    if (view == InventorySection.parts || search.isNotEmpty) {
      return const InventoryPage([], 0);
    }
    if (view == InventorySection.vehicles) {
      return InventoryPage([
        {
          'IdXe': 7,
          'IdSanPham': 1,
          'TenXe': 'Xe kiểm thử',
          'TinhTrangXe': condition.isEmpty ? 'moi' : condition,
          'SoKhung': 'KHUNG-TEST',
          'GiaNhap': 1000000,
          'SoLuongTon': 1,
          'GiaBan': null,
        },
      ], vehicleTotal);
    }
    return InventoryPage([
      {
        'IdSanPham': page + 1,
        'MaSanPham': 'XE-TEST',
        'TenSanPham': 'Sản phẩm kiểm thử',
        'LoaiSanPham': 'xe',
        'QuanLyTonKho': 'tung_chiec',
        'DonViTinh': 'chiếc',
      },
    ], 60);
  }

  @override
  Future<Map<String, dynamic>> details(
    InventorySection view,
    Map<String, dynamic> row,
  ) async => {...row, 'SoKhung': 'KHUNG-TEST', 'SoChiecLienKet': 2};
  @override
  Future<void> close() async {
    closed = true;
  }
}
