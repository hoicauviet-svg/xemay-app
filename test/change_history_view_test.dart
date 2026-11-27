import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/models/repositories/change_history_repository.dart';
import 'package:xemay_app/views/settings/change_history_tab.dart';

class _HistoryRepository implements ChangeHistoryRepository {
  _HistoryRepository(this.rows);
  final List<Map<String, dynamic>> rows;
  int calls = 0;
  String? lastSearch;

  @override
  Future<List<Map<String, dynamic>>> fetch({
    String search = '',
    int limit = 100,
  }) async {
    calls++;
    lastSearch = search;
    return rows;
  }

  @override
  Future<void> close() async {}
}

void main() {
  testWidgets('Change history lists edits and shows the saved details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _HistoryRepository([
      {
        '_id': 'change:6af42e07a84357c83c95ded1',
        'At': DateTime.utc(2026, 11, 27, 10, 30),
        'Action': 'paymentDelete',
        'Kind': 'order',
        'Source': 'record-maintenance',
        'ParentId': 42,
        'RequestId': '6af42e07a84357c83c95ded1',
        'Summary': 'Xóa phiếu trả nợ đơn hàng #42',
        'Machine': 'MAY-VP',
        'Platform': 'macos',
        'AppVersion': '1.0.1+23',
        'Before': {'SoTienDaTra': 100000},
        'After': {'SoTienDaTra': 0},
        'Changes': [
          {'Collection': 'TraNo', 'Id': 'payment-1', 'Deleted': true},
        ],
      },
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ChangeHistoryTab(repository: repository)),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.calls, 1);
    expect(find.text('Xóa phiếu trả nợ'), findsOneWidget);
    expect(find.text('đơn hàng'), findsOneWidget);
    expect(find.text('#42'), findsOneWidget);
    expect(find.text('Xóa phiếu trả nợ đơn hàng #42'), findsOneWidget);
    expect(find.text('MAY-VP'), findsOneWidget);

    await tester.tap(find.text('Xóa phiếu trả nợ đơn hàng #42'));
    await tester.pumpAndSettle();
    expect(find.text('Trước khi thay đổi'), findsOneWidget);
    expect(find.text('Sau khi thay đổi'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Các bước đã ghi'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Các bước đã ghi'), findsOneWidget);
    expect(find.textContaining('payment-1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Change history supports an empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeHistoryTab(repository: _HistoryRepository(const [])),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chưa có lịch sử thay đổi.'), findsOneWidget);
  });
}
