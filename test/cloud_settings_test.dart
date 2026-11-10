import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/controllers/cart_controller.dart';
import 'package:xemay_app/controllers/database_settings_controller.dart';
import 'package:xemay_app/models/settings/database_settings.dart';
import 'package:xemay_app/views/settings/settings_tab.dart';
import 'support/fake_database_settings_repository.dart';

void main() {
  setUp(() => CartController.shared.clear());
  tearDown(() => CartController.shared.clear());

  test(
    'cloud settings survive SQL and local saves, upload and download use correct direction',
    () async {
      final repo = FakeDatabaseSettingsRepository()
        ..status = const MongoInstallationStatus(
          installed: true,
          connected: true,
        );
      final controller = DatabaseSettingsController(repo);
      addTearDown(controller.dispose);
      await controller.load();
      final local = controller.settings.mongoUri;
      await controller.checkCloud('mongodb://cloud:27017/XM', save: true);
      expect(controller.settings.mongoUri, local);
      await controller.checkSql(repo.settings.sqlConnection, save: true);
      await controller.saveMongo(local);
      expect(controller.settings.cloudUri, 'mongodb://cloud:27017/XM');
      await controller.syncCloud(upload: true);
      expect(repo.syncSource, local);
      expect(repo.syncTarget, 'mongodb://cloud:27017/XM');
      expect(controller.settings.mongoUri, local);
      expect(controller.settings.cloudUri, 'mongodb://cloud:27017/XM-sync');
      await controller.syncCloud(upload: false);
      expect(repo.syncSource, 'mongodb://cloud:27017/XM-sync');
      expect(repo.syncTarget, local);
      expect(controller.settings.mongoUri, '$local-sync');
    },
  );

  test(
    'failed sync leaves saved configuration intact and cart blocks sync',
    () async {
      final repo = FakeDatabaseSettingsRepository()
        ..settings = const DatabaseSettings(
          mongoUri: 'mongodb://local/XM',
          cloudUri: 'mongodb://cloud/XM',
        );
      final controller = DatabaseSettingsController(repo);
      addTearDown(controller.dispose);
      await controller.load();
      repo.failSync = true;
      await controller.syncCloud(upload: false);
      expect(controller.error, isNotNull);
      expect(repo.saves, 0);
      expect(controller.settings.mongoUri, 'mongodb://local/XM');
      CartController.shared.setLocked(true);
      try {
        await controller.syncCloud(upload: true);
        expect(repo.syncs, 1);
        expect(controller.error, contains('đơn bán hàng'));
      } finally {
        CartController.shared.setLocked(false);
      }
    },
  );

  testWidgets(
    'cloud tab saves connection and offers upload/download with confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(1300, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeDatabaseSettingsRepository()
        ..status = const MongoInstallationStatus(
          installed: true,
          connected: true,
        );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SettingsTab(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'MongoDB Cloud'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('settings-cloud-uri')),
        'mongodb://cloud/XM',
      );
      await tester.tap(find.byKey(const ValueKey('settings-save-cloud')));
      await tester.pumpAndSettle();
      expect(repo.settings.cloudUri, 'mongodb://cloud/XM');
      await tester.tap(find.byKey(const ValueKey('settings-upload-cloud')));
      await tester.pumpAndSettle();
      expect(find.text('Đồng bộ dữ liệu lên cloud?'), findsOneWidget);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(repo.syncs, 0);
      expect(
        find.byKey(const ValueKey('settings-download-cloud')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('settings-upload-cloud')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tiếp tục'));
      await tester.pumpAndSettle();
      expect(repo.syncs, 1);
      expect(find.textContaining('Đã đồng bộ lên cloud:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
