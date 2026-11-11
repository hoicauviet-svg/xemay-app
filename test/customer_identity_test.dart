import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/models/customers/customer_models.dart';
import 'package:xemay_app/models/pawn/pawn_models.dart';
import 'package:xemay_app/models/printing/pawn_contract_data.dart';
import 'package:xemay_app/views/customers/customer_editor_popup.dart';
import 'support/fake_customer_repository.dart';

void main() {
  test(
    'Identity fields retain leading zeros, validate dates and support clearing',
    () {
      final draft = CustomerDraft()
        ..cccd = ' 001234567890 '
        ..cmnd = '001234567'
        ..issueDate = '29/02/2024'
        ..issuePlace = ' Hà Nội ';
      expect(draft.identityFields(), {
        'SoCCCD': '001234567890',
        'SoCMND': '001234567',
        'NgayCap': DateTime.utc(2024, 2, 29),
        'NoiCap': 'Hà Nội',
      });
      expect(draft.validateIssueDate('31/02/2024'), isNotNull);
      expect(draft.validateIssueDate('2024-02-29'), isNotNull);
      expect(draft.validateIssueDate('01/01/2999'), isNotNull);
      draft.issueDate = '';
      expect(draft.identityFields()['NgayCap'], isNull);
      expect(CustomerDraft().identityFields()['SoCCCD'], '');
    },
  );
  test('Contract fills identity from customer and falls back to CMND', () {
    final customer = <String, dynamic>{
      'SoCCCD': '001234567890',
      'SoCMND': '001234567',
      'NgayCap': DateTime.utc(2020, 5, 4),
      'NoiCap': 'Hà Nội',
    };
    PawnContractData data() => PawnContractData(
      PawnDetails(
        contract: {'IdCamDo': 1, 'SoTienVay': 5000000},
        customer: customer,
        payments: [],
      ),
    );
    expect(data().identityNumber, '001234567890');
    expect(data().identityDate, '04/05/2020');
    expect(data().identityPlace, 'Hà Nội');
    customer['SoCCCD'] = '';
    expect(data().identityNumber, '001234567');
  });
  testWidgets(
    'Customer editor creates, reloads and clears saved identity fields',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeCustomerRepository();
      Future<void> open({Map<String, dynamic>? initial}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: CustomerEditorPopup(
              initial: initial,
              embedded: true,
              onCreate: initial == null
                  ? repo.create
                  : (draft) => repo.update(2, draft),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await open();
      for (final entry in {
        'name': 'Khách mới',
        'cccd': '001234567890',
        'cmnd': '001234567',
        'issue-date': '04/05/2020',
        'issue-place': 'Hà Nội',
      }.entries) {
        final finder = find.byKey(ValueKey('customer-${entry.key}'));
        await tester.ensureVisible(finder);
        await tester.enterText(finder, entry.value);
      }
      await tester.tap(find.text('Lưu khách hàng'));
      await tester.pumpAndSettle();
      final saved = repo.rows.last;
      expect(saved['SoCCCD'], '001234567890');
      expect(saved['NgayCap'], DateTime.utc(2020, 5, 4));
      await tester.pumpWidget(const SizedBox());
      await open(initial: saved);
      expect(find.text('001234567890'), findsOneWidget);
      expect(find.text('04/05/2020'), findsOneWidget);
      for (final key in ['cccd', 'cmnd', 'issue-date', 'issue-place']) {
        final finder = find.byKey(ValueKey('customer-$key'));
        await tester.ensureVisible(finder);
        await tester.enterText(finder, '');
      }
      await tester.tap(find.text('Lưu khách hàng'));
      await tester.pumpAndSettle();
      expect(saved['SoCCCD'], '');
      expect(saved['SoCMND'], '');
      expect(saved['NgayCap'], isNull);
      expect(saved['NoiCap'], '');
      expect(tester.takeException(), isNull);
    },
  );
}
