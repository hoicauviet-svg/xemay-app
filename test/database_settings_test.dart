import 'package:xemay_app/services/mongo_connection_uri.dart';
import 'dart:convert';
import 'dart:async';
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
      final settings = DatabaseSettings(
        mongoUri: 'mongodb://localhost:27017/XM',
        sqlConnection: 'Server=test;Database=xm;UID=u;PWD=example;',
        cloudUri: 'mongodb://cloud/XM',
        databaseVersion: FakeDatabaseSettingsRepository.localVersion,
        cloudVersion: FakeDatabaseSettingsRepository.remoteVersion,
        lastSyncAt: DateTime.utc(2026, 11, 10),
        syncReminderStartedAt: DateTime.utc(2026, 10, 20),
        backupDirectory: '/tmp/sao-luu',
        lastBackupAt: DateTime.utc(2026, 11, 6),
        syncHistory: [
          SyncHistoryEntry(
            at: DateTime.utc(2026, 11, 10),
            upload: true,
            success: true,
            version: FakeDatabaseSettingsRepository.remoteVersion,
            rows: 42,
            collections: 3,
          ),
        ],
      );
      await repo.save(settings);
      expect(jsonDecode(stored!)['sqlConnection'], settings.sqlConnection);
      expect((await repo.load()).mongoUri, settings.mongoUri);
      expect((await repo.load()).cloudUri, settings.cloudUri);
      expect((await repo.load()).databaseVersion?.version, 'local-hash');
      expect((await repo.load()).cloudVersion?.version, 'cloud-hash');
      expect((await repo.load()).lastSyncAt, settings.lastSyncAt);
      expect((await repo.load()).backupDirectory, '/tmp/sao-luu');
      expect((await repo.load()).lastBackupAt, settings.lastBackupAt);
      expect((await repo.load()).syncHistory.single.success, isTrue);
      expect((await repo.load()).syncHistory.single.rows, 42);
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
      expect(
        find.byKey(const ValueKey('settings-backup-mongo')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-restore-mongo')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-backup-directory')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-open-backup-directory')),
        findsOneWidget,
      );
      expect(find.textContaining('5 ngày'), findsOneWidget);
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
  test(
    'backup uses the saved database and a sale in progress blocks restore',
    () async {
      final repo = FakeDatabaseSettingsRepository();
      final controller = DatabaseSettingsController(repo);
      addTearDown(controller.dispose);
      await controller.load();
      await controller.backupNow();
      expect(repo.backups, 0);
      expect(controller.errorFor(SettingsSection.mongo), contains('thư mục'));
      await controller.saveBackupDirectory('/tmp/sao-luu');
      expect(repo.settings.backupDirectory, '/tmp/sao-luu');
      expect(repo.backups, 0);
      expect(repo.settings.lastBackupAt, isNull);
      expect(
        controller.messageFor(SettingsSection.mongo),
        'Đã lưu thư mục sao lưu.',
      );
      await controller.openBackupDirectory();
      expect(repo.openedBackupDirectory, '/tmp/sao-luu');
      await controller.backupNow();
      expect(repo.backups, 1);
      expect(repo.backupDirectory, '/tmp/sao-luu');
      expect(repo.settings.lastBackupAt, isNotNull);
      expect(
        controller.messageFor(SettingsSection.mongo),
        contains('Đã sao lưu'),
      );
      CartController.shared.add({
        'IdXe': 123,
        'IdSanPham': 1,
        'SoLuongTon': 1,
        'GiaBan': 100,
        'LoaiSanPham': 'xe',
      }, vehicle: true);
      await controller.restoreMongo('/tmp/sao-luu.zip');
      expect(repo.restores, 0);
      expect(controller.errorFor(SettingsSection.mongo), contains('khôi phục'));
      CartController.shared.clear();
      await controller.restoreMongo('/tmp/sao-luu.zip');
      expect(repo.restores, 1);
      expect(repo.restoreUri, repo.settings.mongoUri);
      expect(
        controller.messageFor(SettingsSection.mongo),
        contains('Đã khôi phục'),
      );
    },
  );
  test(
    'connection feedback is stored and cleared per settings section',
    () async {
      final repo = FakeDatabaseSettingsRepository()..failSql = true;
      final controller = DatabaseSettingsController(repo);
      addTearDown(controller.dispose);
      await controller.load();
      await controller.checkSql('Server=test;Database=xm;UID=u;PWD=p;');
      final sqlError = controller.errorFor(SettingsSection.sql);
      expect(sqlError, contains('SQL Server'));
      await controller.checkMongo('invalid');
      expect(controller.errorFor(SettingsSection.mongo), isNotNull);
      expect(controller.errorFor(SettingsSection.sql), sqlError);
      repo.status = const MongoInstallationStatus(
        installed: true,
        connected: true,
      );
      await controller.checkCloud('mongodb://cloud/XM');
      expect(
        controller.messageFor(SettingsSection.cloud),
        contains('Cloud thành công'),
      );
      expect(controller.messageFor(SettingsSection.mongo), isNull);
      expect(controller.errorFor(SettingsSection.sql), sqlError);
      repo.failSql = false;
      await controller.checkSql('Server=test;Database=xm;UID=u;PWD=p;');
      expect(controller.errorFor(SettingsSection.sql), isNull);
      expect(controller.errorFor(SettingsSection.mongo), isNotNull);
      expect(
        controller.messageFor(SettingsSection.cloud),
        contains('Cloud thành công'),
      );
    },
  );

  testWidgets(
    'SQL errors completing after switching tabs stay only in SQL tab',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _DelayedSqlRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SettingsTab(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'SQL Server'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-check-sql')));
      await tester.pump();
      await tester.tap(find.widgetWithText(Tab, 'MongoDB'));
      await tester.pump(const Duration(milliseconds: 400));
      repo.result.completeError(
        const DatabaseSettingsException('Lỗi SQL riêng của tab SQL'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Lỗi SQL riêng của tab SQL'), findsNothing);
      await tester.tap(find.widgetWithText(Tab, 'MongoDB Cloud'));
      await tester.pumpAndSettle();
      expect(find.text('Lỗi SQL riêng của tab SQL'), findsNothing);
      await tester.tap(find.widgetWithText(Tab, 'SQL Server'));
      await tester.pumpAndSettle();
      expect(find.text('Lỗi SQL riêng của tab SQL'), findsOneWidget);
      expect(tester.takeException(), isNull);
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

class _DelayedSqlRepository extends FakeDatabaseSettingsRepository {
  final result = Completer<int>();
  @override
  Future<int> checkSql(String connection) => result.future;
}
