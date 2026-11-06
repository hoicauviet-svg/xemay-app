import 'package:flutter/foundation.dart';
import '../models/finance/opening_debt.dart';
import '../models/repositories/opening_debt_repository.dart';

class OpeningDebtController extends ChangeNotifier {
  OpeningDebtController(this.repository);
  final OpeningDebtRepository repository;
  OpeningDebtPage? data;
  String search = '', status = 'open';
  DateTime? loadedAt;
  String? error;
  int _request = 0;
  bool loading = false, _disposed = false;
  Future<void> load() async {
    if (_disposed) return;
    final request = ++_request;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await repository.list(search: search, status: status);
      if (_disposed || request != _request) return;
      data = result;
      loadedAt = DateTime.now();
    } catch (_) {
      if (_disposed || request != _request) return;
      error = 'Chưa tải được danh sách nợ cũ. Vui lòng thử lại.';
    }
    loading = false;
    notifyListeners();
  }

  void filter({String? term, String? state}) {
    search = term ?? search;
    status = state ?? status;
    load();
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    super.dispose();
  }
}

class OpeningDebtDetailsController extends ChangeNotifier {
  OpeningDebtDetailsController(this.repository, this.id);
  final OpeningDebtRepository repository;
  final int id;
  OpeningDebtDetails? data;
  bool loading = true, _disposed = false;
  String? error;
  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await repository.details(id);
      if (!_disposed) data = result;
    } catch (_) {
      if (!_disposed) error = 'Chưa tải được khoản nợ. Vui lòng thử lại.';
    } finally {
      if (!_disposed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> pay(OpeningDebtPayment payment, String requestId) =>
      repository.pay(payment, requestId: requestId);
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
