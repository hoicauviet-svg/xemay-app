import 'package:xemay_app/services/mongo_connection_uri.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/controllers/database_settings_controller.dart';
import 'package:xemay_app/controllers/cart_controller.dart';
import 'package:xemay_app/core/config/database_config.dart';
import 'package:xemay_app/models/settings/database_settings.dart';
import 'package:xemay_app/services/native_database_settings_repository.dart';
import 'package:xemay_app/views/settings/settings_tab.dart';
import 'support/fake_database_settings_repository.dart';

void main() {
  test(
    'Mongo runtime keeps authentication, multi-host nodes and defaults to XM',
    () async {
      expect(
        await MongoConnectionUri.resolve('mongodb://localhost:27017'),
        'mongodb://localhost:27017/XM',
      );
      expect(
        await MongoConnectionUri.resolve(
          'mongodb://u:a%40b@host1:27017,host2:27018/XM?authSource=admin',
        ),
        'mongodb://u:a%40b@host1:27017,host2:27018/XM?authSource=admin',
      );
      expect(
        () => MongoConnectionUri.validate('http://localhost'),
        throwsA(isA<DatabaseSettingsException>()),
      );
    },
  );

  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    CartController.shared.clear();
  });
  tearDown(() {
    CartController.shared.clear();
  });
  test(
    'connection save requires successful ping and preserves SQL settings',
    () async {
      final repo = FakeDatabaseSettingsRepository();
      final controller = DatabaseSettingsController(repo);
      addTearDown(controller.dispose);
      await controller.load();
      await controller.saveMongo('mongodb://127.0.0.1:27017/NEW');
      expect(repo.saves, 0);
      expect(controller.error, isNotNull);
      repo.status = const MongoInstallationStatus(
        installed: true,
        connected: true,
      );
      await controller.saveMongo('mongodb://127.0.0.1:27017/NEW');
      expect(repo.saves, 1);
      expect(repo.settings.sqlConnection, contains('Database=xm'));
      repo.failSql = true;
      await controller.checkSql('bad', save: true);
      expect(repo.saves, 1);
    },
  );
  test(
    'clone never activates until explicitly selected; dirty cart blocks switching',
    () async {
      final repo = FakeDatabaseSettingsRepository();
      final controller = DatabaseSettingsController(repo);
      addTearDown(controller.dispose);
      await controller.load();
      await controller.clone(repo.settings.sqlConnection);
      expect(repo.clones, 1);
      expect(repo.saves, 0);
      expect(controller.cloneResult?.orphans, 123);
      CartController.shared.add({
        'IdXe': 123,
        'IdSanPham': 1,
        'SoLuongTon': 1,
        'GiaBan': 100,
        'LoaiSanPham': 'xe',
      }, vehicle: true);
      await controller.useClone();
      expect(repo.saves, 0);
      expect(controller.error, contains('đơn bán hàng'));
      CartController.shared.clear();
      repo.status = const MongoInstallationStatus(
        installed: true,
        connected: true,
      );
      await controller.useClone();
      expect(repo.saves, 1);
      expect(repo.settings.mongoUri, contains('XM_import_test'));
    },
  );
  test(
    'native connection storage uses secure channel and publishes database changes',
    () async {
      const channel = MethodChannel('xemay/database_settings');
      String? stored;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'load') return stored;
            if (call.method == 'save') {
              stored = (call.arguments as Map)['value'] as String;
              return null;
            }
            throw PlatformException(code: 'unexpected');
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        DatabaseConfig.useMongo(DatabaseConfig.defaultMongoUri);
      });
      final repo = NativeDatabaseSettingsRepository();
      const settings = DatabaseSettings(
        mongoUri: 'mongodb://localhost:27017/XM',
        sqlConnection: 'Server=test;Database=xm;UID=u;PWD=example;',
      );
      await repo.save(settings);
      expect(jsonDecode(stored!)['sqlConnection'], settings.sqlConnection);
      expect((await repo.load()).mongoUri, settings.mongoUri);
      expect(DatabaseConfig.mongoUri, settings.mongoUri);
    },
  );
  testWidgets(
    'settings has Mongo and SQL tabs, missing-install prompt, connection controls and explicit clone activation',
    (t) async {
      t.view.physicalSize = const Size(1400, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final repo = FakeDatabaseSettingsRepository();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SettingsTab(repository: repo)),
        ),
      );
      await t.pumpAndSettle();
      expect(find.widgetWithText(Tab, 'MongoDB'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'SQL Server'), findsOneWidget);
      expect(find.textContaining('Chưa phát hiện MongoDB'), findsOneWidget);
      await t.tap(find.text('Hướng dẫn cài MongoDB'));
      await t.pumpAndSettle();
      expect(repo.installOpened, true);
      repo.status = const MongoInstallationStatus(
        installed: true,
        connected: true,
      );
      await t.tap(find.byKey(const ValueKey('settings-check-mongo')));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(Tab, 'SQL Server'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('settings-check-sql')));
      await t.pumpAndSettle();
      expect(find.textContaining('20 bảng'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('settings-clone')));
      await t.pumpAndSettle();
      expect(repo.clones, 0);
      await t.tap(find.text('Bắt đầu sao chép'));
      await t.pumpAndSettle();
      expect(repo.clones, 1);
      expect(repo.saves, 0);
      expect(find.byKey(const ValueKey('settings-use-clone')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('settings-use-clone')));
      await t.pumpAndSettle();
      expect(repo.saves, 1);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('connection settings fit a narrow window', (t) async {
    t.view.physicalSize = const Size(420, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsTab(repository: FakeDatabaseSettingsRepository()),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(Tab, 'SQL Server'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
