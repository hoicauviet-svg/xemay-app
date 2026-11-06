import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/models/customers/customer_models.dart';
import 'package:xemay_app/models/directory/directory_models.dart';
import 'package:xemay_app/models/products/product_details.dart';
import 'package:xemay_app/models/services/service_models.dart';
import 'package:xemay_app/models/inventory/inventory_models.dart';
import 'package:xemay_app/services/mongo_customer_repository.dart';
import 'package:xemay_app/services/mongo_partner_repository.dart';
import 'package:xemay_app/services/mongo_product_details_repository.dart';
import 'package:xemay_app/services/mongo_service_repository.dart';
import 'package:xemay_app/services/mongo_inventory_repository.dart';

void check(bool ok, String message) {
  if (!ok) throw StateError(message);
  stdout.writeln('PASS: $message');
}

Future<void> rejected(Future<void> Function() action, String name) async {
  var failed = false;
  try {
    await action();
  } catch (_) {
    failed = true;
  }
  check(failed, name);
}

Future<void> main() async {
  final uri =
      'mongodb://127.0.0.1:27017/QA_CRUD_${DateTime.now().microsecondsSinceEpoch}';
  final db = Db(uri);
  await db.open();
  final customers = MongoCustomerRepository(uri: uri),
      directory = MongoPartnerRepository(uri: uri),
      products = MongoProductDetailsRepository(uri: uri),
      services = MongoServiceRepository(uri: uri),
      inventory = MongoInventoryRepository(uri: uri);
  try {
    final c = await customers.create(
      CustomerDraft()
        ..name = 'QA Khách'
        ..phone = '0900000001'
        ..address = 'Thôn cũ',
    );
    await db
        .collection('KhachHang')
        .updateOne(
          {'IdKH': c['IdKH']},
          {
            r'$set': {'IdXa': 1},
          },
        );
    final edited = await customers.update(
      c['IdKH'] as int,
      CustomerDraft()
        ..name = 'QA Khách sửa'
        ..phone = '0900000002'
        ..address = 'Thôn mới, Xã mới',
    );
    check(
      edited['_id'] == c['_id'] &&
          edited['IdKH'] == c['IdKH'] &&
          edited['DiaChiChiTiet'] == 'Thôn mới, Xã mới' &&
          edited['IdXa'] == null,
      'Customer updates keep ID and consolidate legacy address',
    );
    await db.collection('NoCu').insertOne({
      'Id': 1,
      'IdKH': '${c['IdKH']}',
      'SoCoNo': 100,
    });
    await rejected(
      () => customers.delete(edited),
      'Customer deletion protects legacy string links',
    );
    await db.collection('NoCu').deleteMany({});
    await customers.delete(edited);
    check(
      (await customers.fetch(search: 'QA')).total == 0 &&
          await db.collection('KhachHang').count() == 1,
      'Customer delete hides recoverably',
    );
    await rejected(() async {
      await customers.update(
        c['IdKH'] as int,
        CustomerDraft()..name = 'Restore?',
      );
    }, 'Deleted customer cannot be updated accidentally');
    for (final kind in DirectoryKind.values) {
      final d = await directory.create(
        DirectoryEntryDraft(kind)
          ..name = 'QA ${kind.name}'
          ..phone = '0901'
          ..address = 'Địa chỉ'
          ..taxCode = 'TAX'
          ..representative = 'Đại diện'
          ..plate = 'QA-01'
          ..notes = 'Ghi chú',
      );
      await db.collection('NhapHang').insertOne({
        'IdNhapHang': kind.index + 1,
        kind == DirectoryKind.partner ? 'IdDoiTac' : 'IdVanChuyen': d.id,
        'SoTien': 1000,
        'SoTienConNo': 500,
      });
      final saved = await directory.update(
        d.id,
        DirectoryEntryDraft(kind)
          ..name = 'QA Updated ${kind.name}'
          ..phone = '0902'
          ..address = 'Địa chỉ mới'
          ..taxCode = 'TAX2'
          ..representative = 'Đại diện mới'
          ..plate = 'QA-02'
          ..notes = 'Ghi chú mới',
      );
      check(
        saved.id == d.id &&
            saved.phone == '0902' &&
            (kind == DirectoryKind.partner
                ? saved.taxCode == 'TAX2' && saved.address == 'Địa chỉ mới'
                : saved.plate == 'QA-02'),
        'Directory update all fields ${kind.name}',
      );
      await directory.delete(saved);
      check(
        (await directory.fetch(kind)).isEmpty,
        'Directory deleted entries excluded from pickers ${kind.name}',
      );
      final table = kind == DirectoryKind.partner ? 'DoiTac' : 'VanChuyen';
      check(
        (await db.collection(table).findOne({'_id': d.id}))?['DaXoa'] == true &&
            await db.collection('NhapHang').count() == kind.index + 1,
        'Directory delete preserves linked receipt history ${kind.name}',
      );
      if (kind == DirectoryKind.partner) {
        check(
          (await directory.fetchPartners()).total == 0,
          'Partner list excludes archived entries',
        );
      }
      await rejected(() async {
        await directory.update(
          d.id,
          DirectoryEntryDraft(kind)..name = 'Restore?',
        );
      }, 'Deleted directory cannot be updated ${kind.name}');
    }
    await db.collection('Xe').insertOne({
      'IdXe': 1,
      'IdSanPham': 10,
      'TenXe': 'QA Xe',
      'TinhTrang': true,
      'TinhTrangXe': 'moi',
      'GiaNhap': 20000000,
      'GiaBan': 25000000,
    });
    await db.collection('XeMoi').insertOne({
      'IdXe': 1,
      'SoKhung': 'OLD',
      'SoMay': 'OLD',
    });
    const v = ProductReference(id: 1, vehicle: true);
    var details = await products.load(v);
    final draft = ProductEditDraft.fromInformation(details.information, true)
      ..name = 'Xe sửa'
      ..frame = 'FRAME-NEW'
      ..engine = 'ENGINE-NEW'
      ..plate = 'QA-NEW'
      ..salePrice = '26000000'
      ..notes = 'Ghi chú mới';
    await products.update(v, draft);
    details = await products.load(v);
    check(
      details.information['TenXe'] == 'Xe sửa' &&
          details.information['SoKhung'] == 'FRAME-NEW' &&
          details.information['BienSo'] == 'QA-NEW' &&
          details.information['GiaBan'] == 26000000 &&
          details.information['GiaNhap'] == 20000000,
      'Vehicle updates serials/name/price without changing purchase price',
    );
    await db.collection('ChiTietNhapHang').insertOne({
      'IdNhapHang': 99,
      'IdXe': 1,
      'IdSanPham': 10,
      'SoLuong': 1,
      'GiaNhap': 20000000,
    });
    await rejected(
      () => products.delete(v),
      'Product deletion protects receipt links',
    );
    await db.collection('ChiTietNhapHang').deleteMany({});
    await db
        .collection('Xe')
        .updateOne(
          {'IdXe': 1},
          {
            r'$set': {'TinhTrang': false},
          },
        );
    draft.salePrice = '27000000';
    await rejected(
      () => products.update(v, draft),
      'Sold vehicle historical price cannot be rewritten',
    );
    await db
        .collection('Xe')
        .updateOne(
          {'IdXe': 1},
          {
            r'$set': {'TinhTrang': true},
          },
        );
    await products.delete(v);
    await db.collection('_sql_metadata').insertOne({
      '_id': 'product_schema_v2',
    });
    await inventory.connect();
    check(
      (await inventory.fetch(InventorySection.vehicles)).total == 0,
      'Deleted vehicle excluded from inventory list',
    );
    await db.collection('SanPham').insertMany([
      {
        'IdSanPham': 20,
        'LoaiSanPham': 'phu_tung',
        'TenSanPham': 'QA Part',
        'MaSanPham': 'P20',
        'DonViTinh': 'cái',
        'GiaBanThamKhao': 100,
      },
      {
        'IdSanPham': 21,
        'LoaiSanPham': 'phu_tung',
        'TenSanPham': 'Other',
        'MaSanPham': 'P21',
      },
    ]);
    await db.collection('TonKhoPhuTung').insertOne({
      'IdSanPham': 20,
      'SoLuongTon': 1,
    });
    const part = ProductReference(id: 20, vehicle: false);
    final pd = ProductEditDraft.fromInformation(
      (await products.load(part)).information,
      false,
    )..code = 'P21';
    await rejected(
      () => products.update(part, pd),
      'Part duplicate code rejected',
    );
    pd.code = 'P20NEW';
    pd.name = 'Phụ tùng sửa';
    pd.unit = 'bộ';
    pd.salePrice = '500';
    await products.update(part, pd);
    check(
      (await products.load(part)).information['DonViTinh'] == 'bộ',
      'Part fields updated',
    );
    await rejected(() => products.delete(part), 'Part stock prevents delete');
    await db
        .collection('TonKhoPhuTung')
        .updateOne(
          {'IdSanPham': 20},
          {
            r'$set': {'SoLuongTon': 0},
          },
        );
    await products.delete(part);
    check(
      (await db.collection('SanPham').findOne({'IdSanPham': 20}))?['DaXoa'] ==
          true,
      'Unused zero-stock part archived',
    );
    final svc = await services.create(
      ServiceDraft()
        ..name = 'QA Service'
        ..price = '100'
        ..description = 'Old',
    );
    await db.collection('ChiTietHoaDonBan').insertOne({
      'IdDichVu': svc.id,
      'TenSanPham': 'QA Service',
      'DonGia': 100,
    });
    await services.update(
      svc.id,
      ServiceDraft()
        ..name = 'Updated'
        ..price = '200'
        ..description = 'New',
    );
    await services.delete(svc.id);
    check(
      (await services.fetch()).total == 0 &&
          await db.collection('ChiTietHoaDonBan').count({'IdDichVu': svc.id}) ==
              1,
      'Service update/delete preserves historical sale',
    );
    stdout.writeln('PASS: CRUD integration complete; test database removed.');
  } finally {
    await customers.close();
    await directory.close();
    await products.close();
    await services.close();
    await inventory.close();
    await db.drop();
    await db.close();
  }
}
