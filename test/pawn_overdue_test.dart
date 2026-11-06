import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/models/pawn/pawn_models.dart';

void main() {
  test(
    'Appointment keeps unexpired date or advances one calendar month from today',
    () {
      PawnDetails contract(DateTime due) => PawnDetails(
        contract: {'NgayHan': due, 'TrangThai': false},
        payments: const [],
      );
      expect(
        contract(
          DateTime.utc(2026, 11, 4),
        ).defaultAppointmentAt(DateTime(2026, 11, 4)),
        DateTime.utc(2026, 11, 4),
      );
      expect(
        contract(
          DateTime.utc(2026, 12, 20),
        ).defaultAppointmentAt(DateTime(2026, 11, 4)),
        DateTime.utc(2026, 12, 20),
      );
      expect(
        contract(
          DateTime.utc(2026, 11, 3),
        ).defaultAppointmentAt(DateTime(2026, 11, 4)),
        DateTime.utc(2026, 12, 4),
      );
      expect(
        contract(
          DateTime.utc(2026, 1, 1),
        ).defaultAppointmentAt(DateTime(2026, 1, 31)),
        DateTime.utc(2026, 2, 28),
      );
      expect(
        contract(
          DateTime.utc(2028, 1, 1),
        ).defaultAppointmentAt(DateTime(2028, 1, 31)),
        DateTime.utc(2028, 2, 29),
      );
    },
  );

  PawnDetails details(DateTime? due, {bool? closed = false}) => PawnDetails(
    contract: {'NgayHan': due, 'TrangThai': closed},
    payments: const [],
  );
  test('Overdue uses calendar dates and starts after the due date', () {
    final d = details(DateTime.utc(2026, 11, 4, 23, 59));
    expect(d.overdueDaysAt(DateTime(2026, 11, 4, 0)), 0);
    expect(d.overdueDaysAt(DateTime(2026, 11, 5, 0)), 1);
    expect(d.overdueDaysAt(DateTime(2026, 11, 10)), 6);
    expect(d.overdueDaysAt(DateTime(2026, 11, 3)), 0);
  });
  test(
    'Closed contracts do not show an active overdue alert; unknown dates stay blank',
    () {
      expect(
        details(
          DateTime(2026, 10, 1),
          closed: true,
        ).overdueDaysAt(DateTime(2026, 11, 4)),
        0,
      );
      expect(details(null).overdueDaysAt(DateTime(2026, 11, 4)), isNull);
      expect(
        details(
          DateTime(2026, 10, 1),
          closed: null,
        ).overdueDaysAt(DateTime(2026, 11, 4)),
        isNull,
      );
    },
  );
}
