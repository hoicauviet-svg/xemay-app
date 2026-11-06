import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/customers/customer_models.dart';
import '../models/repositories/partner_repository.dart';

class PartnerController extends ChangeNotifier {
  PartnerController(this.repository);
  final PartnerRepository repository;
  CustomerPage? data;
  bool loading = true, _disposed = false;
  String? error;
  String search = '';
  int page = 0, _request = 0;
  Timer? _timer;
  int get pageCount => ((data?.total ?? 0) / 30).ceil().clamp(1, 1 << 30);
  Future<void> load() async {
    if (_disposed) return;
    final request = ++_request;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await repository.fetchPartners(search: search, page: page);
      if (_disposed || request != _request) return;
      data = result;
      loading = false;
    } catch (_) {
      if (_disposed || request != _request) return;
      loading = false;
      error = 'Chưa tải được đối tác. Vui lòng thử lại.';
    }
    notifyListeners();
  }

  void searchChanged(String v) {
    _timer?.cancel();
    _request++;
    search = v;
    page = 0;
    _timer = Timer(const Duration(milliseconds: 300), () => unawaited(load()));
  }

  void goToPage(int v) {
    if (loading || v < 0 || v >= pageCount) return;
    _timer?.cancel();
    page = v;
    unawaited(load());
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    _timer?.cancel();
    unawaited(repository.close());
    super.dispose();
  }
}
