import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/core/theme/app_theme.dart';
import 'package:xemay_app/models/batches/batch_models.dart';
import 'package:xemay_app/models/goods_receipt/goods_receipt_models.dart';
import 'package:xemay_app/views/batches/batch_details_screen.dart';
import 'package:xemay_app/views/directory/partner_details_screen.dart';
import 'support/fake_batch_repository.dart';
import 'support/fake_partner_repository.dart';

class _Batches extends FakeBatchRepository {
  ReceiptProductType? requestedType;
  bool closed = false;
  @override
  Future<ReceiptBatch?> findById(int id) async => id == 44
      ? ReceiptBatch(
          id: id,
          date: batch.date,
          quantity: batch.quantity,
          total: batch.total,
          paid: batch.paid,
          remaining: batch.remaining,
          deliveredBy: batch.deliveredBy,
          origin: batch.origin,
        )
      : null;
  @override
  Future<List<BatchProduct>> products(
    ReceiptBatch batch,
    ReceiptProductType type,
  ) async {
    requestedType = type;
    return super.products(batch, type);
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  for (final width in [1400.0, 420.0]) {
    testWidgets('Partner incoming order opens its batch at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final batches = _Batches();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PartnerDetailsScreen(
            partnerId: 'seller-test',
            repository: FakePartnerRepository(),
            batchRepositoryFactory: () => batches,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'Đơn nhập hàng'));
      await tester.pumpAndSettle();
      await tester.tap(width < 700 ? find.byType(ListTile) : find.text('#44'));
      await tester.pumpAndSettle();
      expect(find.byType(BatchDetailsScreen), findsOneWidget);
      expect(find.text('Lô hàng #44'), findsOneWidget);
      expect(batches.requestedType, ReceiptProductType.usedVehicle);
      await tester.tap(find.widgetWithText(Tab, 'Danh sách sản phẩm'));
      await tester.pumpAndSettle();
      expect(find.text('Xe trong lô thử'), findsOneWidget);
      await tester.tap(find.byTooltip('Quay lại'));
      await tester.pumpAndSettle();
      expect(find.byType(BatchDetailsScreen), findsNothing);
      expect(batches.closed, isTrue);
      expect(find.text('1 đơn nhập'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
