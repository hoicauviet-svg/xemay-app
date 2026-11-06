import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/core/theme/app_theme.dart';
import 'package:xemay_app/models/batches/batch_models.dart';
import 'package:xemay_app/models/goods_receipt/goods_receipt_models.dart';
import 'package:xemay_app/views/batches/batch_details_screen.dart';
import 'support/fake_batch_repository.dart';

class _Repository extends FakeBatchRepository {
  late ReceiptBatch current = batch;
  BatchPaymentPreview? saved;
  @override
  Future<ReceiptBatch?> findById(int id) async => current;
  @override
  Future<void> pay(
    BatchPaymentPreview payment, {
    required String requestId,
  }) async {
    saved = payment;
    current = ReceiptBatch(
      id: batch.id,
      date: batch.date,
      quantity: batch.quantity,
      total: batch.total,
      paid: batch.paid! + payment.amount,
      remaining: batch.remaining! - payment.amount,
      deliveredBy: batch.deliveredBy,
      origin: batch.origin,
    );
  }

  @override
  Future<List<BatchPayment>> payments(int batchId) async => [
    if (saved != null)
      BatchPayment(
        id: 100,
        batchId: batchId,
        date: saved!.date,
        amount: saved!.amount,
        remaining: current.remaining,
        notes: saved!.notes,
        documents: saved!.documents,
      ),
  ];
}

void main() {
  testWidgets(
    'Batch payment saves images/PDF and displays documents in history',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _Repository();
      final pdf = PaymentDocument(
        name: 'bien-lai.pdf',
        mimeType: 'application/pdf',
        bytes: Uint8List.fromList('%PDF-1.4\nchung tu'.codeUnits),
      );
      final image = PaymentDocument(
        name: 'anh.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0]),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: BatchDetailsScreen(
            batch: repo.batch,
            type: ReceiptProductType.newVehicle,
            repository: repo,
            pickDocuments: () async => [pdf, image],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'Thanh toán'));
      await tester.pumpAndSettle();
      expect(find.text('Tổng nợ: 1.500.000 đ'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('batch-payment-remaining')),
        findsOneWidget,
      );
      await tester.tap(find.text('Chọn ảnh hoặc PDF'));
      await tester.pumpAndSettle();
      expect(find.text('bien-lai.pdf'), findsOneWidget);
      expect(find.text('anh.png'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('batch-payment-amount')),
        '1500001',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Thanh toán'));
      await tester.pumpAndSettle();
      expect(repo.saved, isNull);
      expect(
        find.text('Số tiền thanh toán không được vượt tổng nợ.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('batch-payment-amount')),
        '500000',
      );
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('batch-payment-remaining')),
          matching: find.text('1.000.000 đ'),
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('batch-payment-notes')),
        'Thanh toán có chứng từ',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Thanh toán'));
      await tester.pumpAndSettle();
      expect(repo.saved!.amount, 500000);
      expect(repo.saved!.documents.length, 2);
      expect(find.text('Thanh toán thành công'), findsOneWidget);
      expect(find.text('1.000.000 đ'), findsOneWidget);
      await tester.tap(find.text('2 file'));
      await tester.pumpAndSettle();
      expect(find.text('bien-lai.pdf'), findsOneWidget);
      expect(find.text('anh.png'), findsOneWidget);
      expect(find.byTooltip('Lưu bản sao'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
}
