import 'package:flutter/foundation.dart';
import '../models/customers/customer_models.dart';
import '../models/repositories/customer_repository.dart';

/// Uses the customer tab's repository; the tab retains connection ownership.
class CustomerDetailsController extends ChangeNotifier {
  CustomerDetailsController(this.repository, this.customerId);
  final CustomerRepository repository;
  final int customerId;
  Map<String, dynamic>? customer;
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
      final info = await repository.findById(customerId);
      if (_disposed || request != _request) return;
      if (info == null) {
        loading = false;
        error = 'Khách hàng không còn trong danh sách.';
        notifyListeners();
        return;
      }
      final result = await repository.orders(customerId, page: page);
      if (_disposed || request != _request) return;
      customer = info;
      orders = result;
      loading = false;
    } catch (_) {
      if (_disposed || request != _request) return;
      loading = false;
      error =
          'Chưa tải được thông tin khách hàng và đơn hàng. Vui lòng thử lại.';
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
