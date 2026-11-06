import 'package:xemay_app/models/repositories/receipt_repository.dart';
import 'support/fake_sales_repository.dart';
import 'support/fake_inventory_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/app.dart';
import 'package:xemay_app/core/theme/app_theme.dart';
import 'package:xemay_app/models/goods_receipt/goods_receipt_models.dart';
import 'package:xemay_app/views/goods_receipt/goods_receipt_screen.dart';
import 'package:xemay_app/views/goods_receipt/goods_receipt_form_screen.dart';
import 'support/fake_batch_repository.dart';
import 'support/fake_directory_repository.dart';

class _ReceiptRepository implements ReceiptRepository {
  ReceiptPreview? saved;
  @override
  Future<void> save(ReceiptPreview receipt, String requestId) async {
    saved = receipt;
  }

  @override
  Future<void> close() async {}
}

void main() {
  testWidgets(
    'Single receipt payment follows total until a manual amount is entered',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: GoodsReceiptFormScreen(
            type: ReceiptProductType.part,
            directoryRepository: FakeDirectoryRepository(),
            receiptRepository: _ReceiptRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('line-price-1')),
        '100000',
      );
      await tester.enterText(
        find.byKey(const ValueKey('line-quantity-1')),
        '3',
      );
      await tester.pumpAndSettle();
      String paid() => tester
          .widget<TextFormField>(find.byKey(const ValueKey('receipt-paid')))
          .controller!
          .text;
      expect(paid(), '300.000');
      await tester.enterText(
        find.byKey(const ValueKey('receipt-paid')),
        '20000',
      );
      await tester.enterText(
        find.byKey(const ValueKey('line-price-1')),
        '200000',
      );
      await tester.pumpAndSettle();
      expect(paid(), '20.000');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Save returns success and shows import toast with product costs',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _ReceiptRepository();
      bool refreshed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Mở nhập'),
                onPressed: () async {
                  final saved = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GoodsReceiptFormScreen(
                        type: ReceiptProductType.newVehicle,
                        directoryRepository: FakeDirectoryRepository(),
                        receiptRepository: repository,
                      ),
                    ),
                  );
                  refreshed = saved == true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Mở nhập'));
      await tester.pumpAndSettle();
      expect(find.text('Xe 1'), findsNothing);
      expect(find.text('Số chứng từ'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('receipt-carrier')),
        'Người giao thử',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('directory-option-carrier-carrier-test')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('line-name-1')),
        'Xe thử',
      );
      await tester.enterText(
        find.byKey(const ValueKey('line-price-1')),
        '10000000',
      );

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('receipt-paid')),
        250,
        scrollable: find
            .descendant(
              of: find.byType(GoodsReceiptFormScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.enterText(
        find.byKey(const ValueKey('receipt-paid')),
        '3000000',
      );
      await tester.pumpAndSettle();
      expect(find.text('7.000.000 đ'), findsOneWidget);
      expect(find.text('3.000.000'), findsOneWidget);
      expect(find.text('Thêm chi phí'), findsNothing);
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();
      expect(repository.saved!.lines.single.totalCosts, 0);
      expect(repository.saved!.carrierId, 'carrier-test');
      expect(repository.saved!.paidAmount, 3000000);
      expect(repository.saved!.remainingAmount, 7000000);
      expect(refreshed, isTrue);
      expect(find.text('Nhập thành công'), findsOneWidget);
      expect(find.byType(GoodsReceiptFormScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Product plus opens entry view with both modes and returns', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      StoreApp(
        directoryRepositoryFactory: FakeDirectoryRepository.new,
        salesRepositoryFactory: FakeSalesRepository.new,
        inventoryRepositoryFactory: FakeInventoryRepository.new,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sản phẩm').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('product-add-newVehicles')));
    await tester.pumpAndSettle();
    expect(find.byType(GoodsReceiptScreen), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Nhập lẻ'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Lô hàng'), findsOneWidget);
    expect(find.text('Nhập lô'), findsNothing);
    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pumpAndSettle();
    expect(find.byType(GoodsReceiptScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Lots open linked products; the create button opens the two-step form',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeBatchRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('vi'),
          supportedLocales: const [Locale('vi')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: GoodsReceiptScreen(
            type: ReceiptProductType.newVehicle,
            batchRepository: repository,
            directoryRepository: FakeDirectoryRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.fetchCalls, 0);
      await tester.enterText(
        find.byKey(const ValueKey('receipt-partner')),
        'Giữ bản nháp',
      );
      await tester.tap(find.widgetWithText(Tab, 'Lô hàng'));
      await tester.pumpAndSettle();
      expect(find.text('#42'), findsOneWidget);
      await tester.tap(find.text('#42'));
      await tester.pumpAndSettle();
      expect(find.text('Lô hàng #42'), findsOneWidget);
      expect(find.text('Số lượng khai báo'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      await tester.tap(find.widgetWithText(Tab, 'Danh sách sản phẩm'));
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('Xe trong lô thử'), findsOneWidget);
      expect(find.text('KHUNG-LO-42'), findsOneWidget);
      expect(find.byTooltip('Làm mới'), findsNothing);
      await tester.tap(find.byTooltip('Thêm sản phẩm vào lô'));
      await tester.pumpAndSettle();
      expect(find.text('Thêm sản phẩm vào lô #42'), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byKey(const ValueKey('receipt-partner')), findsNothing);
      expect(find.byKey(const ValueKey('batch-quantity')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('line-name-1')),
        'Xe thêm vào lô',
      );
      await tester.enterText(
        find.byKey(const ValueKey('line-price-1')),
        '20000000',
      );
      await tester.enterText(
        find.byKey(const ValueKey('line-sale-price-1')),
        '25000000',
      );
      expect(find.text('Hãng xe'), findsNothing);
      expect(find.text('Tiền đăng ký'), findsNothing);
      expect(find.text('Lưu'), findsOneWidget);
      await tester.tap(find.text('Xem phiếu nhập'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Thêm sản phẩm vào lô #42'),
        ),
        findsOneWidget,
      );

      expect(find.text('Giá bán: 25.000.000 đ'), findsOneWidget);

      await tester.tap(find.text('Tiếp tục chỉnh sửa'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Đóng'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Tab, 'Danh sách sản phẩm'), findsOneWidget);
      await tester.tap(find.widgetWithText(Tab, 'Thông tin'));
      await tester.pumpAndSettle();
      expect(find.text('Số lượng khai báo'), findsOneWidget);
      await tester.tap(find.widgetWithText(Tab, 'Lịch sử thanh toán'));
      await tester.pumpAndSettle();
      expect(find.text('Thanh toán thử'), findsOneWidget);
      expect(find.text('#9'), findsOneWidget);
      await tester.tap(find.widgetWithText(Tab, 'Thanh toán'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('batch-payment-amount')),
        '500000',
      );
      await tester.tap(find.text('Xem phiếu thanh toán'));
      await tester.pumpAndSettle();
      expect(find.text('Xem trước thanh toán'), findsOneWidget);
      expect(find.text('Số tiền: 500.000 đ'), findsOneWidget);
      await tester.tap(find.text('Tiếp tục chỉnh sửa'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Quay lại'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nhập lô hàng'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byTooltip('Đóng'), findsOneWidget);
      expect(find.text('Thông tin lô nhập'), findsOneWidget);
      expect(find.byKey(const ValueKey('line-name-2')), findsNothing);
      await tester.tap(find.text('Tiếp tục'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('line-name-2')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('batch-quantity')), '2');
      await tester.enterText(
        find.byKey(const ValueKey('batch-total')),
        '40000000',
      );
      await tester.enterText(
        find.byKey(const ValueKey('batch-delivered-by')),
        'Người giao thử',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('directory-option-carrier-carrier-test')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('batch-origin')),
        'Nơi nhập thử',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('directory-option-partner-partner-test')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('batch-paid')),
        '10000000',
      );
      await tester.tap(find.text('Tiếp tục'));
      await tester.pumpAndSettle();
      expect(find.text('Còn nợ: 30.000.000 đ'), findsOneWidget);
      expect(find.byKey(const ValueKey('line-name-2')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Thêm xe'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(GoodsReceiptFormScreen).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Thêm xe'));
      await tester.pumpAndSettle();
      expect(find.text('Xe 2'), findsNothing);
      expect(find.byKey(const ValueKey('receipt-line-3')), findsOneWidget);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(find.text('#42'), findsOneWidget);
      await tester.tap(find.widgetWithText(Tab, 'Nhập lẻ'));
      await tester.pumpAndSettle();
      expect(find.text('Giữ bản nháp'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Part entry calculates and previews the entered quantity and price',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('vi'),
          supportedLocales: const [Locale('vi')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const GoodsReceiptFormScreen(type: ReceiptProductType.part),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('line-name-1')),
        'Nhớt máy',
      );
      await tester.enterText(
        find.byKey(const ValueKey('line-quantity-1')),
        '3',
      );
      await tester.enterText(
        find.byKey(const ValueKey('line-price-1')),
        '125000',
      );
      await tester.pumpAndSettle();
      expect(find.text('Tổng tiền: 375.000 đ'), findsOneWidget);
      await tester.tap(find.text('Xem phiếu nhập'));
      await tester.pumpAndSettle();
      expect(find.text('Xem trước phiếu nhập'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Nhớt máy'),
        ),
        findsOneWidget,
      );
      expect(find.text('3 × 125.000 đ = 375.000 đ'), findsOneWidget);
      await tester.tap(find.text('Tiếp tục chỉnh sửa'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('line-name-1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Entry form adapts to a narrow window', (tester) async {
    tester.view.physicalSize = const Size(420, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: GoodsReceiptScreen(
          type: ReceiptProductType.usedVehicle,
          batchRepository: FakeBatchRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Đối tác / nhà cung cấp'), findsOneWidget);
    await tester.tap(find.text('Lô hàng'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('Used vehicle entry has its own plate and notes fields', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: GoodsReceiptFormScreen(
          type: ReceiptProductType.usedVehicle,
          directoryRepository: FakeDirectoryRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('line-brand-1')), findsNothing);
    expect(find.byKey(const ValueKey('line-sale-price-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('line-vehicle-notes-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('line-frame-1')), findsNothing);
    expect(find.byKey(const ValueKey('line-registration-fee-1')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('line-name-1')),
      'Xe cũ thử',
    );
    await tester.enterText(
      find.byKey(const ValueKey('line-price-1')),
      '1000000',
    );
    await tester.enterText(
      find.byKey(const ValueKey('line-plate-1')),
      '21A-001',
    );
    await tester.enterText(
      find.byKey(const ValueKey('line-vehicle-notes-1')),
      'Đã qua sử dụng',
    );
    await tester.tap(find.text('Xem phiếu nhập'));
    await tester.pumpAndSettle();
    expect(find.text('Ghi chú xe: Đã qua sử dụng'), findsOneWidget);
    expect(find.text('Biển số: 21A-001'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
