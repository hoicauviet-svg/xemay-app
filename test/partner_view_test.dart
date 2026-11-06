import 'support/fake_sales_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/app.dart';
import 'support/fake_partner_repository.dart';

void main() {
  testWidgets(
    'Seller lives under partners and purchase history is linked by partner ID',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakePartnerRepository();
      await tester.pumpWidget(
        StoreApp(
          salesRepositoryFactory: FakeSalesRepository.new,
          partnerRepositoryFactory: () => repository,
        ),
      );
      await tester.tap(find.text('Đối tác / nhà cung cấp').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Người bán kiểm thử'));
      await tester.pumpAndSettle();
      expect(find.text('Thông tin đối tác'), findsOneWidget);
      await tester.tap(find.widgetWithText(Tab, 'Đơn nhập hàng'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(Tab, 'Phiếu mua'), findsNothing);
      expect(find.text('Đối tác · Người bán kiểm thử'), findsOneWidget);
      expect(find.text('1 đơn nhập'), findsOneWidget);
      expect(repository.requestedPartner, 'seller-test');
      expect(find.text('#44'), findsOneWidget);
      expect(find.text('Xe mua từ đối tác'), findsOneWidget);
      expect(find.text('Mua hàng từ khách'), findsNothing);
    },
  );
}
