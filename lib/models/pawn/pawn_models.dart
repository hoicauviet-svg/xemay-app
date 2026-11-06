class PawnDraft {
  int? customerId;
  String asset = '', amount = '', rate = '', notes = '';
  DateTime loanDate = DateTime.now();
  DateTime? dueDate;
  bool daily = true, closed = false;
  num? get interestRate => num.tryParse(rate.trim().replaceAll(',', '.'));
  String? validate() {
    if (customerId == null) return 'Vui lòng chọn khách hàng từ danh sách.';
    if (asset.trim().isEmpty) return 'Vui lòng nhập tài sản thế chấp.';
    final principal = int.tryParse(amount);
    if (principal == null || principal <= 0 || principal > 1000000000000000) {
      return 'Số tiền vay phải lớn hơn 0.';
    }
    final interest = interestRate;
    if (interest == null || !interest.isFinite || interest < 0) {
      return 'Lãi suất phải là số không âm.';
    }
    if (dueDate == null) return 'Vui lòng chọn ngày hạn.';
    if (DateTime(
      dueDate!.year,
      dueDate!.month,
      dueDate!.day,
    ).isBefore(DateTime(loanDate.year, loanDate.month, loanDate.day))) {
      return 'Ngày hạn không được trước ngày vay.';
    }
    return null;
  }

  PawnDraft snapshot() => PawnDraft()
    ..customerId = customerId
    ..asset = asset
    ..amount = amount
    ..rate = rate
    ..notes = notes
    ..loanDate = loanDate
    ..dueDate = dueDate
    ..daily = daily
    ..closed = closed;

  Map<String, dynamic> toFields() => {
    'SoTienVay': int.parse(amount).toDouble(),
    'TaiSanTheChap': asset.trim(),
    'NgayPhanTram': daily,
    'LaiSuat': interestRate!.toDouble(),
    'NgayHan': DateTime.utc(dueDate!.year, dueDate!.month, dueDate!.day),
    'NgayVay': DateTime.utc(loanDate.year, loanDate.month, loanDate.day),
    'IdKhachHang': customerId,
    'GhiChu': notes.trim(),
    'TrangThai': closed,
  };
}

class PawnPage {
  const PawnPage(this.rows, this.total);
  final List<Map<String, dynamic>> rows;
  final int total;
}

