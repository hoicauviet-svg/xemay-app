import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/models/pawn/pawn_models.dart';

void main() {
  PawnDetails details({
    bool daily = false,
    num rate = 3,
    bool closed = false,
    List<Map<String, dynamic>> payments = const [],
  }) => PawnDetails(
    contract: {
      'NgayVay': DateTime.utc(2026, 11, 1),
      'NgayHan': DateTime.utc(2026, 11, 5),
      'SoTienVay': 10000000,
      'LaiSuat': rate,
      'NgayPhanTram': daily,
      'TrangThai': closed,
    },
    payments: payments,
  );
  test('Monthly percent divides by 30 using elapsed calendar days', () {
    final result = details().interestAccrualAt(DateTime(2026, 11, 11, 23, 59))!;
    expect(result.days, 10);
    expect(result.amount, closeTo(100000, 0.001));
    expect(
      details(rate: 2.5).interestAccrualAt(DateTime(2026, 11, 16))!.amount,
      closeTo(125000, 0.001),
    );
    expect(details().interestAccrualAt(DateTime(2026, 11, 1))!.amount, 0);
  });
  test('Daily interest is quoted per million, not flat total per day', () {
    final result = details(
      daily: true,
      rate: 2000,
    ).interestAccrualAt(DateTime(2026, 11, 11))!;
    expect(result.days, 10);
    expect(result.amount, 200000);
  });
  test(
    'Latest actual interest payment resets start; calculated-only and principal-only do not',
    () {
      final result = details(
        payments: [
          {
            'NgayTra': DateTime.utc(2026, 11, 5),
            'TienGoc': 0,
            'SoTienLai': 100000,
            'LaiThu': 100000,
          },
          {
            'NgayTra': DateTime.utc(2026, 11, 8),
            'TienGoc': 0,
            'SoTienLai': 100000,
            'LaiThu': 0,
          },
          {
            'NgayTra': DateTime.utc(2026, 11, 9),
            'TienGoc': 0,
            'SoTienLai': 100000,
            'LaiThu': null,
          },
        ],
      ).interestAccrualAt(DateTime(2026, 11, 11))!;
      expect(result.start, DateTime.utc(2026, 11, 5));
      expect(result.days, 6);
      expect(result.amount, closeTo(60000, 0.001));
    },
  );
  test(
    'Partial principal payments change interest only from their payment date',
    () {
      final result = details(
        payments: [
          {
            'NgayTra': DateTime.utc(2026, 11, 6),
            'TienGoc': 4000000,
            'LaiThu': 0,
          },
        ],
      ).interestAccrualAt(DateTime(2026, 11, 11))!;
      expect(result.days, 10);
      expect(result.amount, closeTo(80000, 0.001));
      final restarted = details(
        payments: [
          {
            'NgayTra': DateTime.utc(2026, 11, 6),
            'TienGoc': 4000000,
            'LaiThu': 100000,
          },
        ],
      ).interestAccrualAt(DateTime(2026, 11, 11))!;
      expect(restarted.days, 5);
      expect(restarted.amount, closeTo(30000, 0.001));
    },
  );
  test(
    'Settled contracts do not continue accruing; incomplete data stays uncalculated',
    () {
      expect(
        details(closed: true).interestAccrualAt(DateTime(2026, 12, 1))!.amount,
        0,
      );
      expect(details().interestAccrualAt(DateTime(2026, 10, 31))!.days, 0);
      final invalid = PawnDetails(
        contract: {'SoTienVay': 1000000},
        payments: const [],
      );
      expect(invalid.interestAccrualAt(DateTime(2026, 11, 4)), isNull);
    },
  );
}
