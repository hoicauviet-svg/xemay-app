import 'finance_models.dart';

class OpeningDebtPage {
  const OpeningDebtPage(this.rows, this.total);
  final List<Map<String, dynamic>> rows;
  final int total;
}

class OpeningDebtDetails {
  const OpeningDebtDetails(this.debt, this.customer, this.payments);
  final Map<String, dynamic> debt;
  final Map<String, dynamic>? customer;
  final List<Map<String, dynamic>> payments;
  num? get remaining => debt['SoCoNo'] as num?;
}

class OpeningDebtPayment {
  const OpeningDebtPayment({
    required this.debtId,
    required this.date,
    required this.principal,
    required this.interest,
    required this.collectedInterest,
  });
  final int debtId, principal, interest, collectedInterest;
  final DateTime date;
  String? validate() {
    if ([
      principal,
      interest,
      collectedInterest,
    ].any((n) => n < 0 || n > 1000000000000000)) {
      return 'Số tiền phải là số không âm.';
    }
    if (principal + collectedInterest <= 0) {
      return 'Nhập tiền trả nợ hoặc lãi thực thu lớn hơn 0.';
    }
    return null;
  }

  Map<String, dynamic> toFields() => {
    'IdNoCu': debtId,
    'NgayTra': financeDay(date),
    'SoTienTra': principal.toDouble(),
    'TienLai': interest.toDouble(),
    'LaiThu': collectedInterest.toDouble(),
  };
}
