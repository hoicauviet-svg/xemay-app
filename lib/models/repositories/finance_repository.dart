import '../maintenance/record_maintenance.dart';
import '../finance/cash_category.dart';
import '../finance/finance_models.dart';

abstract class FinanceRepository {
  RecordMaintenance? get maintenance => null;
  Future<List<CashCategory>> categories() async => CashCategory.defaults;
  Future<void> saveCategory(CashCategory category) async =>
      throw UnimplementedError();
  Future<void> archiveCategory(String id) async => throw UnimplementedError();
  Future<FinancePage> cashEntries({
    String search = '',
    String type = 'all',
    int page = 0,
    DateTime? fromDate,
    DateTime? toDate,
  });
  Future<int> createCash(CashEntryDraft draft, {required String requestId});
  Future<FinancePage> loans({String search = '', String status = 'open'});
  Future<int> createLoan(FundingLoanDraft draft, {required String requestId});
  Future<FundingDetails> loanDetails(int id);
  Future<void> repay(FundingPaymentDraft payment, {required String requestId});
  Future<void> close();
}
