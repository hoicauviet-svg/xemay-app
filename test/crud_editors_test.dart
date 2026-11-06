import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/core/theme/app_theme.dart';
import 'package:xemay_app/controllers/directory_controller.dart';
import 'package:xemay_app/models/directory/directory_models.dart';
import 'package:xemay_app/models/products/product_details.dart';
import 'package:xemay_app/models/customers/customer_models.dart';
import 'package:xemay_app/views/customers/customer_editor_popup.dart';
import 'package:xemay_app/views/directory/directory_editor_popup.dart';
import 'package:xemay_app/views/products/product_editor_popup.dart';
import 'support/fake_directory_repository.dart';

void main() {
  Future<void> open(WidgetTester t, Widget popup) async {
    t.view.physicalSize = const Size(1200, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showDialog<void>(context: c, builder: (_) => popup),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
  }

  testWidgets(
    'Customer edit prefills every field and updates without creating',
    (t) async {
      CustomerDraft? saved;
      await open(
        t,
        CustomerEditorPopup(
          initial: const {
            'IdKH': 12,
            'TenKhachHang': 'Khách cũ',
            'SoDienThoai': '090123',
            'DiaChiHienThi': 'Thôn 1, Xã 2',
          },
          onCreate: (d) async {
            saved = d;
            return {'IdKH': 12};
          },
        ),
      );
      expect(find.text('Khách cũ'), findsOneWidget);
      expect(find.text('090123'), findsOneWidget);
      expect(find.text('Thôn 1, Xã 2'), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('customer-name')),
        'Khách mới',
      );
      await t.tap(find.text('Lưu khách hàng'));
      await t.pumpAndSettle();
      expect(saved!.name, 'Khách mới');
      expect(saved!.address, 'Thôn 1, Xã 2');
      expect(find.text('Cập nhật khách hàng'), findsNothing);
    },
  );
  testWidgets(
    'Carrier editor preserves phone plate notes on rename; failure can retry',
    (t) async {
      final repo = FakeDirectoryRepository();
      final directory = DirectoryController(repo);
      addTearDown(directory.dispose);
      final existing = repo.entries.firstWhere(
        (e) => e.kind == DirectoryKind.carrier,
      );
      await open(
        t,
        DirectoryEditorPopup(
          directory: directory,
          kind: DirectoryKind.carrier,
          existing: existing,
        ),
      );
      expect(find.text(existing.plate), findsOneWidget);
      expect(find.text(existing.phone), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('directory-name')),
        'Vận chuyển mới',
      );
      repo.failSave = true;
      await t.tap(find.text('Lưu thay đổi'));
      await t.pumpAndSettle();
      expect(find.textContaining('Không lưu được dữ liệu'), findsOneWidget);
      repo.failSave = false;
      await t.tap(find.text('Lưu thay đổi'));
      await t.pumpAndSettle();
      final saved = repo.entries.firstWhere((e) => e.id == existing.id);
      expect(saved.name, 'Vận chuyển mới');
      expect(saved.plate, existing.plate);
      expect(repo.saves, 0);
    },
  );
  testWidgets(
    'Product editor locks sold vehicle price and validates empty names',
    (t) async {
      ProductEditDraft? saved;
      await open(
        t,
        ProductEditorPopup(
          product: const ProductReference(id: 7, vehicle: true),
          information: const {
            'TenXe': 'Xe cũ',
            'GiaBan': 10000000,
            'TinhTrang': false,
            'SoKhung': 'FRAME',
            'SoMay': 'ENGINE',
          },
          onSave: (d) async {
            saved = d;
          },
        ),
      );
      final name = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Tên sản phẩm',
      );
      final price = t.widget<TextField>(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Giá bán',
        ),
      );
      expect(price.enabled, isFalse);
      await t.enterText(name, '');
      await t.tap(find.text('Lưu thay đổi'));
      await t.pumpAndSettle();
      expect(saved, isNull);
      expect(find.text('Vui lòng nhập Tên sản phẩm'), findsOneWidget);
      await t.enterText(name, 'Xe mới tên');
      await t.tap(find.text('Lưu thay đổi'));
      await t.pumpAndSettle();
      expect(saved!.name, 'Xe mới tên');
      expect(saved!.salePrice, '10000000');
      expect(saved!.frame, 'FRAME');
    },
  );
}
