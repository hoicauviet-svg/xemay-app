import 'dart:async';
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
      await controller.compareCloud(upload: true);
      await controller.syncCloud(upload: true);
      expect(repo.syncSource, local);
      expect(repo.syncTarget, 'mongodb://cloud:27017/XM');
      expect(controller.settings.mongoUri, '$local-sync');
      expect(
        controller.settings.databaseVersion?.label,
        controller.settings.cloudVersion?.label,
      );
      expect(controller.settings.cloudUri, 'mongodb://cloud:27017/XM-sync');
      await controller.compareCloud(upload: false);
      await controller.syncCloud(upload: false);
      expect(repo.syncSource, 'mongodb://cloud:27017/XM-sync');
      expect(repo.syncTarget, '$local-sync');
      expect(controller.settings.mongoUri, '$local-sync-sync');
      expect(
        controller.settings.databaseVersion?.label,
        controller.settings.cloudVersion?.label,
      );
      expect(controller.settings.syncHistory.length, 2);
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
      await controller.compareCloud(upload: false);
      await controller.syncCloud(upload: false);
      expect(controller.error, isNotNull);
      expect(repo.saves, 2);
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

  test(
    'conflicts need explicit choice and preview is consumed after a merge',
    () async {
      final repo = FakeDatabaseSettingsRepository()
        ..settings = const DatabaseSettings(
          mongoUri: 'mongodb://local/XM',
          cloudUri: 'mongodb://cloud/XM',
        )
        ..conflicts = 2;
      final controller = DatabaseSettingsController(repo);
      addTearDown(controller.dispose);
      await controller.load();
      await controller.syncCloud(upload: true);
      expect(repo.syncs, 0);
      expect(controller.error, contains('So sánh'));
      await controller.compareCloud(upload: true);
      expect(controller.settings.databaseVersion?.version, 'local-hash');
      expect(controller.settings.cloudVersion?.version, 'cloud-hash');
      await controller.checkSql(repo.settings.sqlConnection, save: true);
      expect(controller.settings.databaseVersion?.version, 'local-hash');
      await controller.syncCloud(upload: true);
      expect(repo.syncs, 0);
      expect(controller.error, contains('xung đột'));
      await controller.syncCloud(upload: true, conflictPolicy: 'target');
      expect(repo.syncs, 1);
      expect(repo.policy, 'target');
      expect(controller.comparison, isNull);
      await controller.syncCloud(upload: true);
      expect(repo.syncs, 1);
    },
  );

  testWidgets('comparison displays live table progress and elapsed time', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = _SlowComparisonRepository()
      ..settings = const DatabaseSettings(
        mongoUri: 'mongodb://local/XM',
        cloudUri: 'mongodb://cloud/XM',
      );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SettingsTab(repository: repo, initialTab: 2)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('settings-compare-cloud')),
    );
    await tester.tap(find.byKey(const ValueKey('settings-compare-cloud')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('2/34 bảng'), findsOneWidget);
    expect(find.textContaining('Đã chạy'), findsOneWidget);
    repo.result.complete(
      const CloudComparison(
        sourceVersion: FakeDatabaseSettingsRepository.localVersion,
        targetVersion: FakeDatabaseSettingsRepository.remoteVersion,
        sourceOnly: 1,
        targetOnly: 1,
        conflicts: 0,
        schemaConflicts: 0,
        identical: 0,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Đã chạy'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cloud history and compact controls fit a narrow window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeDatabaseSettingsRepository()
      ..settings = DatabaseSettings(
        mongoUri: 'mongodb://local/XM',
        cloudUri: 'mongodb://cloud/XM',
        databaseVersion: FakeDatabaseSettingsRepository.remoteVersion,
        cloudVersion: FakeDatabaseSettingsRepository.remoteVersion,
        lastSyncAt: DateTime.utc(2026, 11, 10),
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
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SettingsTab(repository: repo, initialTab: 2)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('settings-sync-history')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Đồng bộ lên cloud · Thành công'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('conflict dialog blocks confirmation until a side is selected', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1300, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeDatabaseSettingsRepository()
      ..settings = const DatabaseSettings(
        mongoUri: 'mongodb://local/XM',
        cloudUri: 'mongodb://cloud/XM',
      )
      ..conflicts = 2;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SettingsTab(repository: repo)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'MongoDB Cloud'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('settings-upload-cloud')),
    );
    await tester.tap(find.byKey(const ValueKey('settings-upload-cloud')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Khác nội dung cùng khóa: 2'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Tiếp tục'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('settings-conflict-policy')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ưu tiên dữ liệu trên máy').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();
    expect(repo.policy, 'source');
    expect(tester.takeException(), isNull);
  });

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

class _SlowComparisonRepository extends FakeDatabaseSettingsRepository {
  final result = Completer<CloudComparison>();
  @override
  Future<CloudComparison> compareCloud({
    required String sourceUri,
    required String targetUri,
    void Function(String)? progress,
  }) {
    progress?.call('Phía đích: 2/34 bảng — KhachHang: 10.000 dòng');
    return result.future;
  }
}
