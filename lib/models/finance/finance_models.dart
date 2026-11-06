DateTime financeDay(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);
int? financeMoney(String value) => int.tryParse(value.trim());

class FinanceException implements Exception {
  const FinanceException(this.message);
  final String message;
  @override
  String toString() => message;
}

class FinancePage {
  const FinancePage(this.rows, this.total, {this.income = 0, this.expense = 0});
  final List<Map<String, dynamic>> rows;
  final int total;
  final num income, expense;
}

class CashEntryDraft {
  DateTime date = DateTime.now();
  bool income = true;
  String reason = '', amount = '';
  String? categoryId, categoryName;
  String? validate() {
    final value = financeMoney(amount);
    if (value == null || value <= 0 || value > 1000000000000000) {
      return 'Nhập số tiền lớn hơn 0.';
    }
    if (reason.trim().isEmpty) return 'Vui lòng nhập lý do thu/chi.';
    return null;
  }

  Map<String, dynamic> toFields() => {
    'NgayThang': financeDay(date),
    'LyDo': reason.trim(),
    'SoTien': financeMoney(amount)!.toDouble(),
    'ThuChi': income,
    if (categoryId != null) 'IdDanhMuc': categoryId,
    if (categoryName != null) 'TenDanhMuc': categoryName,
  };
  CashEntryDraft snapshot() => CashEntryDraft()
    ..date = date
    ..income = income
    ..reason = reason
    ..amount = amount
    ..categoryId = categoryId
    ..categoryName = categoryName;
}

class FundingLoanDraft {
  String amount = '', rate = '', partner = '', notes = '';
  DateTime date = DateTime.now();
  DateTime? dueDate, interestDate;
  num? get parsedRate => num.tryParse(rate.trim().replaceAll(',', '.'));
  String? validate() {
    final value = financeMoney(amount);
    final interest = parsedRate;
    if (value == null || value <= 0 || value > 1000000000000000) {
      return 'Nhập số tiền vay lớn hơn 0.';
    }
    if (partner.trim().isEmpty) return 'Vui lòng nhập đối tác cho vay.';
    if (interest == null || !interest.isFinite || interest < 0) {
      return 'Lãi suất phải là số không âm.';
    }
    if (dueDate == null) return 'Vui lòng chọn ngày hẹn.';
    if (financeDay(dueDate!).isBefore(financeDay(date))) {
      return 'Ngày hẹn không được trước ngày vay.';
    }
    if (interestDate != null &&
        financeDay(interestDate!).isBefore(financeDay(date))) {
      return 'Ngày tính lãi không được trước ngày vay.';
    }
    return null;
  }

  Map<String, dynamic> toFields() => {
    'SoTienVay': financeMoney(amount)!.toDouble(),
    'NgayVay': financeDay(date),
    'LaiSuat': parsedRate!.toDouble(),
    'NgayHen': financeDay(dueDate!),
    'DoiTac': partner.trim(),
    'GhiChu': notes.trim(),
    'TongConNo': financeMoney(amount)!.toDouble(),
    'NgayTinhLai': financeDay(interestDate ?? date),
  };
  FundingLoanDraft snapshot() => FundingLoanDraft()
    ..amount = amount
    ..rate = rate
    ..partner = partner
    ..notes = notes
    ..date = date
    ..dueDate = dueDate
    ..interestDate = interestDate;
}

class FundingDetails {
  const FundingDetails({required this.loan, required this.payments});
  final Map<String, dynamic> loan;
  final List<Map<String, dynamic>> payments;
  num? get remaining => loan['TongConNo'] as num?;
  bool get canPay => remaining != null && remaining!.isFinite && remaining! > 0;
  int? interestAt(DateTime date) {
    final original = loan['SoTienVay'],
        rate = loan['LaiSuat'],
        startValue = loan['NgayTinhLai'] ?? loan['NgayVay'];
    if (original is! num ||
        !original.isFinite ||
        rate is! num ||
        !rate.isFinite ||
        rate < 0 ||
        startValue is! DateTime ||
        remaining == null ||
        !remaining!.isFinite ||
        remaining! < 0) {
      return null;
    }
    if (remaining == 0) return 0;
    final start = financeDay(startValue), end = financeDay(date);
    if (!end.isAfter(start)) return 0;
    num principal = original, interest = 0;
    var cursor = start;
    final events = <({DateTime date, num amount})>[];
    for (final payment in payments) {
      final amount = payment['SoTienTraGoc'];
      if (amount is! num || !amount.isFinite || amount < 0) return null;
      if (amount == 0) continue;
      final paidDate = payment['NgayTra'];
      if (paidDate is! DateTime) return null;
      final day = financeDay(paidDate);
      if (!day.isAfter(start)) {
        principal -= amount;
      } else if (!day.isAfter(end)) {
        events.add((date: day, amount: amount));
      }
    }
    if (principal < 0) return null;
    events.sort((a, b) => a.date.compareTo(b.date));
    for (final event in events) {
      interest +=
          principal * rate / 100 / 30 * event.date.difference(cursor).inDays;
      principal -= event.amount;
      if (principal < 0) return null;
      cursor = event.date;
    }
    interest += principal * rate / 100 / 30 * end.difference(cursor).inDays;
    return interest.isFinite ? interest.round() : null;
  }
}

class FundingPaymentDraft {
  const FundingPaymentDraft({
    required this.loanId,
    required this.date,
    required this.principal,
    required this.interest,
  });
  final int loanId, principal, interest;
  final DateTime date;
  String? validate() {
    if ([principal, interest].any((v) => v < 0 || v > 1000000000000000) ||
        principal + interest <= 0) {
      return 'Vui lòng nhập tiền gốc hoặc tiền lãi lớn hơn 0.';
    }
    return null;
  }

  Map<String, dynamic> toFields() => {
    'IdVayVon': loanId,
    'NgayTra': financeDay(date),
    'SoTienTraGoc': principal.toDouble(),
    'SoTienTraLai': interest.toDouble(),
  };
}
