import 'package:xemay_app/models/maintenance/record_maintenance.dart';
import 'package:xemay_app/views/maintenance/record_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/core/theme/app_theme.dart';
import 'package:xemay_app/models/pawn/pawn_models.dart';
import 'package:xemay_app/models/repositories/pawn_repository.dart';
import 'package:xemay_app/views/pawn/pawn_details_screen.dart';
import 'package:xemay_app/views/pawn/pawn_tab.dart';
import 'support/fake_customer_repository.dart';

class _Repository extends PawnRepository {
  RecordMaintenance? actions;
  @override
  RecordMaintenance? get maintenance => actions;
  final contract = <String, dynamic>{
    'IdCamDo': 42,
    'IdKhachHang': 1,
    'TenKhachHang': 'Khách thử',
    'SoTienVay': 5000000,
    'TaiSanTheChap': 'Tài sản thử',
    'NgayVay': DateTime(2026, 11, 1),
    'NgayHan': DateTime(2026, 12, 1),
    'LaiSuat': 3,
    'NgayPhanTram': false,
    'TrangThai': false,
  };
  final payments = <Map<String, dynamic>>[];
  PawnPaymentDraft? saved;
  @override
  Future<PawnPage> fetch({
    String search = '',
    int page = 0,
    int? customerId,
    String status = 'all',
  }) async => PawnPage([contract], 1);
  @override
  Future<PawnDetails> details(int id) async => PawnDetails(
    contract: Map.of(contract),
    payments: List.of(payments),
    customer: {'TenKhachHang': 'Khách thử'},
  );
  @override
  Future<void> pay(
    PawnPaymentDraft payment, {
    required String requestId,
  }) async {
    saved = payment;
    payments.add({'IdTraNoCamDo': 10, ...payment.toFields()});
  }

  @override
  Future<int> create(PawnDraft draft, {required String requestId}) async => 42;
  @override
  Future<void> close() async {}
}

class _Maintenance extends RecordMaintenance {
  _Maintenance(this.repo);
  final _Repository repo;
  int deletes = 0;
  @override
  Future<RecordEditData> load(RecordKind kind, int id) async =>
      RecordEditData({...repo.contract, '_CustomerName': 'Khách thử'}, [], []);
  @override
  Future<void> save(
    RecordKind kind,
    int id,
    Map<String, dynamic> fields,
    List<Map<String, dynamic>> lines, {
    required String requestId,
  }) async {
    repo.contract.addAll(fields);
  }

  @override
  Future<void> delete(
    RecordKind kind,
    int id, {
    required String requestId,
  }) async {
    deletes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'Pawn information owns print, edit and explicit deletion warning',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _Repository();
      final maintenance = _Maintenance(repo);
      repo.actions = maintenance;
      await tester.pumpWidget(
        MaterialApp(home: PawnDetailsScreen(id: 42, repository: repo)),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'In hợp đồng'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.print_outlined),
        ),
        findsNothing,
      );
      await tester.tap(find.text('Cập nhật thông tin'));
      await tester.pumpAndSettle();
      final collateral = find.widgetWithText(TextFormField, 'Tài sản thế chấp');
      expect(collateral, findsOneWidget);
      await tester.enterText(collateral, 'Xe đã cập nhật');
      await tester.tap(find.text('Lưu thay đổi'));
      await tester.pumpAndSettle();
      expect(repo.contract['TaiSanTheChap'], 'Xe đã cập nhật');
      expect(find.text('Xe đã cập nhật'), findsOneWidget);
      await tester.tap(find.text('Xóa phiếu'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('toàn bộ lịch sử thu gốc, thu lãi'),
        findsOneWidget,
      );
      expect(find.text('Xác nhận xóa'), findsOneWidget);
      expect(maintenance.deletes, 0);
      // Close the confirmation without performing a deletion.
      Navigator.of(tester.element(find.byType(RecordEditor))).pop();
      await tester.pumpAndSettle();
      expect(maintenance.deletes, 0);
      await tester.tap(find.widgetWithText(Tab, 'Lịch sử'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilledButton, 'In hợp đồng').hitTestable(),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Current interest displays whole dong consistently with payment',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _Repository();
      final now = DateTime.now();
      repo.contract['NgayVay'] = DateTime.utc(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 1));
      repo.contract['SoTienVay'] = 1000000;
      repo.contract['LaiSuat'] = 2.5;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PawnDetailsScreen(id: 42, repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('833 đ'), findsOneWidget);
      expect(find.text('833,33 đ'), findsNothing);
      await tester.tap(find.widgetWithText(Tab, 'Thanh toán'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('pawn-payment-interest')),
            )
            .controller!
            .text,
        '833',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Pawn opens a page with history and saves principal/interest separately',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _Repository();
      repo.contract['NgayHan'] = DateTime.now().subtract(
        const Duration(days: 3),
      );
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
      await tester.tap(find.text('#42'));
      await tester.pumpAndSettle();
      expect(find.byType(PawnDetailsScreen), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byKey(const ValueKey('pawn-overdue-notice')), findsOneWidget);
      expect(find.text('Phiếu cầm đồ đã quá hạn 3 ngày'), findsOneWidget);
      expect(find.text('Ngày tính lãi'), findsOneWidget);
      expect(find.text('Lãi kỳ hiện tại'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Thông tin'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Lịch sử'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Thanh toán'), findsOneWidget);
      await tester.tap(find.widgetWithText(Tab, 'Lịch sử'));
      await tester.pumpAndSettle();
      expect(find.text('Chưa có lịch sử thanh toán.'), findsOneWidget);
      await tester.tap(find.widgetWithText(Tab, 'Thanh toán'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('pawn-payment-principal')),
        '5000001',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Thanh toán'));
      await tester.pumpAndSettle();
      expect(repo.saved, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('pawn-payment-principal')),
        '1000000',
      );
      final expectedInterest = (await repo.details(
        42,
      )).interestAccrualAt(DateTime.now())!.roundedAmount;
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('pawn-payment-interest')),
                matching: find.byType(TextField),
              ),
            )
            .readOnly,
        isTrue,
      );
      await tester.enterText(
        find.byKey(const ValueKey('pawn-payment-collected')),
        '100000',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Thanh toán'));
      await tester.pumpAndSettle();
      expect(repo.saved!.principal, 1000000);
      expect(repo.saved!.interest, expectedInterest);
      expect(repo.saved!.collectedInterest, 100000);
      expect(find.text('Thanh toán thành công'), findsOneWidget);

      expect(find.text('100.000 đ'), findsOneWidget);
      await tester.tap(find.widgetWithText(Tab, 'Thông tin'));
      await tester.pumpAndSettle();
      expect(find.text('4.000.000 đ'), findsOneWidget);
      await tester.tap(find.byTooltip('Quay lại'));
      await tester.pumpAndSettle();
      expect(find.byType(PawnDetailsScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Pawn payment adapts to narrow windows', (tester) async {
    tester.view.physicalSize = const Size(420, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PawnDetailsScreen(id: 42, repository: _Repository()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(Tab, 'Thanh toán'));
    await tester.tap(find.widgetWithText(Tab, 'Thanh toán'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('pawn-payment-collected')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
