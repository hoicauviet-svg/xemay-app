import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/core/theme/app_theme.dart';
import 'package:xemay_app/models/goods_receipt/goods_receipt_models.dart';
import 'package:xemay_app/views/goods_receipt/goods_receipt_form_screen.dart';
import 'support/fake_directory_repository.dart';

void main() {
  testWidgets(
    'Partner and carrier autocomplete select existing IDs; + saves and selects new records',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeDirectoryRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('vi'),
          supportedLocales: const [Locale('vi')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: GoodsReceiptFormScreen(
            type: ReceiptProductType.newVehicle,
            initialMode: ReceiptMode.batch,
            directoryRepository: repository,
          ),
        ),
      );
      await tester.enterText(find.byKey(const ValueKey('batch-quantity')), '2');
      await tester.enterText(
        find.byKey(const ValueKey('batch-total')),
        '40000000',
      );
      await tester.enterText(
        find.byKey(const ValueKey('batch-origin')),
        '0900000001',
      );
      await tester.pumpAndSettle();
      expect(find.text('Nơi nhập thử'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('directory-option-partner-partner-test')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Thêm vận chuyển'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('directory-name')),
        'Vận chuyển mới',
      );
      await tester.enterText(
        find.byKey(const ValueKey('directory-phone')),
        '0900000003',
      );
      await tester.enterText(
        find.byKey(const ValueKey('directory-plate')),
        'TEST-02',
      );
      await tester.enterText(
        find.byKey(const ValueKey('directory-notes')),
        'Ghi chú vận chuyển',
      );
      await tester.tap(find.text('Lưu và chọn'));
      await tester.pumpAndSettle();
      expect(repository.saves, 1);
      expect(find.text('Vận chuyển mới'), findsOneWidget);
      await tester.tap(find.byTooltip('Thêm đối tác / nhà cung cấp'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('directory-name')),
        'Đối tác mới',
      );
      await tester.enterText(
        find.byKey(const ValueKey('directory-phone')),
        '0900000004',
      );
      await tester.enterText(
        find.byKey(const ValueKey('directory-address')),
        'Địa chỉ mới',
      );
      await tester.enterText(
        find.byKey(const ValueKey('directory-tax')),
        '0123456789',
      );
      await tester.enterText(
        find.byKey(const ValueKey('directory-representative')),
        'Đại diện thử',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('directory-notes')));
      await tester.enterText(
        find.byKey(const ValueKey('directory-notes')),
        'Ghi chú đối tác',
      );
      await tester.tap(find.text('Lưu và chọn'));
      await tester.pumpAndSettle();
      expect(repository.saves, 2);
      expect(repository.entries.last.taxCode, '0123456789');
      expect(repository.entries.last.representative, 'Đại diện thử');
      expect(repository.entries.last.notes, 'Ghi chú đối tác');
      await tester.tap(find.text('Tiếp tục'));
      await tester.pumpAndSettle();
      expect(find.text('Đối tác / nhà cung cấp: Đối tác mới'), findsOneWidget);
      expect(find.text('Vận chuyển: Vận chuyển mới'), findsOneWidget);
      expect(find.byKey(const ValueKey('line-name-2')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
