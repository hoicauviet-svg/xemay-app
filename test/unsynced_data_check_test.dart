import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/controllers/database_settings_controller.dart';
import 'package:xemay_app/models/settings/database_settings.dart';
import 'package:xemay_app/services/unsynced_data_check.dart';
import 'package:xemay_app/views/dashboard/sync_progress_bar.dart';
import 'package:xemay_app/views/settings/unsynced_data_toast.dart';
import 'support/fake_database_settings_repository.dart';

CloudComparison _comparison({
  int sourceOnly = 0,
  int targetOnly = 0,
  int conflicts = 0,
  int schemaConflicts = 0,
  int pendingChanges = 0,
  String source = 'same',
  String target = 'same',
}) => CloudComparison(
  sourceVersion: DatabaseVersion(
    version: source,
    revision: 1,
    observedAt: '2026-11-14T00:00:00Z',
    rows: 1,
    collections: 1,
  ),
  targetVersion: DatabaseVersion(
    version: target,
    revision: 1,
    observedAt: '2026-11-14T00:00:00Z',
    rows: 1,
    collections: 1,
  ),
  sourceOnly: sourceOnly,
  targetOnly: targetOnly,
  conflicts: conflicts,
  schemaConflicts: schemaConflicts,
  identical: 0,
  pendingChanges: pendingChanges,
);

class _CompareRepo extends FakeDatabaseSettingsRepository {
  _CompareRepo(this.comparison);
  final CloudComparison comparison;
  int compares = 0;
  String? source;
  String? target;
  @override
  Future<CloudComparison> compareCloud({
    required String sourceUri,
    required String targetUri,
    void Function(String)? progress,
  }) async {
    compares++;
    source = sourceUri;
    target = targetUri;
    return comparison;
  }
}

void main() {
  test('skips the hidden check when cloud is not configured', () async {
    final repo = _CompareRepo(_comparison());
    expect(await UnsyncedDataCheck(repo).pendingComparison(), isNull);
    expect(repo.compares, 0);
  });

  test('reports unsynced journal or document changes', () async {
    final repo = _CompareRepo(_comparison(pendingChanges: 2))
      ..settings = const DatabaseSettings(
        mongoUri: 'mongodb://local/XM',
        cloudUri: 'mongodb://cloud/XM',
      );
    expect(await UnsyncedDataCheck(repo).pendingComparison(), isNotNull);
    expect(repo.source, 'mongodb://local/XM');
    expect(repo.target, 'mongodb://cloud/XM');
    expect(_comparison().needsSync, isFalse);
    expect(_comparison(sourceOnly: 1).needsSync, isTrue);
    expect(_comparison(targetOnly: 1).needsSync, isTrue);
    expect(_comparison(conflicts: 1).needsSync, isTrue);
    expect(_comparison(schemaConflicts: 1).needsSync, isTrue);
  });

  testWidgets('toast asks for sync and opens the requested action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () =>
                  showUnsyncedDataToast(context, onSync: () => opened = true),
              child: const Text('Hiện toast'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Hiện toast'));
    await tester.pumpAndSettle();
    expect(
      find.text('Có dữ liệu chưa đồng bộ. Hãy đồng bộ với MongoDB Cloud.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Đồng bộ'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
    expect(
      find.text('Có dữ liệu chưa đồng bộ. Hãy đồng bộ với MongoDB Cloud.'),
      findsNothing,
    );
    opened = false;
    await tester.tap(find.text('Hiện toast'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Bỏ qua'));
    await tester.pumpAndSettle();
    expect(opened, isFalse);
    expect(
      find.text('Có dữ liệu chưa đồng bộ. Hãy đồng bộ với MongoDB Cloud.'),
      findsNothing,
    );
  });

  test('staged comparison starts the sync immediately', () async {
    final preview = _comparison(
      sourceOnly: 1,
      source: 'local',
      target: 'cloud',
    );
    final repo = _CompareRepo(preview)
      ..settings = const DatabaseSettings(
        mongoUri: 'mongodb://local/XM',
        cloudUri: 'mongodb://cloud/XM',
      );
    final controller = DatabaseSettingsController(repo);
    addTearDown(controller.dispose);
    final lines = <String>[];
    controller.addListener(() {
      if (controller.progress.isNotEmpty) lines.add(controller.progress.last);
    });
    await controller.load();
    controller.stageComparison(preview, upload: true);
    await controller.syncCloud(upload: true, conflictPolicy: 'abort');
    expect(controller.error, isNull);
    expect(repo.syncs, 1);
    expect(repo.syncSource, 'mongodb://local/XM');
    expect(repo.syncTarget, 'mongodb://cloud/XM');
    expect(lines, contains('Đã đối chiếu dữ liệu'));
  });

  testWidgets('sync progress bar can be dismissed while active', (
    tester,
  ) async {
    var dismissed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SyncProgressBar(
            active: true,
            message: 'Đang đồng bộ dữ liệu…',
            onClose: () => dismissed = true,
          ),
        ),
      ),
    );
    expect(find.widgetWithText(TextButton, 'Bỏ qua'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Bỏ qua'));
    expect(dismissed, isTrue);
  });

  testWidgets('progress bar is the last item and shows the current step', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(child: Text('Nội dung')),
              SyncProgressBar(active: true, message: 'Đang gộp dữ liệu'),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Đang gộp dữ liệu'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(SyncProgressBar)).dy,
      greaterThan(tester.getTopLeft(find.text('Nội dung')).dy),
    );
  });
}