class PawnException implements Exception {
  const PawnException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PawnDetails {
  const PawnDetails({
    required this.contract,
    required this.payments,
    this.customer,
  });
  final Map<String, dynamic> contract;
  final Map<String, dynamic>? customer;
  final List<Map<String, dynamic>> payments;
  num? get principalPaid {
    if (payments.any(
      (p) =>
          p['TienGoc'] is! num ||
          !(p['TienGoc'] as num).isFinite ||
          (p['TienGoc'] as num) < 0,
    )) {
      return null;
    }
    return payments.fold<num>(0, (sum, p) => sum + (p['TienGoc'] as num));
  }

  num? get remaining {
    final amount = contract['SoTienVay'];
    final paid = principalPaid;
    if (amount is! num ||
        !amount.isFinite ||
        amount < 0 ||
        paid == null ||
        paid > amount) {
      return null;
    }
    return amount - paid;
  }

  static DateTime _day(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);
  DateTime? get interestStartDate {
    final loan = contract['NgayVay'];
    if (loan is! DateTime) return null;
    var start = _day(loan);
    for (final payment in payments) {
      final collected = payment['LaiThu'], date = payment['NgayTra'];
      if (collected is num && collected.isFinite && collected > 0) {
        if (date is! DateTime) return null;
        final paidDay = _day(date);
        if (paidDay.isAfter(start)) start = paidDay;
      }
    }
    return start;
  }

  PawnInterestAccrual? interestAccrualAt(DateTime asOf) {
    final start = interestStartDate,
        loan = contract['SoTienVay'],
        rate = contract['LaiSuat'],
        daily = contract['NgayPhanTram'];
    if (start == null ||
        loan is! num ||
        !loan.isFinite ||
        loan < 0 ||
        rate is! num ||
        !rate.isFinite ||
        rate < 0 ||
        daily is! bool ||
        remaining == null) {
      return null;
    }
    if (contract['TrangThai'] == true) {
      return PawnInterestAccrual(start: start, days: 0, amount: 0);
    }
    if (contract['TrangThai'] != false) return null;
    final end = _day(asOf);
    final days = end.difference(start).inDays;
    if (days <= 0) return PawnInterestAccrual(start: start, days: 0, amount: 0);
    var principal = loan;
    final events = <({DateTime date, num principal})>[];
    for (final payment in payments) {
      final paid = payment['TienGoc'];
      if (paid is! num || !paid.isFinite || paid < 0) return null;
      if (paid == 0) continue;
      final date = payment['NgayTra'];
      if (date is! DateTime) return null;
      final paidDay = _day(date);
      if (!paidDay.isAfter(start)) {
        principal -= paid;
      } else if (!paidDay.isAfter(end)) {
        events.add((date: paidDay, principal: paid));
      }
    }
    if (principal < 0) return null;
    events.sort((a, b) => a.date.compareTo(b.date));
    final factor = daily ? rate / 1000000 : rate / 100 / 30;
    num amount = 0;
    var cursor = start;
    for (final event in events) {
      amount += principal * factor * event.date.difference(cursor).inDays;
      principal -= event.principal;
      if (principal < 0) return null;
      cursor = event.date;
    }
    amount += principal * factor * end.difference(cursor).inDays;
    if (!amount.isFinite) return null;
    return PawnInterestAccrual(start: start, days: days, amount: amount);
  }

  DateTime? defaultAppointmentAt(DateTime today) {
    final due = contract['NgayHan'];
    if (due is! DateTime) return null;
    if ((overdueDaysAt(today) ?? 0) <= 0) return due;
    final lastDay = DateTime.utc(today.year, today.month + 2, 0).day;
    return DateTime.utc(
      today.year,
      today.month + 1,
      today.day > lastDay ? lastDay : today.day,
    );
  }

  int? overdueDaysAt(DateTime asOf) {
    if (contract['TrangThai'] == true) return 0;
    final due = contract['NgayHan'];
    if (contract['TrangThai'] != false || due is! DateTime) return null;
    final days = DateTime.utc(
      asOf.year,
      asOf.month,
      asOf.day,
    ).difference(DateTime.utc(due.year, due.month, due.day)).inDays;
    return days > 0 ? days : 0;
  }

  bool get canPay =>
      contract['TrangThai'] == false && remaining != null && remaining! > 0;
}

class PawnInterestAccrual {
  const PawnInterestAccrual({
    required this.start,
    required this.days,
    required this.amount,
  });
  final DateTime start;
  final int days;
  final num amount;
  int get roundedAmount => amount.round();
}

class PawnPaymentDraft {
  const PawnPaymentDraft({
    required this.pawnId,
    required this.date,
    required this.principal,
    required this.interest,
    required this.collectedInterest,
    this.appointmentDate,
  });
  final int pawnId, principal, interest, collectedInterest;
  final DateTime date;
  final DateTime? appointmentDate;
  Map<String, dynamic> toFields() => {
    'IdCamDo': pawnId,
    'NgayTra': DateTime.utc(date.year, date.month, date.day),
    'TienGoc': principal.toDouble(),
    'SoTienLai': interest.toDouble(),
    'LaiThu': collectedInterest.toDouble(),
    if (appointmentDate case final next?)
      'NgayHen': DateTime.utc(next.year, next.month, next.day),
  };
  String? validate() {
    final next = appointmentDate;
    if (next != null &&
        DateTime.utc(
          next.year,
          next.month,
          next.day,
        ).isBefore(DateTime.utc(date.year, date.month, date.day))) {
      return 'Ngày hẹn không được trước ngày trả.';
    }
    if ([
      principal,
      interest,
      collectedInterest,
    ].any((v) => v < 0 || v > 1000000000000000)) {
      return 'Số tiền phải là số không âm hợp lệ.';
    }
    if (principal + collectedInterest <= 0) {
      return 'Vui lòng nhập tiền gốc hoặc lãi thực thu lớn hơn 0.';
    }
    return null;
  }
}
