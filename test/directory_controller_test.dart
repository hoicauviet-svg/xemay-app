import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/controllers/directory_controller.dart';
import 'package:xemay_app/models/directory/directory_models.dart';
import 'package:xemay_app/controllers/goods_receipt_controller.dart';
import 'package:xemay_app/models/goods_receipt/goods_receipt_models.dart';
import 'support/fake_directory_repository.dart';

void main() {
  test(
    'A single load completes and matches phone/plate without mixing directories',
    () async {
      final directory = DirectoryController(FakeDirectoryRepository());
      addTearDown(directory.dispose);
      await directory
          .ensureLoaded(DirectoryKind.partner)
          .timeout(const Duration(seconds: 2));
      await directory
          .ensureLoaded(DirectoryKind.carrier)
          .timeout(const Duration(seconds: 2));
      expect(
        directory.search(DirectoryKind.partner, '0900000001').single.id,
        'partner-test',
      );
      expect(
        directory.search(DirectoryKind.carrier, 'TEST-01').single.id,
        'carrier-test',
      );
      expect(directory.search(DirectoryKind.partner, 'TEST-01'), isEmpty);
    },
  );

  test(
    'Changing a selected label clears its ID and blocks batch confirmation',
    () {
      final controller = GoodsReceiptController(ReceiptProductType.newVehicle);
      addTearDown(controller.dispose);
      controller.setMode(ReceiptMode.batch);
      controller.updateBatch((d) {
        d.quantity = '1';
        d.totalAmount = '20000000';
      });
      controller.selectBatchPartner('partner-test', 'Đối tác');
      controller.selectBatchCarrier('carrier-test', 'Vận chuyển');
      expect(controller.confirmBatch(), isNull);
      expect(
        controller.batchInfo.toDatabaseFields()['IdDoiTac'],
        'partner-test',
      );
      expect(
        controller.batchInfo.toDatabaseFields()['IdVanChuyen'],
        'carrier-test',
      );
      controller.changeBatchPartner('Đối tác khác');
      expect(controller.batch.partnerId, isNull);
      expect(controller.isBatchConfirmed, isFalse);
      expect(controller.confirmBatch(), isNotNull);
    },
  );

  test('A failed create keeps the popup draft and allows retry', () async {
    final repo = FakeDirectoryRepository()..failSave = true;
    final directory = DirectoryController(repo);
    final editor = DirectoryEditController(
      directory,
      DirectoryKind.partner,
      'Tên mới',
    );
    addTearDown(directory.dispose);
    addTearDown(editor.dispose);
    editor.draft.phone = '0900000000';
    expect(await editor.save(), isNull);
    expect(editor.error, isNotNull);
    expect(editor.draft.name, 'Tên mới');
    repo.failSave = false;
    expect((await editor.save())?.phone, '0900000000');
    expect(repo.saves, 1);
  });
}
