import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/core/theme/app_theme.dart';
import 'package:xemay_app/models/orders/order_details.dart';
import 'package:xemay_app/models/repositories/order_repository.dart';
import 'package:xemay_app/views/customers/customer_details_screen.dart';
import 'package:xemay_app/views/orders/order_details_screen.dart';
import 'support/fake_customer_repository.dart';

class _Repository extends OrderRepository {
  num due = 100000, paid = 50000;
  int saves = 0;
  final history = <Map<String, dynamic>>[];
  @override
  Future<OrderDetails> load(int id) async => OrderDetails(
    header: {
      'IdHoaDon': id,
      'NgayMua': DateTime(2026, 11, 1),
      'TongThanhToan': 150000,
      'GiamGia': 10000,
    },
    customer: {'TenKhachHang': 'Khách đơn thử', 'SoDienThoai': '0900000001'},
    lines: [
      {
        'TenSanPham': 'Xe đơn thử',
        'IdXe': 7,
        'SoKhung': 'KHUNG-7',
        'SoMay': 'MAY-7',
        'SoLuong': 1,
        'DonGia': 160000,
      },
    ],
    debts: [
      {'SoTienDaTra': paid, 'SoTienConNo': due},
    ],
    payments: List.of(history),
  );
  @override
  Future<void> pay(
    int id, {
    required DateTime date,
    required int amount,
    required String notes,
    required String requestId,
    DateTime? nextAppointment,
  }) async {
    saves++;
    paid += amount;
    due -= amount;
    history.add({
      'IdTraNo': 9,
      'NgayTra': date,
      'SotienTra': amount,
      'SoCoNo': due,
      'LaiThu': 0,
      'GhiChu': notes,
    });
  }

  @override
  Future<void> close() async {}
}

void main() {
  testWidgets(
    'Customer order opens detail tabs and payment refreshes balance/history',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _Repository();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: CustomerDetailsScreen(
            customerId: 1,
            repository: FakeCustomerRepository(),
            orderRepositoryFactory: () => repo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'Đơn hàng'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('#42'));
      await tester.pumpAndSettle();
      expect(find.byType(OrderDetailsScreen), findsOneWidget);
      expect(find.text('Đơn hàng #42'), findsOneWidget);
      expect(find.text('Khách đơn thử'), findsOneWidget);
      await tester.tap(find.widgetWithText(Tab, 'Danh sách sản phẩm'));
      await tester.pumpAndSettle();
      expect(find.text('Xe đơn thử'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.widgetWithText(Tab, 'Thanh toán'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('order-payment-amount')),
        '100001',
      );
      await tester.tap(find.text('Lưu thanh toán'));
      await tester.pumpAndSettle();
      expect(repo.saves, 0);
      await tester.enterText(
        find.byKey(const ValueKey('order-payment-amount')),
        '40000',
      );
      await tester.enterText(
        find.byKey(const ValueKey('order-payment-notes')),
        'Thu tiền thử',
      );
      await tester.tap(find.text('Lưu thanh toán'));
      await tester.pumpAndSettle();
      expect(repo.saves, 1);
      expect(repo.due, 60000);
      expect(find.text('Thanh toán thành công'), findsOneWidget);
      expect(find.text('Thu tiền thử'), findsOneWidget);
      expect(find.text('60.000 đ'), findsOneWidget);
      await tester.tap(find.widgetWithText(Tab, 'Thông tin'));
      await tester.pumpAndSettle();
      expect(find.text('90.000 đ'), findsOneWidget);
      await tester.tap(find.byTooltip('Quay lại'));
      await tester.pumpAndSettle();
      expect(find.byType(OrderDetailsScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Order detail and payment adapt to narrow windows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: OrderDetailsScreen(orderId: 42, repository: _Repository()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(Tab, 'Thanh toán'));
    await tester.tap(find.widgetWithText(Tab, 'Thanh toán'));
    await tester.pumpAndSettle();
    expect(find.text('Lưu thanh toán'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
