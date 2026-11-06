import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/dashboard/dashboard_module.dart';
import '../models/inventory/inventory_models.dart';
import '../models/repositories/inventory_repository.dart';

class ProductListController extends ChangeNotifier {
  ProductListController(this.repository, this.module);
  final InventoryRepository repository;
  final DashboardModule module;
  InventoryPage? _data;
  bool _loading = true, _disposed = false;
  String? _error;
  String _search = '';
  String availability = 'available';
  void setAvailability(String value) {
    _debounce?.cancel();
    availability = value;
    unawaited(load());
  }

  int _request = 0;
  DateTime? loadedAt;
  Timer? _debounce;
  InventoryPage? get data => _data;
  bool get loading => _loading;
  String? get error => _error;
  String get search => _search;
  InventorySection get section => module == DashboardModule.parts
      ? InventorySection.parts
      : InventorySection.vehicles;
  String get condition => switch (module) {
    DashboardModule.newVehicles => 'moi',
    DashboardModule.usedVehicles => 'cu',
    _ => '',
  };
  Future<void> load() async {
    if (_disposed) return;
    final request = ++_request;
    final search = _search;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await repository.connect();
      if (_disposed || request != _request) return;
      final result = await repository.fetch(
        section,
        condition: condition,
        availability: availability,
        search: search,
        pageSize: 0,
      );
      if (_disposed || request != _request) return;
      _data = result;
      loadedAt = DateTime.now();
      _loading = false;
    } catch (_) {
      if (_disposed || request != _request) return;
      _loading = false;
      _error = 'Chưa tải được sản phẩm. Kiểm tra dữ liệu trên máy và thử lại.';
    }
    notifyListeners();
  }

  void searchChanged(String value) {
    if (_disposed) return;
    _debounce?.cancel();
    _request++;
    _search = value;
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(load()),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    _debounce?.cancel();
    unawaited(repository.close());
    super.dispose();
  }
}
