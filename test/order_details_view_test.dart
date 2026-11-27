import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/core/theme/app_theme.dart';
import 'package:xemay_app/models/maintenance/record_maintenance.dart';
import 'package:xemay_app/models/orders/order_details.dart';
import 'package:xemay_app/models/repositories/order_repository.dart';
import 'package:xemay_app/views/customers/customer_details_screen.dart';
import 'package:xemay_app/views/orders/order_details_screen.dart';
import 'support/fake_customer_repository.dart';

class _Repository extends OrderRepository {
  num due = 100000, paid = 50000;
  String? orderStatus, orderReason;
  int saves = 0;
  final history = <Map<String, dynamic>>[];
  @override
  Future<OrderDetails> load(int id) async => OrderDetails(
    header: {
      'IdHoaDon': id,
      'NgayMua': DateTime(2026, 11, 1),
      'TongThanhToan': 150000,
      'GiamGia': 10000,
      if (orderStatus != null) 'TrangThaiDon': orderStatus,
      if (orderReason != null) 'LyDoHuy': orderReason,
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
    int? interest,
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

class _CancelMaintenance extends RecordMaintenance {
  int deleted = 0;
  String? reason;
  @override
  Future<List<Map<String, dynamic>>> pending() async => [];
  @override
  Future<void> ensureReadable(RecordKind kind, int id) async {}
  @override
  Future<List<Map<String, dynamic>>> suggestions(
    String collection,
    String search,
  ) async => [];
  @override
  Future<void> recover(RecordKind kind, int id) async {}
  @override
  Future<RecordEditData> load(RecordKind kind, int id) async =>
      throw UnimplementedError();
  @override
  Future<void> save(
    RecordKind kind,
    int id,
    Map<String, dynamic> fields,
    List<Map<String, dynamic>> lines, {
    required String requestId,
  }) async {}
  @override
  Future<void> delete(
    RecordKind kind,
    int id, {
    required String requestId,
    String? reason,
  }) async {
    deleted++;
    this.reason = reason;
  }

  @override
  Future<void> payment(
    RecordKind kind,
    int parentId,
    dynamic paymentId,
    Map<String, dynamic>? fields, {
    required String requestId,
    DateTime? interestStart,
    DateTime? nextAppointment,
  }) async {}
}

class _CancelRepository extends _Repository {
  final audit = _CancelMaintenance();
  @override
  RecordMaintenance get maintenance => audit;
}

void main() {
  test('saved order invoice follows the remaining debt', () {
    final data = OrderDetails(
      header: {
        'IdKH': 1,
        'NgayMua': DateTime(2026, 11, 1),
        'TongThanhToan': 150000,
        'GiamGia': 10000,
        'GhiChu': 'Giao xe',
        'NgayHen': DateTime(2026, 12, 1),
      },
      customer: {'TenKhachHang': 'Khách đơn thử', 'SoDienThoai': '0900000001'},
      lines: const [
        {
          'TenSanPham': 'Xe đơn thử',
          'IdXe': 7,
          'IdSanPham': 1,
          'SoKhung': 'KHUNG-7',
          'SoLuong': 1,
          'DonGia': 160000,
        },
      ],
      debts: const [
        {'SoTienDaTra': 90000, 'SoTienConNo': 60000},
      ],
      payments: const [],
    ).toInvoice(42);
    expect(data.invoiceId, 42);
    expect(data.customerName, 'Khách đơn thử');
    expect(data.draft.total, 150000);
    expect(data.draft.collected, 90000);
    expect(data.draft.due, 60000);
    expect(data.draft.lines.single.name, 'Xe đơn thử');
    expect(data.vehicles[7]?['SoKhung'], 'KHUNG-7');
    expect(data.draft.notes, 'Giao xe');
  });
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
      expect(find.text('In hóa đơn'), findsOneWidget);
      expect(find.text('In hợp đồng'), findsOneWidget);
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
      await tester.pump();
      expect(find.text('90.000 đ'), findsOneWidget);
      expect(find.text('60.000 đ'), findsOneWidget);
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
  testWidgets('A cancelled order keeps its record and blocks further actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = _CancelRepository()
      ..orderStatus = 'da_huy'
      ..orderReason = 'Khách đổi ý';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: OrderDetailsScreen(orderId: 42, repository: repo),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Đã hủy'), findsOneWidget);
    expect(
      find.textContaining('Lịch sử thanh toán đã được xóa'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('order-cancel')), findsNothing);
    await tester.tap(find.widgetWithText(Tab, 'Thanh toán'));
    await tester.pumpAndSettle();
    expect(find.text('Đơn hàng đã hủy, không thể thanh toán.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Cancelling an order requires a detailed warning and explicit confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _CancelRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Mở đơn'),
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        OrderDetailsScreen(orderId: 42, repository: repo),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Mở đơn'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('order-cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Hủy đơn hàng #42'), findsOneWidget);
      expect(find.text('Đơn hàng đã hủy không thể hoàn tác.'), findsOneWidget);
      expect(
        find.text('Khách hàng không bị xóa khỏi danh sách.'),
        findsOneWidget,
      );
      expect(
        find.text('Toàn bộ 0 phiếu/lịch sử thanh toán của đơn sẽ bị xóa.'),
        findsOneWidget,
      );
      expect(
        find.text('1 dòng sản phẩm sẽ được hoàn lại tồn kho (nếu có).'),
        findsOneWidget,
      );
      final confirm = find.byKey(const ValueKey('order-cancel-confirm'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('order-cancel-ack')));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('order-cancel-reason')),
        'Khách đổi ý',
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(repo.audit.deleted, 1);
      expect(repo.audit.reason, 'Khách đổi ý');
      expect(find.text('Mở đơn'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
