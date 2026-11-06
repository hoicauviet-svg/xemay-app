import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/batches/batch_models.dart';
import '../models/goods_receipt/goods_receipt_models.dart';
import '../models/repositories/batch_repository.dart';

class BatchListController extends ChangeNotifier {
  BatchListController(this.repository, this.type);
  final BatchRepository repository;
  final ReceiptProductType type;
  final int pageSize = 30;
  BatchPage? _data;
  bool _loading = true, _disposed = false;
  String? _error;
  String _search = '';
  int _page = 0, _request = 0;
  Timer? _debounce;

  BatchPage? get data => _data;
  bool get loading => _loading;
  String? get error => _error;
  int get page => _page;
  bool get hasPrevious => !_loading && _page > 0;
  bool get hasNext => !_loading && (_page + 1) * pageSize < (_data?.total ?? 0);

  Future<void> load() async {
    if (_disposed) return;
    final request = ++_request;
    final page = _page, search = _search;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await repository.connect();
      if (_disposed || request != _request) return;
      final result = await repository.fetch(
        type,
        page: page,
        pageSize: pageSize,
        search: search,
      );
      if (_disposed || request != _request) return;
      _data = result;
      _loading = false;
    } catch (_) {
      if (_disposed || request != _request) return;
      _loading = false;
      _error = 'Không tải được lô hàng. Kiểm tra dữ liệu trên máy và thử lại.';
    }
    notifyListeners();
  }

  void searchChanged(String value) {
    _debounce?.cancel();
    _request++;
    _page = 0;
    _search = value;
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(load()),
    );
  }

  void nextPage() {
    if (hasNext) {
      _page++;
      unawaited(load());
    }
  }

  void previousPage() {
    if (hasPrevious) {
      _page--;
      unawaited(load());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    _debounce?.cancel();
    super.dispose();
  }
}
