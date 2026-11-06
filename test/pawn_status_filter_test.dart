import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/core/theme/app_theme.dart';
import 'package:xemay_app/models/pawn/pawn_models.dart';
import 'package:xemay_app/models/repositories/pawn_repository.dart';
import 'package:xemay_app/views/pawn/pawn_tab.dart';
import 'support/fake_customer_repository.dart';

class _Pawns extends PawnRepository {
  String? lastStatus;
  int? customer;
  @override
  Future<PawnPage> fetch({
    String search = '',
    int page = 0,
    int? customerId,
    String status = 'all',
  }) async {
    lastStatus = status;
    customer = customerId;
    final rows =
        [
              {
                'IdCamDo': 1,
                'TaiSanTheChap': 'Tài sản đang cầm',
                'TrangThai': false,
              },
              {
                'IdCamDo': 2,
                'TaiSanTheChap': 'Tài sản đã chuộc',
                'TrangThai': true,
              },
            ]
            .where(
              (r) => status == 'all' || r['TrangThai'] == (status == 'closed'),
            )
            .toList();
    return PawnPage(rows, rows.length);
  }

  @override
  Future<int> create(PawnDraft draft, {required String requestId}) async => 1;
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
    'Pawn status defaults active and filter preserves customer scope',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _Pawns();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: PawnTab(
              repository: repo,
              customers: FakeCustomerRepository(),
              customerId: 7,
              readOnly: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.lastStatus, 'active');
      expect(repo.customer, 7);
      expect(find.text('Tài sản đang cầm'), findsOneWidget);
      expect(find.text('Tài sản đã chuộc'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('pawn-status-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tất cả'));
      await tester.pumpAndSettle();
      expect(repo.lastStatus, 'all');
      expect(repo.customer, 7);
      expect(find.text('2 phiếu cầm đồ'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pawn-status-filter')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is CheckedPopupMenuItem<String> && w.value == 'closed',
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.lastStatus, 'closed');
      expect(find.text('Tài sản đang cầm'), findsNothing);
      expect(find.text('Tài sản đã chuộc'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
