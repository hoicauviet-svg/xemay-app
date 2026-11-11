import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/customers/customer_models.dart';
import '../models/repositories/customer_repository.dart';

class CustomerController extends ChangeNotifier {
  CustomerController(this.repository, {this.closeRepository = true});
  final bool closeRepository;
  final CustomerRepository repository;
  CustomerPage? data;
  String search = '', phoneFilter = 'all';
  int page = 0, _request = 0;
  bool loading = true, _disposed = false;
  String? error;
  Timer? _timer;
  Future<void> load() async {
    if (_disposed) return;
    final request = ++_request;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await repository.fetch(
        search: search,
        phoneFilter: phoneFilter,
        page: page,
      );
      if (_disposed || request != _request) return;
      if (result.rows.isEmpty && page > 0) {
        page = result.total == 0 ? 0 : ((result.total - 1) / 30).floor();
        await load();
        return;
      }
      data = result;
      loading = false;
    } catch (_) {
      if (_disposed || request != _request) return;
      loading = false;
      error = 'Chưa tải được khách hàng. Vui lòng thử lại.';
    }
    notifyListeners();
  }

  void searchChanged(String value) {
    _timer?.cancel();
    _request++;
    search = value;
    page = 0;
    _timer = Timer(const Duration(milliseconds: 300), () => unawaited(load()));
  }

  void filterChanged(String phone) {
    _timer?.cancel();
    phoneFilter = phone;
    page = 0;
    unawaited(load());
  }

  int get pageCount => ((data?.total ?? 0) / 30).ceil().clamp(1, 1 << 30);
  Future<void> goToPage(int index) async {
    if (loading || index < 0 || index >= pageCount || index == page) return;
    _timer?.cancel();
    page = index;
    await load();
  }

  Future<Map<String, dynamic>> create(CustomerDraft draft) =>
      repository.create(draft);
  Future<void> delete(Map<String, dynamic> customer) =>
      repository.delete(customer);
  String address(Map<String, dynamic> row) =>
      '${row['DiaChiChiTiet'] ?? ''}'.trim();

  @override
  void dispose() {
    _disposed = true;
    _request++;
    _timer?.cancel();
    if (closeRepository) unawaited(repository.close());
    super.dispose();
  }
}
