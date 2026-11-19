// Verifies the database repair runner against an isolated MongoDB database.
import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/services/database_fix_service.dart';

int checks = 0;
void check(bool ok, String label) {
  if (!ok) throw StateError('FAIL: $label');
  checks++;
  stdout.writeln('PASS: $label');
}

Future<void> main() async {
  final uri =
      'mongodb://127.0.0.1:27017/QA_FIX_RUNNER_${DateTime.now().microsecondsSinceEpoch}';
  final db = Db(uri);
  await db.open();
  final service = DatabaseFixService(db, () async {});
  try {
    await db.runCommand({
      'create': 'FixDoc',
      'validator': {
        r'$jsonSchema': {
          'bsonType': 'object',
          'required': ['name', 'amount'],
          'properties': {
            'name': {'bsonType': 'string'},
            'amount': {'bsonType': 'int'},
          },
        },
      },
      'validationLevel': 'strict',
      'validationAction': 'error',
    });
    await db.collection('FixDoc').insertMany([
      {'_id': 1, 'name': 'a', 'amount': 10},
      {'_id': 2, 'name': 'b', 'amount': 20},
    ]);

    const updateScript =
        r'[{"collection":"FixDoc","filter":{"_id":1},'
        r'"update":{"$set":{"name":"a2"}},"note":"đổi tên"}]';
    final updatePlan = DatabaseFixService.parse(updateScript);
    final preview = await service.preview(updatePlan);
    check(preview.steps.single.matched == 1, 'Kiểm tra đếm đúng bản ghi khớp');
    check(preview.steps.single.note == 'đổi tên', 'Kiểm tra giữ ghi chú lệnh');
    check(
      (await db.collection('FixDoc').findOne({'_id': 1}))?['name'] == 'a',
      'Kiểm tra không ghi dữ liệu',
    );

    final updateRun = await service.execute(updatePlan, script: updateScript);
    check(
      updateRun.ok && updateRun.steps.single.modified == 1 && updateRun.wrote,
      'Thực thi update đúng số bản ghi',
    );
    check(
      (await db.collection('FixDoc').findOne({'_id': 1}))?['name'] == 'a2',
      'Update ghi đúng giá trị mới',
    );

    const insertScript =
        r'[{"collection":"FixDoc","insert":{"_id":3,"name":"c","amount":30,'
        r'"when":{"$date":"2026-11-19T00:00:00Z"}}}]';
    final insertRun = await service.execute(
      DatabaseFixService.parse(insertScript),
      script: insertScript,
    );
    final inserted = await db.collection('FixDoc').findOne({'_id': 3});
    check(
      insertRun.ok && insertRun.steps.single.inserted == 1,
      'Thực thi insert đúng số bản ghi',
    );
    check(
      inserted?['when'] == DateTime.utc(2026, 11, 19),
      'Chuyển \$date sang DateTime đúng',
    );

    const deleteScript =
        r'[{"collection":"FixDoc","filter":{"_id":3},"delete":true}]';
    final deleteRun = await service.execute(
      DatabaseFixService.parse(deleteScript),
      script: deleteScript,
    );
    check(
      deleteRun.ok &&
          deleteRun.steps.single.removed == 1 &&
          await db.collection('FixDoc').findOne({'_id': 3}) == null,
      'Thực thi delete đúng bản ghi',
    );

    const failingScript =
        r'[{"collection":"FixDoc","filter":{"_id":1},'
        r'"update":{"$set":{"name":"a3"}}},'
        r'{"collection":"FixDoc","filter":{"_id":2},'
        r'"update":{"$set":{"amount":"không phải số"}}}]';
    final failing = await service.execute(
      DatabaseFixService.parse(failingScript),
      script: failingScript,
    );
    check(
      !failing.ok &&
          failing.failedStep == 2 &&
          failing.steps.length == 2 &&
          !failing.steps.last.ok,
      'Dừng ở lỗi đầu tiên và giữ lệnh trước đã ghi',
    );
    check(
      (await db.collection('FixDoc').findOne({'_id': 1}))?['name'] == 'a3' &&
          (await db.collection('FixDoc').findOne({'_id': 2}))?['amount'] == 20,
      'Lệnh trước đã áp dụng, lệnh lỗi không làm thay đổi dữ liệu',
    );
    check(
      failing.steps.last.error?.contains('validation') == true,
      'Lỗi validator được trả về cho người dùng',
    );

    var rejected = false;
    try {
      await service.preview(
        DatabaseFixService.parse(
          '[{"collection":"KhongCo","filter":{"_id":1},"delete":true}]',
        ),
      );
    } on DatabaseFixFormatException {
      rejected = true;
    }
    check(rejected, 'Kiểm tra chặn collection không tồn tại');

    rejected = false;
    try {
      DatabaseFixService.parse(
        '[{"collection":"_sync_state","filter":{"_id":1},"delete":true}]',
      );
    } on DatabaseFixFormatException {
      rejected = true;
    }
    check(rejected, 'Từ chối sửa collection đồng bộ');

    check(
      await db.collection('_fix_history').count() == 4,
      'Mỗi lần chạy đều được lưu vào _fix_history',
    );
    final history = await db.collection('_fix_history').findOne({'Ok': false});
    check(
      history?['Results'] is List && history?['Script'] is String,
      'Lịch sử lưu lệnh, kết quả và trạng thái',
    );
    stdout.writeln('$checks checks passed.');
  } finally {
    await db.drop();
    await service.close();
  }
}
