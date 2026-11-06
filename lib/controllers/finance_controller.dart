import 'package:flutter/foundation.dart';
import '../models/finance/finance_models.dart';
import '../models/repositories/finance_repository.dart';

class FinanceController extends ChangeNotifier {
  FinanceController(this.repository, {required this.loans})
    : filter = loans ? 'open' : 'all';
  final FinanceRepository repository;
  final bool loans;
  FinancePage? data;
  String search = '', filter;
  DateTime? fromDate, toDate;
  int page = 0, _request = 0;
  bool loading = false, _disposed = false;
  DateTime? loadedAt;
  String? error;
  int get pageCount => ((data?.total ?? 0) / 30).ceil().clamp(1, 1000000);
  Future<void> load() async {
    if (_disposed) return;
    final request = ++_request;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = loans
          ? await repository.loans(search: search, status: filter)
          : await repository.cashEntries(
              search: search,
              type: filter,
              fromDate: fromDate,
              toDate: toDate,
              page: page,
            );
      if (_disposed || request != _request) return;
      data = result;
      loadedAt = DateTime.now();
    } catch (_) {
      if (_disposed || request != _request) return;
      error = 'Chưa tải được dữ liệu tài chính. Vui lòng thử lại.';
    }
    loading = false;
    notifyListeners();
  }

  void setDateRange(DateTime? from, DateTime? to) {
    fromDate = from == null ? null : financeDay(from);
    toDate = to == null ? null : financeDay(to);
    page = 0;
    load();
  }

  void updateSearch(String value) {
    search = value;
    page = 0;
    load();
  }

  void setFilter(String value) {
    filter = value;
    page = 0;
    load();
  }

  void goToPage(int value) {
    if (loans || loading || value < 0 || value >= pageCount) return;
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
