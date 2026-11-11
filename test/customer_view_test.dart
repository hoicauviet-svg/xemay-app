import 'support/fake_sales_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/app.dart';
import 'support/fake_customer_repository.dart';

void main() {
  testWidgets(
    'Customer tab searches, filters, creates with retry and confirms deletion',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeCustomerRepository();
      await tester.pumpWidget(
        StoreApp(
          salesRepositoryFactory: FakeSalesRepository.new,
          customerRepositoryFactory: () => repository,
        ),
      );
      await tester.tap(find.text('Khách hàng').first);
      await tester.pumpAndSettle();
      expect(find.text('Thôn 1, Xã kiểm thử'), findsOneWidget);
      await tester.tap(find.text('Khách kiểm thử'));
      await tester.pumpAndSettle();
      expect(find.text('Thông tin khách hàng'), findsOneWidget);
      expect(find.text('Khách kiểm thử'), findsOneWidget);
      expect(find.text('Sửa'), findsOneWidget);
      expect(find.text('Xóa'), findsOneWidget);
      expect(find.text('Gộp'), findsNothing);
      await tester.tap(find.widgetWithText(Tab, 'Đơn hàng'));
      await tester.pumpAndSettle();
      expect(find.text('#42'), findsOneWidget);
      expect(find.text('Xe kiểm thử (#7)'), findsOneWidget);
      expect(repository.lastOrderCustomer, 1);
      expect(find.text('Mua hàng từ khách'), findsNothing);
      await tester.tap(find.byTooltip('Quay lại'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Không có');
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.text('Không có khách hàng phù hợp.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      await tester.tap(find.byTooltip('Lọc khách hàng'));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<int>), findsNothing);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Có số điện thoại').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Áp dụng'));
      await tester.pumpAndSettle();
      expect(repository.phoneFilter, 'with_phone');
      await tester.tap(find.byTooltip('Thêm khách hàng mới'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('customer-locality')), findsNothing);
      await tester.tap(find.text('Lưu khách hàng'));
      await tester.pumpAndSettle();
      expect(find.text('Vui lòng nhập tên khách hàng'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('customer-name')),
        'Khách mới',
      );
      await tester.enterText(
        find.byKey(const ValueKey('customer-phone')),
        '0900000002',
      );
      await tester.enterText(
        find.byKey(const ValueKey('customer-address')),
        'Thôn 2, Xã mới',
      );
      repository.failSave = true;
      await tester.tap(find.text('Lưu khách hàng'));
      await tester.pumpAndSettle();
      expect(find.text('Không lưu được khách hàng'), findsOneWidget);
      repository.failSave = false;
      await tester.tap(find.text('Lưu khách hàng'));
      await tester.pumpAndSettle();
      expect(find.text('Khách mới'), findsOneWidget);
      expect(find.text('Thôn 2, Xã mới'), findsOneWidget);
      await tester.tap(find.byTooltip('Xóa khách hàng').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(repository.rows.length, 2);
      repository.referenced = true;
      await tester.tap(find.byTooltip('Xóa khách hàng').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xóa'));
      await tester.pumpAndSettle();
      expect(repository.rows.length, 2);
      expect(
        find.text('Không thể xóa khách hàng đã có giao dịch hoặc công nợ.'),
        findsOneWidget,
      );
      repository.referenced = false;
      await tester.tap(find.byTooltip('Xóa khách hàng').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xóa'));
      await tester.pumpAndSettle();
      expect(repository.rows.length, 1);
      expect(find.text('Khách mới'), findsNothing);
    },
  );
}
