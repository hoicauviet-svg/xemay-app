import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/core/theme/app_theme.dart';
import 'package:xemay_app/models/pawn/pawn_models.dart';
import 'package:xemay_app/models/repositories/pawn_repository.dart';
import 'package:xemay_app/views/pawn/pawn_editor_popup.dart';
import 'support/fake_customer_repository.dart';

class _Repository extends PawnRepository {
  @override
  Future<PawnPage> fetch({
    String search = '',
    int page = 0,
    int? customerId,
    String status = 'all',
  }) async => const PawnPage([], 0);
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
  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('Customer field aligns with add button at scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(
            platform: TargetPlatform.macOS,
            visualDensity: VisualDensity.compact,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => PawnEditorPopup(
                    repository: _Repository(),
                    customers: FakeCustomerRepository(),
                  ),
                ),
                child: const Text('Mở'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Mở'));
      await tester.pumpAndSettle();
      void aligned() {
        final editable = find.descendant(
          of: find.byKey(const ValueKey('pawn-customer')),
          matching: find.byType(EditableText),
        );
        final container = InputDecorator.containerOf(tester.element(editable))!;
        final border = container.localToGlobal(Offset.zero) & container.size;
        final button = tester.getRect(
          find.byKey(const ValueKey('pawn-customer-add')),
        );
        expect(
          button.top,
          closeTo(border.top, 0.5),
          reason: 'Button $button / input border $border',
        );
        expect(
          button.height,
          closeTo(border.height, 0.5),
          reason: 'Button $button / input border $border',
        );
      }

      expect(
        tester
            .getSize(find.byType(RawAutocomplete<Map<String, dynamic>>))
            .width,
        closeTo(
          tester.getSize(find.byKey(const ValueKey('pawn-amount'))).width * 2 +
              16,
          0.5,
        ),
      );
      aligned();
      await tester.tap(find.byKey(const ValueKey('pawn-customer')));
      await tester.pumpAndSettle();
      aligned();
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();
      aligned();
    });
  }
}
