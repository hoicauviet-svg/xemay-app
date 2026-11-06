import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/models/maintenance/record_maintenance.dart';
import 'package:xemay_app/views/maintenance/record_actions.dart';
import 'package:xemay_app/views/maintenance/record_recovery_button.dart';

class _Maintenance extends RecordMaintenance {
  int writes = 0, recoveries = 0;
  bool fail = false;
  final requests = <String>[];
  Map<String, dynamic>? fields;
  @override
  Future<RecordEditData> load(RecordKind kind, int id) async => RecordEditData(
    {
      'NgayNhap': DateTime(2026, 1, 1),
      'SoLuong': 2,
      'SoTien': 100000,
      'GhiChu': 'Lô thử',
    },
    [],
    [
      {
        '_id': 'payment',
        'IdTraNoNhapHang': 1,
        'NgayTra': DateTime(2026, 2, 1),
        'SoTienTra': 10000,
        'GhiChu': 'Phiếu thử',
      },
    ],
  );
  @override
  Future<List<Map<String, dynamic>>> suggestions(
    String collection,
    String search,
  ) async => [];
  @override
  Future<void> ensureReadable(RecordKind kind, int id) async {}
  @override
  Future<List<Map<String, dynamic>>> pending() async => recoveries == 0
      ? [
          {'_id': 'request', 'Kind': 'batch', 'Parent': 1},
        ]
      : [];
  @override
  Future<void> recover(RecordKind kind, int id) async {
    recoveries++;
  }

  @override
  Future<void> save(
    RecordKind kind,
    int id,
    Map<String, dynamic> values,
    List<Map<String, dynamic>> lines, {
    required String requestId,
  }) async {
    writes++;
    fields = values;
  }

  @override
  Future<void> delete(
    RecordKind kind,
    int id, {
    required String requestId,
  }) async {
    writes++;
  }

  @override
  Future<void> payment(
    RecordKind kind,
    int parentId,
    dynamic paymentId,
    Map<String, dynamic>? values, {
    required String requestId,
    DateTime? interestStart,
    DateTime? nextAppointment,
  }) async {
    writes++;
    requests.add(requestId);
    fields = values;
    if (fail) {
      throw const RecordChangeException(
        'Mất kết nối, thử lại',
        uncertain: true,
      );
    }
  }
}

void main() {
  testWidgets(
    'Edit repayment preloads values and retries same request after uncertain write',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _Maintenance();
      var changed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecordActions(
              repository: repo,
              kind: RecordKind.batch,
              id: 1,
              paymentId: 'payment',
              onChanged: () async {
                changed++;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Sửa phiếu trả nợ'));
      await tester.pumpAndSettle();
      final amount = find.byWidgetPredicate(
        (w) =>
            w is TextField && w.decoration?.labelText == 'Số tiền thanh toán',
      );
      expect(tester.widget<TextField>(amount).controller!.text, '10000');
      await tester.enterText(amount, '15000');
      repo.fail = true;
      await tester.tap(find.widgetWithText(FilledButton, 'Lưu thay đổi'));
      await tester.pumpAndSettle();
      expect(repo.writes, 1);
      expect(changed, 0);
      expect(tester.widget<TextField>(amount).enabled, false);
      repo.fail = false;
      await tester.tap(find.widgetWithText(FilledButton, 'Thử lại'));
      await tester.pumpAndSettle();
      expect(repo.requests.first, repo.requests.last);
      expect(repo.fields!['SoTienTra'], 15000);
      expect(changed, 1);
      expect(find.byType(RecordEditor), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Delete repayment requires explicit confirmation', (
    tester,
  ) async {
    final repo = _Maintenance();
    var changed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordActions(
            repository: repo,
            kind: RecordKind.batch,
            id: 1,
            paymentId: 'payment',
            onChanged: () async {
              changed++;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Xóa phiếu trả nợ'));
    await tester.pumpAndSettle();
    expect(repo.writes, 0);
    await tester.tap(find.widgetWithText(FilledButton, 'Xác nhận xóa'));
    await tester.pumpAndSettle();
    expect(repo.writes, 1);
    expect(repo.fields, isNull);
    expect(changed, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Opening pending changes is read-only until Continue is clicked',
    (tester) async {
      final repo = _Maintenance();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RecordRecoveryButton(repository: repo)),
        ),
      );
      await tester.tap(find.byTooltip('Tiếp tục xử lý thay đổi dang dở'));
      await tester.pumpAndSettle();
      expect(repo.recoveries, 0);
      expect(repo.writes, 0);
      await tester.tap(find.widgetWithText(FilledButton, 'Tiếp tục xử lý'));
      await tester.pumpAndSettle();
      expect(repo.recoveries, 1);
      expect(find.text('Không có thay đổi dang dở.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
