import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/models/directory/directory_models.dart';
import 'package:xemay_app/services/mongo_directory_repository.dart';

Future<void> main() async {
  final live = MongoDirectoryRepository();
  final dbName = 'XM_directory_test_${DateTime.now().microsecondsSinceEpoch}';
  final testUri = 'mongodb://127.0.0.1:27017/$dbName';
  final repository = MongoDirectoryRepository(uri: testUri);
  final inspection = Db(testUri);
  try {
    final partners = await live.fetch(DirectoryKind.partner);
    final carriers = await live.fetch(DirectoryKind.carrier);
    if (partners.isEmpty || carriers.isEmpty) {
      throw StateError('Thiếu danh mục đã chuyển');
    }
    final partner =
        DirectoryEntryDraft(DirectoryKind.partner, name: 'Đối tác kiểm thử')
          ..phone = '0900000000'
          ..address = 'Địa chỉ kiểm thử'
          ..taxCode = 'TEST-TAX'
          ..representative = 'Đại diện kiểm thử'
          ..notes = 'Ghi chú đối tác';
    final carrier =
        DirectoryEntryDraft(DirectoryKind.carrier, name: 'Vận chuyển kiểm thử')
          ..phone = '0900000001'
          ..plate = 'TEST-01'
          ..notes = 'Ghi chú vận chuyển';
    final p = await repository.create(partner);
    final v = await repository.create(carrier);
    await inspection.open();
    final savedP = await inspection.collection('DoiTac').findOne({'_id': p.id});
    final savedV = await inspection.collection('VanChuyen').findOne({
      '_id': v.id,
    });
    if (savedP?['MaSoThue'] != partner.taxCode ||
        savedP?['NguoiDaiDien'] != partner.representative ||
        savedP?['GhiChu'] != partner.notes ||
        savedP?['DiaChi'] != partner.address) {
      throw StateError('Trường đối tác lưu không đúng');
    }
    if (savedV?['BienSoXe'] != carrier.plate ||
        savedV?['GhiChu'] != carrier.notes ||
        savedV?['SoDienThoai'] != carrier.phone) {
      throw StateError('Trường vận chuyển lưu không đúng');
    }
    if ((await repository.fetch(DirectoryKind.partner)).single.id != p.id ||
        (await repository.fetch(DirectoryKind.carrier)).single.id != v.id) {
      throw StateError('Không đọc lại được bản ghi mới');
    }
    stdout.writeln(
      'PASS: ${partners.length} live partners and ${carriers.length} live carriers read; all create/read fields verified in isolated test database.',
    );
  } finally {
    await live.close();
    await repository.close();
    if (!inspection.isConnected) await inspection.open();
    await inspection.drop();
    await inspection.close();
  }
}
