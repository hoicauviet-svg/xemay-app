import 'package:flutter/foundation.dart';
import '../models/orders/order_details.dart';
import '../models/repositories/order_repository.dart';

class OrderDetailsController extends ChangeNotifier {
  OrderDetailsController(this.repository, this.orderId);
  final OrderRepository repository;
  final int orderId;
  OrderDetails? data;
  bool loading = false, _disposed = false;
  String? error;
  Future<void> load() async {
    if (_disposed) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await repository.load(orderId);
      if (!_disposed) data = result;
    } on OrderException catch (e) {
      if (!_disposed) error = e.message;
    } catch (_) {
      if (!_disposed) error = 'Chưa tải được đơn hàng. Vui lòng thử lại.';
    }
    if (!_disposed) {
      loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
