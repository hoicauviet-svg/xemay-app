import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/services/service_models.dart';
import '../models/repositories/service_repository.dart';

class ServiceController extends ChangeNotifier {
  ServiceController(this.repository);
  final ServiceRepository repository;
  ServicePage? data;
  bool loading = true, _disposed = false;
  String search = '';
  String? error;
  int _request = 0;
  DateTime? loadedAt;
  Timer? _timer;
  Future<void> load() async {
    if (_disposed) return;
    final request = ++_request;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await repository.fetch(search: search);
      if (_disposed || request != _request) return;
      data = result;
      loadedAt = DateTime.now();
      loading = false;
    } catch (_) {
      if (_disposed || request != _request) return;
      loading = false;
      error = 'Chưa tải được dịch vụ. Vui lòng thử lại.';
    }
    notifyListeners();
  }

  void searchChanged(String value) {
    _timer?.cancel();
    _request++;
    search = value;
    _timer = Timer(const Duration(milliseconds: 300), () => unawaited(load()));
  }

  Future<ServiceItem> create(ServiceDraft draft) => repository.create(draft);
  @override
  void dispose() {
    _disposed = true;
    _request++;
    _timer?.cancel();
    unawaited(repository.close());
    super.dispose();
  }
}
