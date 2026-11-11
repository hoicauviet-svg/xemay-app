import 'package:xemay_app/models/customers/customer_models.dart';
import 'package:xemay_app/models/repositories/customer_repository.dart';

class FakeCustomerRepository implements CustomerRepository {
  bool failSave = false, referenced = false;
  String phoneFilter = 'all', search = '';
  final rows = <Map<String, dynamic>>[
    {
      '_id': 1,
      'IdKH': 1,
      'TenKhachHang': 'Khách kiểm thử',
      'SoDienThoai': '0900000001',
      'DiaChiChiTiet': 'Thôn 1, Xã kiểm thử',
    },
  ];
  @override
  Future<CustomerPage> fetch({
    String search = '',
    String phoneFilter = 'all',
    int page = 0,
  }) async {
    this.search = search;
    this.phoneFilter = phoneFilter;
    final found = rows
        .where((r) => r['TenKhachHang'].toString().contains(search))
        .toList();
    for (final row in found) {
      row['DiaChiHienThi'] = [
        row['DiaChiChiTiet'],
      ].where((v) => v != null && v.toString().trim().isNotEmpty).join(', ');
    }
    return CustomerPage(found, found.length);
  }

  int? lastOrderCustomer;
  String? lastOrderKind;
  @override
  Future<Map<String, dynamic>?> findById(int customerId) async {
    final found = rows.where((r) => r['IdKH'] == customerId);
    return found.isEmpty
        ? null
        : {...found.first, 'DiaChiHienThi': 'Thôn 1, Xã kiểm thử'};
  }

  @override
  Future<CustomerOrderPage> orders(int customerId, {int page = 0}) async {
    lastOrderCustomer = customerId;

    return CustomerOrderPage([
      {
        'MaDonHang': 42,
        'NgayDonHang': DateTime(2026, 11, 1),
        'SanPhamHienThi': 'Xe kiểm thử (#7)',
        'TongSoLuong': 1,
        'TongTien': null,
        'GhiChu': 'Đơn kiểm thử',
      },
    ], 1);
  }

  @override
  Future<Map<String, dynamic>> create(CustomerDraft draft) async {
    if (failSave) throw const CustomerException('Không lưu được khách hàng');
    final row = <String, dynamic>{
      '_id': 2,
      'IdKH': 2,
      'TenKhachHang': draft.name,
      'SoDienThoai': draft.phone,
      'DiaChiChiTiet': draft.address,
      ...draft.identityFields(),
    };
    rows.add(row);
    return {...row, 'DiaChiHienThi': draft.address.trim()};
  }

  @override
  Future<Map<String, dynamic>> update(int id, CustomerDraft draft) async {
    if (failSave) throw const CustomerException('Không lưu được khách hàng');
    final r = rows.firstWhere((r) => r['IdKH'] == id);
    r.addAll({
      'TenKhachHang': draft.name,
      'SoDienThoai': draft.phone,
      'DiaChiChiTiet': draft.address,
      ...draft.identityFields(),
    });
    r.remove('IdXa');
    return r;
  }

  @override
  Future<void> delete(Map<String, dynamic> customer) async {
    if (referenced) {
      throw const CustomerException(
        'Không thể xóa khách hàng đã có giao dịch hoặc công nợ.',
      );
    }
    rows.remove(customer);
  }

  @override
  Future<List<Map<String, dynamic>>> mergeCandidates() async =>
      (await fetch()).rows;

  @override
  Future<List<Map<String, dynamic>>> pendingMerges() async => [];

  @override
  Future<void> merge({
    required int targetId,
    required List<int> sourceIds,
  }) async {
    if (failSave) throw const CustomerException('Không gộp được khách hàng');
    rows.removeWhere((r) => sourceIds.contains(r['IdKH']));
  }

  @override
  Future<void> close() async {}
}
