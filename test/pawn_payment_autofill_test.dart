import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:xemay_app/core/theme/app_theme.dart';
import 'package:xemay_app/models/pawn/pawn_models.dart';
import 'package:xemay_app/views/pawn/pawn_payment_form.dart';

void main() {
  testWidgets(
    'Overdue appointment defaults to next month and saves without manual selection',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.now();
      final today = DateTime.utc(now.year, now.month, now.day);
      final details = PawnDetails(
        contract: {
          'IdCamDo': 42,
          'NgayVay': today.subtract(const Duration(days: 10)),
          'NgayHan': today.subtract(const Duration(days: 1)),
          'SoTienVay': 1000000,
          'LaiSuat': 3,
          'NgayPhanTram': false,
          'TrangThai': false,
        },
        payments: const [],
      );
      PawnPaymentDraft? saved;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: PawnPaymentForm(
              details: details,
              onPay: (payment, _) async {
                saved = payment;
              },
            ),
          ),
        ),
      );
      final expected = details.defaultAppointmentAt(today)!;
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('pawn-payment-appointment')),
          matching: find.text(DateFormat('dd/MM/yyyy').format(expected)),
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('pawn-payment-collected')),
        '1000',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Thanh toán'));
      await tester.pumpAndSettle();
      expect(saved!.appointmentDate, expected);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Interest autofills and recalculates for a changed repayment date',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.now();
      final today = DateTime.utc(now.year, now.month, now.day);
      final details = PawnDetails(
        contract: {
          'IdCamDo': 42,
          'NgayVay': today.subtract(const Duration(days: 10)),
          'SoTienVay': 1000000,
          'LaiSuat': 3,
          'NgayPhanTram': false,
          'TrangThai': false,
        },
        payments: const [],
      );
      PawnPaymentDraft? saved;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: PawnPaymentForm(
              details: details,
              onPay: (payment, _) async {
                saved = payment;
              },
            ),
          ),
        ),
      );
      String interest() => tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('pawn-payment-interest')),
          )
          .controller!
          .text;
      expect(interest(), '10.000');
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('pawn-payment-collected')),
            )
            .controller!
            .text,
        '0',
      );
      await tester.tap(find.byKey(const ValueKey('pawn-payment-date')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Switch to input'));
      await tester.pumpAndSettle();
      final date = today.add(const Duration(days: 5));
      await tester.enterText(
        find.byType(InputDatePickerFormField),
        DateFormat('MM/dd/yyyy').format(date),
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(interest(), '15.000');
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('pawn-payment-interest')),
                matching: find.byType(TextField),
              ),
            )
            .readOnly,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('pawn-payment-appointment')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Switch to input'));
      await tester.pumpAndSettle();
      final next = today.add(const Duration(days: 10));
      await tester.enterText(
        find.byType(InputDatePickerFormField),
        DateFormat('MM/dd/yyyy').format(next),
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('pawn-payment-collected')),
        '15000',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Thanh toán'));
      await tester.pumpAndSettle();
      expect(saved!.appointmentDate, DateTime(next.year, next.month, next.day));
      expect(saved!.interest, 15000);

      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Autofilled interest rounds to whole dong and handles new paid-interest anchor',
    (tester) async {
      final now = DateTime.now();
      final today = DateTime.utc(now.year, now.month, now.day);
      final contract = {
        'IdCamDo': 42,
        'NgayVay': today.subtract(const Duration(days: 10)),
        'SoTienVay': 1000000,
        'LaiSuat': 2.5,
        'NgayPhanTram': false,
        'TrangThai': false,
      };
      final details = PawnDetails(
        contract: contract,
        payments: [
          {
            'NgayTra': today.subtract(const Duration(days: 1)),
            'TienGoc': 0,
            'LaiThu': 1000,
          },
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: PawnPaymentForm(details: details, onPay: (_, _) async {}),
          ),
        ),
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('pawn-payment-interest')),
            )
            .controller!
            .text,
        '833',
      );
      final updated = PawnDetails(
        contract: contract,
        payments: [
          {'NgayTra': today, 'TienGoc': 0, 'LaiThu': 1000},
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: PawnPaymentForm(details: updated, onPay: (_, _) async {}),
          ),
        ),
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('pawn-payment-interest')),
            )
            .controller!
            .text,
        '0',
      );
    },
  );
}
