import 'package:flutter/foundation.dart';
import '../models/customers/customer_models.dart';
import '../models/repositories/partner_repository.dart';

/// The partner tab retains ownership of its repository connection.
class PartnerDetailsController extends ChangeNotifier {
  PartnerDetailsController(this.repository, this.partnerId);
  final PartnerRepository repository;
  final String partnerId;
  Map<String, dynamic>? partner;
  CustomerOrderPage? orders;
  int page = 0, _request = 0;
  bool loading = true, _disposed = false;
  String? error;
  int get pageCount => ((orders?.total ?? 0) / 30).ceil().clamp(1, 1 << 30);
  Future<void> load() async {
    if (_disposed) return;
    final request = ++_request;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final info = await repository.findPartner(partnerId);
      if (_disposed || request != _request) return;
      if (info == null) {
        loading = false;
        error = 'Đối tác không còn trong danh sách.';
        notifyListeners();
        return;
      }
      final result = await repository.purchaseOrders(partnerId, page: page);
      if (_disposed || request != _request) return;
      partner = info;
      orders = result;
      loading = false;
    } catch (_) {
      if (_disposed || request != _request) return;
      loading = false;
      error = 'Chưa tải được thông tin đối tác và đơn hàng. Vui lòng thử lại.';
    }
    notifyListeners();
  }

  void goToPage(int value) {
    if (loading || value < 0 || value >= pageCount) return;
    page = value;
    load();
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    super.dispose();
  }
}
