import 'package:flutter/foundation.dart';
import '../models/finance/finance_models.dart';
import '../models/repositories/finance_repository.dart';

class FundingDetailsController extends ChangeNotifier {
  FundingDetailsController(this.repository, this.id);
  final FinanceRepository repository;
  final int id;
  FundingDetails? data;
  bool loading = true, _disposed = false;
  String? error;
  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await repository.loanDetails(id);
      if (!_disposed) data = result;
    } on FinanceException catch (e) {
      if (!_disposed) error = e.message;
    } catch (_) {
      if (!_disposed) error = 'Chưa tải được khoản vay. Vui lòng thử lại.';
    } finally {
      if (!_disposed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> pay(FundingPaymentDraft draft, String requestId) =>
      repository.repay(draft, requestId: requestId);
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
