import 'package:xemay_app/models/finance/cash_category.dart';
import 'package:xemay_app/models/finance/finance_models.dart';
import 'package:xemay_app/models/repositories/finance_repository.dart';

class FakeFinance extends FinanceRepository {
  final categoryRows = [...CashCategory.defaults];
  @override
  Future<List<CashCategory>> categories() async => List.of(categoryRows);
  @override
  Future<void> saveCategory(CashCategory category) async {
    categoryRows.removeWhere((c) => c.id == category.id);
    categoryRows.add(category);
  }

  @override
  Future<void> archiveCategory(String id) async {
    categoryRows.removeWhere((c) => c.id == id);
  }

  CashEntryDraft? saved;
  String filter = '';
  List<Map<String, dynamic>>? fundingRows;
  DateTime? from, to;
  FundingPaymentDraft? paid;
  final loan = <String, dynamic>{
    'IdVayVon': 1,
    'SoTienVay': 1000000.0,
    'TongConNo': 1000000.0,
    'LaiSuat': 3.0,
    'DoiTac': 'Người cho vay',
    'NgayVay': DateTime.utc(2026, 1, 1),
    'NgayHen': DateTime.utc(2027, 1, 1),
    'NgayTinhLai': DateTime.utc(2026, 1, 1),
  };
  @override
  Future<FinancePage> cashEntries({
    String search = '',
    String type = 'all',
    int page = 0,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    filter = type;
    from = fromDate;
    to = toDate;
    return FinancePage(
      [
        {
          'ThuChiId': 1,
          'ThuChi': true,
          'SoTien': 100000.0,
          'LyDo': 'Thu thử',
          'NgayThang': DateTime.utc(2026, 1, 1),
        },
      ],
      1,
      income: 100000,
    );
  }

  @override
  Future<int> createCash(
    CashEntryDraft draft, {
    required String requestId,
  }) async {
    saved = draft;
    return 2;
  }

  @override
  Future<int> createLoan(
    FundingLoanDraft draft, {
    required String requestId,
  }) async => 2;
  @override
  Future<FinancePage> loans({
    String search = '',
    String status = 'open',
  }) async {
    filter = status;
    final rows = fundingRows ?? [loan];
    return FinancePage(rows, rows.length);
  }

  @override
  Future<FundingDetails> loanDetails(int id) async =>
      FundingDetails(loan: loan, payments: []);
  @override
  Future<void> repay(
    FundingPaymentDraft payment, {
    required String requestId,
  }) async {
    paid = payment;
  }

  @override
  Future<void> close() async {}
}
