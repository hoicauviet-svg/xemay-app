import 'package:flutter/material.dart';
import 'package:xemay_app/views/orders/order_payment_form.dart';
import 'package:xemay_app/core/formatters/money_input_formatter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/models/orders/order_details.dart';

OrderDetails order({
  DateTime? start,
  num due = 1000000,
  List<Map<String, dynamic>> payments = const [],
}) => OrderDetails(
  header: {'NgayTinhLai': start},
  customer: null,
  lines: const [],
  debts: [
    {'SoTienDaTra': 0, 'SoTienConNo': due},
  ],
  payments: payments,
);

OrderDetails appointmentOrder({DateTime? start}) => OrderDetails(
  header: {'NgayHen': start},
  customer: null,
  lines: const [],
  debts: const [],
  payments: const [],
);

void main() {
  testWidgets(
    'payment date fills editable interest and a changed amount is saved',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.now();
      final start = OrderDetails.day(now).subtract(const Duration(days: 30));
      int? saved;
      int? savedInterest;
      DateTime? savedAppointment;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrderPaymentForm(
              order: order(start: start),
              onSave:
                  (date, amount, interest, notes, token, appointment) async {
                    saved = amount;
                    savedInterest = interest;
                    savedAppointment = appointment;
                  },
            ),
          ),
        ),
      );
      final field = find.byKey(const ValueKey('order-payment-interest'));
      expect(
        tester.widget<TextFormField>(field).controller!.text,
        groupMoney('20000'),
      );
      await tester.tap(find.byIcon(Icons.calendar_today_outlined));
      await tester.pumpAndSettle();
      final target = now.day == 1 ? 2 : now.day - 1;
      await tester.tap(find.text('$target').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      final expected = order(
        start: start,
      ).interestAt(DateTime(now.year, now.month, target));
      expect(
        tester.widget<TextFormField>(field).controller!.text,
        groupMoney('$expected'),
      );
      await tester.enterText(field, '12345');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.event_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lưu thanh toán'));
      await tester.pumpAndSettle();
      expect(saved, 0);
      expect(savedInterest, 12345);
      expect(
        OrderDetails.day(savedAppointment!),
        OrderDetails.day(DateTime(now.year, now.month, target)),
      );
    },
  );

  test(
    'order 151970: 30 October to 4 November is five days on recorded debt',
    () {
      final data = OrderDetails(
        header: {
          'NgayTinhLai': DateTime.utc(2026, 10, 30),
          'NgayHen': DateTime.utc(2026, 11, 5),
        },
        customer: null,
        lines: const [],
        debts: [
          {'SoTienDaTra': 9864000.0, 'SoTienConNo': 28650000.0},
        ],
        payments: [
          {
            'NgayTra': DateTime.utc(2026, 10, 30),
            'SotienTra': 9864000.0,
            'LaiThu': 0,
          },
        ],
      );
      expect(data.interestAt(DateTime(2026, 11, 4)), 95500);
      expect(data.interestAt(DateTime(2026, 11, 5)), 114600);
    },
  );

  test(
    'next appointment keeps future/today, renews past and clamps month end',
    () {
      expect(
        appointmentOrder(
          start: DateTime(2026, 11, 5),
        ).nextAppointmentAt(DateTime(2026, 11, 4)),
        DateTime.utc(2026, 11, 5),
      );
      expect(
        appointmentOrder(
          start: DateTime(2026, 11, 4),
        ).nextAppointmentAt(DateTime(2026, 11, 4)),
        DateTime.utc(2026, 11, 4),
      );
      expect(
        appointmentOrder(
          start: DateTime(2026, 10, 30),
        ).nextAppointmentAt(DateTime(2026, 11, 4)),
        DateTime.utc(2026, 12, 4),
      );
      expect(
        appointmentOrder(
          start: DateTime(2026, 1, 1),
        ).nextAppointmentAt(DateTime(2026, 1, 31)),
        DateTime.utc(2026, 2, 28),
      );
      expect(
        appointmentOrder().nextAppointmentAt(DateTime(2026, 11, 4)),
        isNull,
      );
    },
  );

  test('2% per 30 days, calendar dates, rounded to dong', () {
    final data = order(start: DateTime(2026, 1, 1));
    expect(data.interestAt(DateTime(2026, 1, 31)), 20000);
    expect(data.interestAt(DateTime(2026, 1, 2)), 667);
    expect(data.interestAt(DateTime(2025, 12, 31)), 0);
    expect(order().interestAt(DateTime(2026, 1, 31)), 0);
  });
  test(
    'principal-only repayment splits interest, actual interest resets anchor',
    () {
      final data = order(
        start: DateTime(2026, 1, 1),
        due: 500000,
        payments: [
          {
            'NgayTra': DateTime.utc(2026, 1, 16),
            'SotienTra': 500000,
            'SoTienLai': 10000,
            'LaiThu': 0,
          },
        ],
      );
      expect(data.interestAt(DateTime(2026, 1, 31)), 15000);
      final renewed = order(
        start: DateTime(2026, 1, 1),
        due: 500000,
        payments: [
          {
            'NgayTra': DateTime.utc(2026, 1, 16),
            'SotienTra': 500000,
            'LaiThu': 10000,
          },
        ],
      );
      expect(renewed.interestAt(DateTime(2026, 1, 31)), 5000);
    },
  );
}
