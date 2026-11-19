import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongo_dart/mongo_dart.dart' show ObjectId;
import 'package:xemay_app/services/database_fix_service.dart';
import 'package:xemay_app/services/stuck_order_repair.dart';
import 'package:xemay_app/views/settings/database_fix_tab.dart';

class _Runner implements DatabaseFixRunner {
  int previews = 0, executions = 0, closes = 0;
  DatabaseFixPlan? lastPlan;
  @override
  Future<DatabaseFixPreview> preview(DatabaseFixPlan plan) async {
    previews++;
    lastPlan = plan;
    return DatabaseFixPreview(
      steps: [
        DatabaseFixPreviewStep(
          index: 1,
          collection: plan.operations.first.collection,
          action: plan.operations.first.action,
          matched: 1,
        ),
      ],
    );
  }

  @override
  Future<DatabaseFixRun> execute(
    DatabaseFixPlan plan, {
    required String script,
  }) async {
    executions++;
    lastPlan = plan;
    return DatabaseFixRun(
      ok: true,
      steps: [
        DatabaseFixStepResult(
          index: 1,
          collection: plan.operations.first.collection,
          action: plan.operations.first.action,
          ok: true,
          matched: 1,
          modified: 1,
        ),
      ],
      duration: const Duration(milliseconds: 5),
      wrote: true,
    );
  }

  @override
  Future<void> close() async => closes++;
}

class _StuckRunner implements StuckOrderRunner {
  int scans = 0, repairs = 0, closes = 0;
  @override
  Future<StuckOrderScan> scan() async {
    scans++;
    return StuckOrderScan(
      issues: [
        const StuckOrderIssue(
          orderId: 42,
          title: 'Kế hoạch sửa/xóa dở dang',
          details: ['Header lệch sổ nợ.'],
          actions: ['Hoàn tất kế hoạch và giải phóng khóa.'],
          fixable: true,
        ),
      ],
      checkedOrders: 1,
      pendingPlans: 1,
      staleLocks: 0,
      headerMismatches: 0,
      at: DateTime(2026, 11, 19),
    );
  }

  @override
  Future<StuckOrderRepairRun> repair() async {
    repairs++;
    return StuckOrderRepairRun(
      results: const [
        StuckOrderRepairResult(
          orderId: 42,
          ok: true,
          message: 'Đã sửa đơn #42.',
          fixed: true,
        ),
      ],
      scan: StuckOrderScan(
        issues: const [],
        checkedOrders: 1,
        pendingPlans: 0,
        staleLocks: 0,
        headerMismatches: 0,
        at: DateTime(2026, 11, 19),
      ),
    );
  }

  @override
  Future<void> close() async => closes++;
}

const _script =
    '[{"collection":"HoaDonBan","filter":{"IdHoaDon":7},'
    '"update":{"\$set":{"SoTienKhachDua":0}}}]';

const _stuckCommand =
    '{"description":"Quét và sửa đơn kẹt",'
    '"select":{"command":"stuck-orders"},'
    '"apply":{"command":"repair-stuck-orders"}}';

