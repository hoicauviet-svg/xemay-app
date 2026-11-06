import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/app.dart';
import 'package:xemay_app/core/theme/app_theme.dart';
import 'package:xemay_app/models/pawn/pawn_models.dart';
import 'package:xemay_app/models/repositories/pawn_repository.dart';
import 'package:xemay_app/views/pawn/pawn_editor_popup.dart';
import 'package:xemay_app/views/pawn/pawn_tab.dart';
import 'support/fake_customer_repository.dart';
import 'support/fake_sales_repository.dart';

class _Repository extends PawnRepository {
  Map<String, dynamic>? saved;
  @override
  Future<PawnPage> fetch({
    String search = '',
    int page = 0,
    int? customerId,
    String status = 'all',
  }) async => PawnPage(
    saved == null
        ? []
        : [
            {
              'IdCamDo': 100,
              ...saved!,
              'TenKhachHang': 'Khách kiểm thử',
              'SoDienThoai': '0900000001',
            },
          ],
    saved == null ? 0 : 1,
  );
  @override
  Future<int> create(PawnDraft draft, {required String requestId}) async {
    saved = draft.toFields();
    return 100;
  }

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
    'Pawn form stores only source fields and monthly percentage flags',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _Repository();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: PawnTab(
              repository: repo,
              customers: FakeCustomerRepository(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pawn-add')));
      await tester.pumpAndSettle();
      expect(find.text('Mã cầm đồ'), findsNothing);
      expect(
        find.text('Tìm tên, số điện thoại hoặc mã khách hàng'),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('pawn-customer-add')), findsOneWidget);
      expect(find.byKey(const ValueKey('pawn-status')), findsNothing);
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();
      expect(repo.saved, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('pawn-customer')),
        'Khách',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pawn-customer-option-1')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('pawn-amount')),
        '5000000',
      );
      await tester.tap(find.byKey(const ValueKey('pawn-interest-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('%/tháng').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('pawn-rate')), '2,5');
      await tester.tap(find.byKey(const ValueKey('pawn-due-date-null')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('pawn-asset')),
        'Điện thoại thử',
      );
      await tester.enterText(
        find.byKey(const ValueKey('pawn-notes')),
        'Ghi chú nguồn',
      );
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();
      expect(repo.saved!.keys.toSet(), {
        'SoTienVay',
        'TaiSanTheChap',
        'NgayPhanTram',
        'LaiSuat',
        'NgayHan',
        'NgayVay',
        'IdKhachHang',
        'GhiChu',
        'TrangThai',
      });
      expect(repo.saved!['IdKhachHang'], 1);
      expect(repo.saved!['SoTienVay'], 5000000);
      expect(repo.saved!['LaiSuat'], 2.5);
      expect(repo.saved!['NgayPhanTram'], false);
      expect(repo.saved!['TrangThai'], false);
      expect(find.byType(PawnEditorPopup), findsNothing);
      expect(find.text('Đã lưu phiếu cầm đồ #100'), findsOneWidget);
      expect(find.text('#100'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('New customer is selected automatically in pawn form', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final customers = FakeCustomerRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: PawnTab(repository: _Repository(), customers: customers),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pawn-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pawn-customer-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('customer-name')),
      'Khách mới cầm đồ',
    );
    await tester.tap(find.text('Lưu khách hàng'));
    await tester.pumpAndSettle();
    expect(customers.rows.length, 2);
    expect(find.text('Khách mới cầm đồ'), findsOneWidget);
    expect(find.byType(PawnEditorPopup), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dashboard pawn section opens actual pawn module', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      StoreApp(
        salesRepositoryFactory: FakeSalesRepository.new,
        customerRepositoryFactory: FakeCustomerRepository.new,
        pawnRepositoryFactory: _Repository.new,
      ),
    );
    await tester.tap(find.text('Cầm đồ').first);
    await tester.pumpAndSettle();
    expect(find.byType(PawnTab), findsOneWidget);
    expect(find.byKey(const ValueKey('pawn-add')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Pawn form fits narrow windows', (tester) async {
    tester.view.physicalSize = const Size(420, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: PawnTab(
            repository: _Repository(),
            customers: FakeCustomerRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pawn-add')));
    await tester.pumpAndSettle();
    expect(find.text('Thêm phiếu cầm đồ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
