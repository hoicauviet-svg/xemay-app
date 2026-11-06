import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/controllers/batch_details_controller.dart';
import 'package:xemay_app/models/goods_receipt/goods_receipt_models.dart';
import 'support/fake_batch_repository.dart';

void main() {
  test(
    'Loads the batch and its product/payment history using the same batch ID',
    () async {
      final repo = FakeBatchRepository();
      final controller = BatchDetailsController(
        repo,
        repo.batch,
        ReceiptProductType.newVehicle,
      );
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.error, isNull);
      expect(controller.products.single.batchId, 42);
      expect(controller.payments.single.batchId, 42);
      expect(controller.payments.single.amount, 500000);
      controller.setPaymentAmount('0');
      expect(controller.validatePayment(), contains('lớn hơn 0'));
      controller.setPaymentAmount('2000000');
      expect(controller.validatePayment(), contains('không được vượt'));
      controller.setPaymentAmount('500000');
      controller.setPaymentNotes('  Trả một phần  ');
      final preview = controller.previewPayment();
      expect(preview.batchId, 42);
      expect(preview.amount, 500000);
      expect(preview.notes, 'Trả một phần');
      expect(controller.batch.remaining, 1500000);
      expect(controller.payments.length, 1);
    },
  );

  test('A failed refresh blocks payment preview', () async {
    final repo = FakeBatchRepository();
    final controller = BatchDetailsController(
      repo,
      repo.batch,
      ReceiptProductType.newVehicle,
    );
    addTearDown(controller.dispose);
    await controller.load();
    controller.setPaymentAmount('100000');
    repo.fail = true;
    await controller.load();
    expect(controller.error, isNotNull);
    expect(() => controller.previewPayment(), throwsStateError);
  });
}
