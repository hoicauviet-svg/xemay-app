import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/core/theme/app_theme.dart';
import 'package:xemay_app/models/pawn/pawn_models.dart';
import 'package:xemay_app/views/pawn/pawn_payment_form.dart';

void main() {
  testWidgets(
    'Settlement previews full remaining principal plus interest and requires confirmation',
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
          'NgayPhanTram': false,
          'LaiSuat': 3,
          'TrangThai': false,
        },
        payments: [
          {
            'NgayTra': today.subtract(const Duration(days: 5)),
            'TienGoc': 200000,
            'LaiThu': 0,
          },
        ],
      );
      PawnPaymentDraft? saved;
      int calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: PawnPaymentForm(
              details: details,
              onPay: (payment, _) async {
                saved = payment;
                calls++;
              },
            ),
          ),
        ),
      );
      final expectedInterest = details.interestAccrualAt(today)!.roundedAmount;
      await tester.tap(find.byKey(const ValueKey('pawn-settle')));
      await tester.pumpAndSettle();
      expect(
        find.text('Tất toán = Trả toàn bộ tiền gốc + tiền lãi'),
        findsOneWidget,
      );
      expect(find.text('Tiền gốc còn lại: 800.000 đ'), findsOneWidget);
      expect(find.text('Tiền lãi: 9.000 đ'), findsOneWidget);
      expect(find.text('Tổng tất toán: 809.000 đ'), findsOneWidget);
      expect(saved, isNull);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('pawn-payment-principal')),
            )
            .controller!
            .text,
        '0',
      );
      await tester.tap(find.byKey(const ValueKey('pawn-settle')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xác nhận tất toán'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(saved!.principal, 800000);
      expect(saved!.interest, expectedInterest);
      expect(saved!.collectedInterest, expectedInterest);
      expect(saved!.appointmentDate, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
