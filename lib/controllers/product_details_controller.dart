import 'package:flutter/foundation.dart';
import '../models/products/product_details.dart';
import '../models/repositories/product_details_repository.dart';

class ProductDetailsController extends ChangeNotifier {
  ProductDetailsController(this.repository, this.product);
  final ProductDetailsRepository repository;
  final ProductReference product;
  ProductDetails? data;
  bool loading = false, saving = false, _disposed = false;
  String? error;
  Future<void> load({bool silent = false}) async {
    final keepVisible = silent && data != null;
    if (!keepVisible) {
      loading = true;
      error = null;
      notifyListeners();
    }
    try {
      final result = await repository.load(product);
      if (_disposed) return;
      data = result;
      error = null;
    } catch (_) {
      if (_disposed) return;
      if (data == null) {
        error = 'Không tải được chi tiết sản phẩm. Vui lòng thử lại.';
      } else if (keepVisible) {
        rethrow;
      }
    } finally {
      if (!_disposed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> addCost({
    required DateTime date,
    required int amount,
    required String notes,
    required String requestId,
  }) async {
    if (saving) return;
    saving = true;
    notifyListeners();
    try {
      await repository.addCost(
        product,
        date: date,
        amount: amount,
        notes: notes,
        requestId: requestId,
      );
    } finally {
      if (!_disposed) {
        saving = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