void main() {
  group('DatabaseFixService.parse', () {
    test('accepts a single operation object and normalizes values', () {
      final plan = DatabaseFixService.parse(
        '{"collection":"HoaDonBan","filter":{"IdHoaDon":7,'
        '"NgayHen":{"\$date":"2026-11-19T00:00:00Z"},'
        '"TraNoId":{"\$oid":"64b7f9a2e8e4744f01f7b7da"}},'
        '"update":{"\$set":{"TienThua":0}},"many":true,"note":" thử "}',
      );
      final operation = plan.operations.single;
      expect(operation.number, 1);
      expect(operation.collection, 'HoaDonBan');
      expect(operation.action, DatabaseFixAction.update);
      expect(operation.many, isTrue);
      expect(operation.upsert, isFalse);
      expect(operation.note, 'thử');
      expect(operation.filter['NgayHen'], DateTime.utc(2026, 11, 19));
      expect(
        operation.filter['TraNoId'],
        ObjectId.parse('64b7f9a2e8e4744f01f7b7da'),
      );
      expect(operation.update!['\$set'], {'TienThua': 0});
    });

    test('accepts an operations wrapper with description', () {
      final plan = DatabaseFixService.parse('''
        {
          "description": "Sửa hai phiếu",
          "operations": [
            {"collection":"TraNo","filter":{"_id":1},"delete":true,"many":true},
            {"collection":"TraNo","insert":{"_id":2,"SotienTra":1}}
          ]
        }
      ''');
      expect(plan.description, 'Sửa hai phiếu');
      expect(plan.operations.length, 2);
      expect(plan.operations[0].action, DatabaseFixAction.delete);
      expect(plan.operations[0].many, isTrue);
      expect(plan.operations[1].action, DatabaseFixAction.insert);
      expect(plan.operations[1].insert!['SotienTra'], 1);
    });

    test('the shipped stuck-order command file is valid', () {
      final plan = DatabaseFixService.parse(
        File('tool/fix_don_hang_ket.json').readAsStringSync(),
      );
      expect(plan.isStuckOrders, isTrue);
      expect(plan.description, contains('đơn hàng bị kẹt'));
    });

    test('accepts the stuck-orders command file', () {
      final plan = DatabaseFixService.parse(_stuckCommand);
      expect(plan.isStuckOrders, isTrue);
      expect(plan.operations, isEmpty);
      expect(plan.description, 'Quét và sửa đơn kẹt');
      expect(
        DatabaseFixService.parse('{"command":"stuck-orders"}').isStuckOrders,
        isTrue,
      );
    });

    test('rejects unknown select/apply commands', () {
      expect(
        () => DatabaseFixService.parse(
          '{"select":{"command":"other"},"apply":{"command":"repair-stuck-orders"}}',
        ),
        throwsA(isA<DatabaseFixFormatException>()),
      );
    });

    test('rejects an out-of-range \$date', () {
      expect(
        () => DatabaseFixService.parse(
          '{"collection":"HoaDonBan","filter":{"IdHoaDon":1},'
          '"update":{"\$set":{"NgayHen":{"\$date":100000000000000000000}}}}',
        ),
        throwsA(isA<DatabaseFixFormatException>()),
      );
    });

    test('reports invalid JSON with a line and column', () {
      expect(
        () => DatabaseFixService.parse('[\n  {"collection": }\n]'),
        throwsA(
          isA<DatabaseFixFormatException>().having(
            (error) => error.message,
            'message',
            allOf(contains('JSON không hợp lệ'), contains('dòng 2')),
          ),
        ),
      );
    });

    test('requires a concrete filter for update and delete', () {
      for (final body in [
        '{"collection":"HoaDonBan","update":{"\$set":{"GiamGia":0}}}',
        '{"collection":"HoaDonBan","delete":true}',
        '{"collection":"HoaDonBan","filter":{},"delete":true}',
      ]) {
        expect(
          () => DatabaseFixService.parse(body),
          throwsA(isA<DatabaseFixFormatException>()),
          reason: body,
        );
      }
    });

    test('rejects unknown update operators and fields', () {
      expect(
        () => DatabaseFixService.parse(
          '{"collection":"HoaDonBan","filter":{"IdHoaDon":1},'
          '"update":{"\$rename":{"a":"b"}}}',
        ),
        throwsA(isA<DatabaseFixFormatException>()),
      );
      expect(
        () => DatabaseFixService.parse(
          '{"collection":"HoaDonBan","filter":{"IdHoaDon":1},'
          '"update":{"\$set":{"_id":2}}}',
        ),
        throwsA(isA<DatabaseFixFormatException>()),
      );
      expect(
        () => DatabaseFixService.parse(
          '{"collection":"HoaDonBan","filter":{"IdHoaDon":1},'
          '"update":{"\$inc":{"GiamGia":"x"}}}',
        ),
        throwsA(isA<DatabaseFixFormatException>()),
      );
    });

    test('blocks sync and audit collections', () {
      for (final name in ['_sync_state', '_sync_changes', '_fix_history']) {
        expect(
          () => DatabaseFixService.parse(
            '{"collection":"$name","filter":{"_id":1},"delete":true}',
          ),
          throwsA(isA<DatabaseFixFormatException>()),
          reason: name,
        );
      }
    });

    test('rejects inserting into a collection with a filter', () {
      expect(
        () => DatabaseFixService.parse(
          '{"collection":"TraNo","filter":{"_id":1},"insert":{"_id":2}}',
        ),
        throwsA(isA<DatabaseFixFormatException>()),
      );
    });

    test('caps the number of operations', () {
      final operations = [
        for (var index = 0; index <= DatabaseFixService.maxOperations; index++)
          '{"collection":"TraNo","filter":{"_id":$index},"delete":true}',
      ].join(',');
      expect(
        () => DatabaseFixService.parse('[$operations]'),
        throwsA(isA<DatabaseFixFormatException>()),
      );
    });
  });

  testWidgets('preview and execute flow asks for confirmation', (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runner = _Runner();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DatabaseFixTab(
            runnerFactory: () => runner,
            stuckRunnerFactory: () => _StuckRunner(),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('fix-script')));
    await tester.enterText(find.byKey(const ValueKey('fix-script')), _script);
    await tester.ensureVisible(find.byKey(const ValueKey('fix-preview')));
    await tester.tap(find.byKey(const ValueKey('fix-preview')));
    await tester.pumpAndSettle();
    expect(runner.previews, 1);
    expect(find.textContaining('Kiểm tra: 1 lệnh'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('fix-execute')));
    await tester.pumpAndSettle();
    expect(find.text('Thực thi lệnh sửa dữ liệu?'), findsOneWidget);
    expect(runner.executions, 0);
    await tester.tap(find.byKey(const ValueKey('fix-confirm')));
    await tester.pumpAndSettle();
    expect(runner.executions, 1);
    expect(find.textContaining('Hoàn tất 1 lệnh'), findsOneWidget);
    expect(runner.closes, greaterThanOrEqualTo(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('stuck-orders command runs through preview and execute', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final stuck = _StuckRunner();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DatabaseFixTab(
            runnerFactory: () => _Runner(),
            stuckRunnerFactory: () => stuck,
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('fix-script')));
    await tester.enterText(
      find.byKey(const ValueKey('fix-script')),
      _stuckCommand,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('fix-preview')));
    await tester.tap(find.byKey(const ValueKey('fix-preview')));
    await tester.pumpAndSettle();
    expect(stuck.scans, 1);
    expect(stuck.repairs, 0);
    expect(find.textContaining('1 đơn cần xử lý'), findsOneWidget);
    expect(find.textContaining('#42 · Kế hoạch'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('fix-execute')));
    await tester.tap(find.byKey(const ValueKey('fix-execute')));
    await tester.pumpAndSettle();
    expect(stuck.scans, 2);
    expect(find.text('Thực thi sửa đơn kẹt?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('stuck-confirm')));
    await tester.pumpAndSettle();
    expect(stuck.repairs, 1);
    expect(find.textContaining('Đã sửa 1/1 đơn'), findsOneWidget);
    expect(find.text('Không còn đơn kẹt.'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fix tab adapts to a narrow window', (tester) async {
    tester.view.physicalSize = const Size(420, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DatabaseFixTab(runnerFactory: () => _Runner())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fix-script')), findsOneWidget);
    expect(find.byKey(const ValueKey('fix-execute')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid JSON never reaches the database runner', (tester) async {
    final runner = _Runner();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DatabaseFixTab(
            runnerFactory: () => runner,
            stuckRunnerFactory: () => _StuckRunner(),
          ),
        ),
      ),
    );
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.ensureVisible(find.byKey(const ValueKey('fix-script')));
    await tester.enterText(find.byKey(const ValueKey('fix-script')), '[');
    await tester.ensureVisible(find.byKey(const ValueKey('fix-preview')));
    await tester.tap(find.byKey(const ValueKey('fix-preview')));
    await tester.pumpAndSettle();
    expect(runner.previews, 0);
    expect(find.textContaining('JSON không hợp lệ'), findsOneWidget);
  });
}
