import 'package:xemay_app/models/customers/customer_models.dart';
import 'package:xemay_app/models/repositories/partner_repository.dart';
import 'fake_directory_repository.dart';

class FakePartnerRepository extends FakeDirectoryRepository
    implements PartnerRepository {
  final partner = <String, dynamic>{
    '_id': 'seller-test',
    'TenDoiTac': 'Người bán kiểm thử',
    'SoDienThoai': '0900000000',
    'DiaChi': 'Thôn 1, Xã thử',
    'MaSoThue': '',
    'NguoiDaiDien': '',
    'GhiChu': '',
  };
  String? requestedPartner;
  @override
  Future<CustomerPage> fetchPartners({
    String search = '',
    int page = 0,
  }) async => CustomerPage([partner], 1);
  @override
  Future<Map<String, dynamic>?> findPartner(String id) async =>
      id == partner['_id'] ? partner : null;
  @override
  Future<CustomerOrderPage> purchaseOrders(
    String partnerId, {
    int page = 0,
  }) async {
    requestedPartner = partnerId;
    return CustomerOrderPage([
      {
        'MaDonHang': 44,
        'IdNhapHang': 44,
        'LoaiSanPham': 'xe_cu',
        'NgayDonHang': DateTime(2026, 11, 1),
        'SanPhamHienThi': 'Xe mua từ đối tác',
        'TongSoLuong': 1,
        'TongTien': null,
      },
    ], 1);
  }
}
