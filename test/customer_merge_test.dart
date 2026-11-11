import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/views/customers/customer_merge_tab.dart';
import 'support/fake_customer_repository.dart';

void main() {
  testWidgets(
    'Selection survives search, cancellation and failed merge retry',
    (tester) async {
      tester.view.physicalSize = const Size(1300, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeCustomerRepository();
      repo.rows.add({
        '_id': 2,
        'IdKH': 2,
        'TenKhachHang': 'Khách kiểm thử',
        'DiaChiChiTiet': 'Thôn 1, Xã kiểm thử',
        'SoDienThoai': '0900000001',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CustomerMergeTab(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();
      final merge = find.widgetWithText(FilledButton, 'Gộp khách hàng');
      expect(tester.widget<FilledButton>(merge).onPressed, isNull);
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.enterText(find.byType(TextField), 'kiểm thử');
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      await tester.tap(find.byType(CheckboxListTile).at(1));
      await tester.pump();
      expect(find.text('Đã chọn 2 khách hàng'), findsOneWidget);
      await tester.tap(merge);
      await tester.pumpAndSettle();
      expect(find.textContaining('Giữ khách chính: #1'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Hủy'));
      await tester.pumpAndSettle();
      expect(repo.rows.length, 2);
      repo.failSave = true;
      await tester.tap(merge);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Xác nhận gộp'));
      await tester.pumpAndSettle();
      expect(repo.rows.length, 2);
      expect(find.textContaining('Không gộp được'), findsOneWidget);
      repo.failSave = false;
      await tester.tap(find.widgetWithText(FilledButton, 'Thử lại'));
      await tester.pumpAndSettle();
      expect(repo.rows.length, 1);
      expect(repo.rows.single['IdKH'], 1);
      expect(find.byType(CustomerMergeTab), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsOneWidget);
      expect(find.text('1 kết quả · 1 khách trên trang'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Paginate whole groups, retain selections and reset page on search',
    (tester) async {
      tester.view.physicalSize = const Size(1300, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeCustomerRepository();
      repo.rows.clear();
      for (var group = 0; group < 11; group++) {
        for (var member = 0; member < (group == 10 ? 3 : 2); member++) {
          repo.rows.add({
            'IdKH': group * 10 + member + 1,
            'TenKhachHang': 'Nhóm ${group.toString().padLeft(2, '0')}',
            'SoDienThoai': '0901234567',
            'DiaChiChiTiet': 'Phố $group',
          });
        }
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CustomerMergeTab(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.textContaining('3 khách hàng · nhóm 10'), findsOneWidget);
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();
      await tester.tap(find.byTooltip('Trang sau'));
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.textContaining('2 khách hàng · nhóm 09'), findsOneWidget);
      expect(find.text('Đã chọn 1 khách hàng'), findsOneWidget);
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();
      expect(find.text('Đã chọn 2 khách hàng'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Nhóm 10');
      await tester.pumpAndSettle();
      expect(find.text('1 / 1'), findsOneWidget);
      expect(find.text('Đã chọn 2 khách hàng'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Keyword search includes unique customers with different or missing contact information',
    (tester) async {
      final repo = FakeCustomerRepository();
      repo.rows.add({
        'IdKH': 2,
        'TenKhachHang': 'Khách kiểm thử khác',
        'DiaChiChiTiet': 'Nơi khác',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CustomerMergeTab(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNothing);
      await tester.enterText(find.byType(TextField), 'kiểm thử');
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNWidgets(2));
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Nơi khác');
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsOneWidget);
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();
      expect(find.text('Đã chọn 2 khách hàng'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.text('Đã chọn 2 khách hàng'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Keyword results paginate unique customers independently from duplicate groups',
    (tester) async {
      final repo = FakeCustomerRepository();
      repo.rows.clear();
      for (var id = 1; id <= 31; id++) {
        repo.rows.add({'IdKH': id, 'TenKhachHang': 'Khách tìm kiếm $id'});
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CustomerMergeTab(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Khách tìm kiếm');
      await tester.pumpAndSettle();
      expect(find.text('31 kết quả · 30 khách trên trang'), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();
      await tester.tap(find.byTooltip('Trang sau'));
      await tester.pumpAndSettle();
      expect(find.text('31 kết quả · 1 khách trên trang'), findsOneWidget);
      expect(find.text('#31 — Khách tìm kiếm 31'), findsOneWidget);
      expect(find.text('Đã chọn 1 khách hàng'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
