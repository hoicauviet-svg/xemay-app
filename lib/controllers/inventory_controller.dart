import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/inventory/inventory_models.dart';
import '../models/repositories/inventory_repository.dart';

/// Owns inventory state and user actions. No widgets or database driver here.
class InventoryController extends ChangeNotifier {
  InventoryController(this._repository);
  final InventoryRepository _repository;
  static const searchDelay = Duration(milliseconds: 300);
  final int pageSize = 30;
  InventorySection _section = InventorySection.products;
  InventorySummary? _summary;
  InventoryPage? _data;
  String _search = '', _condition = '';
  String? _error;
  bool _loading = true, _connected = false, _disposed = false;
  int _page = 0, _request = 0;
  Timer? _debounce;

  InventorySection get section => _section;
  InventorySummary? get summary => _summary;
  InventoryPage? get data => _data;
  String get search => _search;
  String get condition => _condition;
  String? get error => _error;
  bool get loading => _loading;
  bool get connected => _connected;
  int get page => _page;
  bool get hasPreviousPage => !_loading && _page > 0;
  bool get hasNextPage =>
      !_loading && (_page + 1) * pageSize < (_data?.total ?? 0);

  Future<void> load({bool refreshSummary = false}) async {
    if (_disposed) return;
    final request = ++_request;
    final section = _section,
        search = _search,
        condition = _condition,
        page = _page;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await _repository.connect();
      if (_disposed || request != _request) return;
      final summary = refreshSummary || _summary == null
          ? await _repository.summary()
          : _summary;
      if (_disposed || request != _request) return;
      final result = await _repository.fetch(
        section,
        search: search,
        condition: condition,
        page: page,
        pageSize: pageSize,
      );
      if (_disposed || request != _request) return;
      _summary = summary;
      _data = result;
      _connected = true;
      _loading = false;
    } catch (_) {
      if (_disposed || request != _request) return;
      _loading = false;
      _connected = false;
      _error =
          'Hãy kiểm tra dịch vụ dữ liệu trên máy đã chạy, rồi thử kết nối lại.';
    }
    notifyListeners();
  }

  void selectSection(InventorySection section) {
    if (_disposed) return;
    _debounce?.cancel();
    _section = section;
    _search = '';
    _condition = '';
    _page = 0;
    _data = null;
    unawaited(load());
  }

  void searchChanged(String value) {
    if (_disposed) return;
    _debounce?.cancel();
    _request++;
    _search = value;
    _page = 0;
    _debounce = Timer(searchDelay, () => unawaited(load()));
  }

  void setCondition(String value) {
    if (_disposed) return;
    _debounce?.cancel();
    _condition = value;
    _page = 0;
    unawaited(load());
  }

  void nextPage() {
    if (_disposed || !hasNextPage) return;
    _page++;
    unawaited(load());
  }

  void previousPage() {
    if (_disposed || !hasPreviousPage) return;
    _page--;
    unawaited(load());
  }

  Future<Map<String, dynamic>> details(
    InventorySection section,
    Map<String, dynamic> row,
  ) => _repository.details(section, row);

  @override
  void dispose() {
    _disposed = true;
    _request++;
    _debounce?.cancel();
    unawaited(_repository.close());
    super.dispose();
  }
}
