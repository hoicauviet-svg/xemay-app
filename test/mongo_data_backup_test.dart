import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/models/settings/database_settings.dart';
import 'package:xemay_app/services/mongo_data_backup.dart';

void main() {
  test('a file that is not a backup is rejected', () async {
    final dir = await Directory.systemTemp.createTemp('xm-backup-bad-');
    try {
      final path = '${dir.path}/nope.zip';
      await File(path).writeAsString('khong phai zip');
      expect(
        () => MongoDataBackup.importFromFile(
          mongoUri: 'mongodb://127.0.0.1:27017/XM_backup_unused',
          path: path,
        ),
        throwsA(
          isA<DatabaseSettingsException>().having(
            (error) => error.message,
            'message',
            contains('không phải bản sao lưu'),
          ),
        ),
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('backup restores documents, indexes, validators and views', () async {
    final name = 'XM_backup_${DateTime.now().microsecondsSinceEpoch}';
    final uri = 'mongodb://127.0.0.1:27017/$name';
    final db = await Db.create(uri);
    await db.open();
    final dir = await Directory.systemTemp.createTemp('xm-backup-');
    try {
      await db.createCollection(
        'Xe',
        createCollectionOptions: CreateCollectionOptions(
          validator: {
            r'$jsonSchema': {
              'bsonType': 'object',
              'required': ['IdXe'],
            },
          },
          validationLevel: 'strict',
          validationAction: 'error',
        ),
      );
      final id = ObjectId();
      final when = DateTime.utc(2026, 11, 11, 8, 30);
      await db.collection('Xe').insertOne({
        '_id': id,
        'IdXe': 7,
        'Ngay': when,
        'Ten': 'Wave',
      });
      await db.createIndex(
        'Xe',
        keys: {'IdXe': 1},
        unique: true,
        name: 'IdXe_unique',
      );
      await db.createView('XeTen', 'Xe', [
        {
          r'$project': {'Ten': 1, 'IdXe': 1},
        },
      ]);
      final path = '${dir.path}/sao-luu.zip';
      final exported = await MongoDataBackup.exportToFile(
        mongoUri: uri,
        path: path,
      );
      expect(exported.database, name);
      expect(exported.collections, 2);
      expect(exported.rows, 1);

      await db.collection('Xe').deleteMany({'IdXe': 7});
      await db.collection('Rac').insertOne({'_id': 1, 'Ten': 'rac'});

      final restored = await MongoDataBackup.importFromFile(
        mongoUri: uri,
        path: path,
      );
      expect(restored.rows, 1);
      expect(restored.collections, 2);

      final document = await db.collection('Xe').findOne();
      expect(document!['Ten'], 'Wave');
      expect(document['IdXe'], 7);
      expect((document['_id'] as ObjectId).toHexString(), id.toHexString());
      expect((document['Ngay'] as DateTime).toUtc(), when);
      final view = await db.collection('XeTen').findOne();
      expect(view!['Ten'], 'Wave');
      final names = (await db.getCollectionInfos())
          .map((info) => info['name'])
          .toList();
      expect(names, contains('Xe'));
      expect(names, isNot(contains('Rac')));
      final indexes = await db.collection('Xe').getIndexes();
      expect(
        indexes.any(
          (index) => index['name'] == 'IdXe_unique' && index['unique'] == true,
        ),
        isTrue,
      );
      final invalid = await db.collection('Xe').insertOne({'Ten': 'thieu'});
      expect(invalid.hasWriteErrors, isTrue);
      final duplicate = await db.collection('Xe').insertOne({
        'IdXe': 7,
        'Ten': 'trung',
      });
      expect(duplicate.hasWriteErrors, isTrue);
      expect(await db.collection('Xe').count(), 1);
      final old = File('${dir.path}/SaoLuu_20000101_0000.zip');
      await old.writeAsString('cu');
      final note = File('${dir.path}/giu.txt');
      await note.writeAsString('giu');
      await MongoDataBackup.exportToDirectory(
        mongoUri: uri,
        directory: dir.path,
        now: DateTime(2026, 1, 2, 8, 5),
      );
      await MongoDataBackup.exportToDirectory(
        mongoUri: uri,
        directory: dir.path,
        now: DateTime(2026, 1, 8, 9, 15),
      );
      expect(old.existsSync(), isFalse);
      expect(note.existsSync(), isTrue);
      final backups = Directory(dir.path)
          .listSync()
          .whereType<File>()
          .map((file) => file.path.split(Platform.pathSeparator).last)
          .where((name) => name.startsWith('SaoLuu_'))
          .toList();
      expect(backups, ['SaoLuu_20260108_0915.zip']);
    } finally {
      await db.drop();
      await db.close();
      await dir.delete(recursive: true);
    }
  });
}
