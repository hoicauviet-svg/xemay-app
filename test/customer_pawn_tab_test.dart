import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/core/theme/app_theme.dart';
import 'package:xemay_app/models/pawn/pawn_models.dart';
import 'package:xemay_app/models/repositories/pawn_repository.dart';
import 'package:xemay_app/views/customers/customer_details_screen.dart';
import 'support/fake_customer_repository.dart';

class _Pawns extends PawnRepository {
  int? requestedCustomer;
  int calls = 0;
  @override
  Future<PawnPage> fetch({
    String search = '',
    int page = 0,
    int? customerId,
    String status = 'all',
  }) async {
    calls++;
    requestedCustomer = customerId;
    return PawnPage([
      {
        'IdCamDo': 100,
        'IdKhachHang': customerId,
        'TenKhachHang': 'Khách kiểm thử',
        'TaiSanTheChap': 'Tài sản của khách',
        'SoTienVay': 5000000,
        'NgayPhanTram': false,
        'LaiSuat': 3,
        'TrangThai': false,
      },
    ], 1);
  }

  @override
  Future<int> create(PawnDraft draft, {required String requestId}) async =>
      throw StateError('Read only');
  @override
  Future<PawnDetails> details(int id) async => PawnDetails(
    contract: (await fetch()).rows.firstWhere((r) => r['IdCamDo'] == id),
    payments: const [],
  );
  @override
  Future<void> pay(
    PawnPaymentDraft payment, {
    required String requestId,
  }) async => throw UnsupportedError('Payment not used in this test');
  @override
  Future<void> close() async {}
}

void main() {
  testWidgets(
    'Customer pawn tab loads only on selection with exact customer ID',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pawns = _Pawns();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: CustomerDetailsScreen(
            customerId: 1,
            repository: FakeCustomerRepository(),
            pawnRepositoryFactory: () => pawns,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(Tab, 'Cầm đồ'), findsOneWidget);
      expect(pawns.calls, 0);
      await tester.tap(find.widgetWithText(Tab, 'Cầm đồ'));
      await tester.pumpAndSettle();
      expect(pawns.requestedCustomer, 1);
      expect(find.text('Tài sản của khách'), findsOneWidget);
      expect(find.text('NGÀY THÁNG'), findsOneWidget);
      expect(find.text('NGÀY VAY'), findsNothing);
      expect(find.text('Ngày vay: '), findsOneWidget);
      expect(find.text('Ngày hạn: '), findsOneWidget);
      final table = tester.getRect(
        find.byKey(const ValueKey('fixed-table-heading')),
      );
      final status = tester.getRect(find.text('TRẠNG THÁI'));
      expect(status.right, lessThanOrEqualTo(table.right));
      expect(table.right, lessThanOrEqualTo(tester.view.physicalSize.width));
      expect(find.text('1 phiếu cầm đồ'), findsOneWidget);
      expect(find.byKey(const ValueKey('pawn-add')), findsNothing);
      await tester.tap(find.text('#100'));
      await tester.pumpAndSettle();
      expect(find.text('Cầm đồ #100'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
