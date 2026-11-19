// Verifies the stuck-order scanner/repair against an isolated MongoDB database
// using the deployed HoaDonBan validator.
import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/services/stuck_order_repair.dart';
import 'check_sale_payment_delete.dart' show saleHeaderValidator;

int checks = 0;
void check(bool ok, String label) {
  if (!ok) throw StateError('FAIL: $label');
  checks++;
  stdout.writeln('PASS: $label');
}

Future<void> main() async {
  final uri =
      'mongodb://127.0.0.1:27017/QA_STUCK_REPAIR_${DateTime.now().microsecondsSinceEpoch}';
  final db = Db(uri);
  await db.open();
  final service = StuckOrderRepair(db, () async {});
  Future<Map<String, dynamic>> get(String name, dynamic id) async =>
      (await db.collection(name).findOne({'_id': id}))!;
  Future<void> put(String name, Map<String, dynamic> row) async {
    await db.collection(name).insertOne(row);
  }

  final sale = DateTime.utc(2026, 10, 1);
  final due = DateTime.utc(2026, 11, 1);
  Map<String, dynamic> header({
    required String id,
    required int orderId,
    required int paid,
    required int cash,
    required int change,
    required int dueAmount,
  }) => {
    '_id': id,
    'IdHoaDon': orderId,
    'IdKH': 1,
    'IdSoNo': orderId,
    'TongTienHang': 10000000,
    'GiamGia': 0,
    'TongThanhToan': 10000000,
    'SoTienKhachDua': cash,
    'SoTienDaTra': paid,
    'SoTienConNo': dueAmount,
    'TienThua': change,
    'PhienBanBanHang': 3,
    'PhienBanNgayCongNo': 1,
    'MaYeuCauLuu': 'req-$orderId',
    'TrangThaiLuu': 'da_luu',
    'NgayMua': sale,
    'NgayHen': due,
    'NgayTinhLai': sale,
  };

  try {
    await db.runCommand({
      'create': 'HoaDonBan',
      'validator': saleHeaderValidator(),
      'validationLevel': 'strict',
      'validationAction': 'error',
    });
    await put('KhachHang', {
      '_id': 'c',
      'IdKH': 1,
      'TenKhachHang': 'Khách thử',
    });

    // 1. Half-applied payment delete: plan pending, header still old.
    final plan1 = ObjectId().oid;
    await put(
      'HoaDonBan',
      header(
        id: 'sale1',
        orderId: 1,
        paid: 10000000,
        cash: 10020000,
        change: 20000,
        dueAmount: 0,
      ),
    );
    await put('SoNo', {
      '_id': 'debt1',
      'IdSoNo': 1,
      'IdHoaDon': 1,
      'SoTienDaTra': 0,
      'SoTienConNo': 10000000,
    });
    await put('_record_changes', {
      '_id': plan1,
      'Kind': 'order',
      'Parent': 1,
      'State': 'pending',
      'Date': DateTime.now().toUtc(),
      'DeleteParent': false,
      'Operations': [
        {
          'Collection': 'SoNo',
          'Id': 'debt1',
          'Fields': {'SoTienDaTra': 0, 'SoTienConNo': 10000000},
          'Unset': <String>[],
        },
        {
          'Collection': 'TraNo',
          'Id': 'sale:1:payment',
          'Fields': null,
          'Unset': <String>[],
        },
        {
          'Collection': 'HoaDonBan',
          'Id': 'sale1',
          'Fields': {
            'SoTienDaTra': 0,
            'SoTienConNo': 10000000,
            'SoTienKhachDua': 20000,
          },
          'Unset': <String>[],
        },
      ],
      'Locks': [
        {'Collection': 'HoaDonBan', 'Id': 'sale1'},
        {'Collection': 'SoNo', 'Id': 'debt1'},
      ],
    });
    await db
        .collection('HoaDonBan')
        .updateOne(
          {'_id': 'sale1'},
          {
            r'$set': {'SuaXoaDangLuu': plan1},
          },
        );
    await db
        .collection('SoNo')
        .updateOne(
          {'_id': 'debt1'},
          {
            r'$set': {'SuaXoaDangLuu': plan1},
          },
        );

    // 2. Header no longer matches the debt book, without a plan.
    await put(
      'HoaDonBan',
      header(
        id: 'sale2',
        orderId: 2,
        paid: 10000000,
        cash: 10000000,
        change: 0,
        dueAmount: 0,
      ),
    );
    await put('SoNo', {
      '_id': 'debt2',
      'IdSoNo': 2,
      'IdHoaDon': 2,
      'SoTienDaTra': 0,
      'SoTienConNo': 10000000,
    });

    // 3. A pending delete plan must not be auto-completed.
    final plan3 = ObjectId().oid;
    await put(
      'HoaDonBan',
      header(
        id: 'sale3',
        orderId: 3,
        paid: 10000000,
        cash: 10000000,
        change: 0,
        dueAmount: 0,
      ),
    );
    await put('SoNo', {
      '_id': 'debt3',
      'IdSoNo': 3,
      'IdHoaDon': 3,
      'SoTienDaTra': 10000000,
      'SoTienConNo': 0,
    });
    await put('_record_changes', {
      '_id': plan3,
      'Kind': 'order',
      'Parent': 3,
      'State': 'pending',
      'Date': DateTime.now().toUtc(),
      'DeleteParent': true,
      'Operations': [
        {
          'Collection': 'HoaDonBan',
          'Id': 'sale3',
          'Fields': null,
          'Unset': <String>[],
        },
      ],
      'Locks': [
        {'Collection': 'HoaDonBan', 'Id': 'sale3'},
      ],
    });
    await db
        .collection('HoaDonBan')
        .updateOne(
          {'_id': 'sale3'},
          {
            r'$set': {'SuaXoaDangLuu': plan3},
          },
        );

    // 4. A stale lock with no plan.
    await put(
      'HoaDonBan',
      header(
        id: 'sale4',
        orderId: 4,
        paid: 10000000,
        cash: 10000000,
        change: 0,
        dueAmount: 0,
      ),
    );
    await put('SoNo', {
      '_id': 'debt4',
      'IdSoNo': 4,
      'IdHoaDon': 4,
      'SoTienDaTra': 10000000,
      'SoTienConNo': 0,
    });
    await db
        .collection('HoaDonBan')
        .updateOne(
          {'_id': 'sale4'},
          {
            r'$set': {'SuaXoaDangLuu': 'orphan-lock'},
          },
        );

    final scan = await service.scan();
    check(
      scan.checkedOrders == 4 &&
          scan.pendingPlans == 2 &&
          scan.staleLocks == 1 &&
          scan.headerMismatches == 1,
      'Quét đếm đúng kế hoạch, khóa sót và header lệch',
    );
    check(scan.issues.length == 4, 'Phát hiện đủ 4 đơn cần xử lý');
    final issue = {for (final item in scan.issues) item.orderId: item};
    check(
      issue[1]!.fixable && issue[2]!.fixable && issue[4]!.fixable,
      'Đơn có kế hoạch dở, header lệch và khóa sót đều sửa được',
    );
    check(
      issue[3]!.fixable == false && issue[3]!.blocker != null,
      'Kế hoạch xóa đơn bị chặn khỏi sửa tự động',
    );
    check(
      (await get('HoaDonBan', 'sale1'))['SuaXoaDangLuu'] == plan1,
      'Quét không thay đổi dữ liệu',
    );

    final run = await service.repair();
    check(
      run.results.length == 3 &&
          run.results.every((result) => result.ok) &&
          run.wrote,
      'Sửa 3 đơn sửa được và bỏ qua đơn xóa',
    );
    check(
      run.scan.issues.length == 1 && !run.scan.issues.single.fixable,
      'Sau khi sửa chỉ còn đơn xóa cần xử lý tay',
    );
    final fixed1 = await get('HoaDonBan', 'sale1');
    check(
      fixed1['SoTienDaTra'] == 0 &&
          fixed1['SoTienConNo'] == 10000000 &&
          fixed1['SoTienKhachDua'] == 0 &&
          fixed1['TienThua'] == 0,
      'Đơn 1: header khớp sổ nợ và tiền thừa hợp lệ',
    );
    check(
      fixed1['SuaXoaDangLuu'] == null &&
          (await get('SoNo', 'debt1'))['SuaXoaDangLuu'] == null,
      'Đơn 1: giải phóng khóa header và sổ nợ',
    );
    final finished = await get('_record_changes', plan1);
    check(
      finished['State'] == 'done' && finished['Released'] == true,
      'Đơn 1: kế hoạch được hoàn tất',
    );
    final fixed2 = await get('HoaDonBan', 'sale2');
    check(
      fixed2['SoTienDaTra'] == 0 &&
          fixed2['SoTienConNo'] == 10000000 &&
          fixed2['SoTienKhachDua'] == 0,
      'Đơn 2: header lệch sổ nợ được cập nhật',
    );
    check(
      (await get('HoaDonBan', 'sale4'))['SuaXoaDangLuu'] == null,
      'Đơn 4: khóa còn sót được xóa',
    );
    check(
      (await get('HoaDonBan', 'sale3'))['SuaXoaDangLuu'] == plan3 &&
          (await get('_record_changes', plan3))['State'] == 'pending',
      'Đơn 3: kế hoạch xóa và khóa được giữ nguyên',
    );
    check(
      await db.collection('_fix_history').count() == 1,
      'Lần sửa được ghi vào _fix_history',
    );

    // 5. A document created before the validator may hold integral doubles.
    //    MongoDB rejects the whole document unless the update normalizes them.
    final plan5 = ObjectId().oid;
    await db.collection('HoaDonBan').insertOne({
      '_id': 'sale5',
      'IdHoaDon': 5.0,
      'IdKH': 1.0,
      'IdSoNo': 5,
      'TongTienHang': 10000000.0,
      'GiamGia': 0.0,
      'TongThanhToan': 10000000.0,
      'SoTienKhachDua': 10020000.0,
      'SoTienDaTra': 10000000.0,
      'SoTienConNo': 0.0,
      'TienThua': 20000.0,
      'PhienBanBanHang': 3,
      'PhienBanNgayCongNo': 1,
      'MaYeuCauLuu': 'req-5',
      'TrangThaiLuu': 'da_luu',
      'NgayMua': sale,
      'NgayHen': due,
      'NgayTinhLai': sale,
    }, bypassDocumentValidation: true);
    await put('SoNo', {
      '_id': 'debt5',
      'IdSoNo': 5,
      'IdHoaDon': 5,
      'SoTienDaTra': 0,
      'SoTienConNo': 10000000,
    });
    await put('_record_changes', {
      '_id': plan5,
      'Kind': 'order',
      'Parent': 5,
      'State': 'pending',
      'Date': DateTime.now().toUtc(),
      'DeleteParent': false,
      'Operations': [
        {
          'Collection': 'SoNo',
          'Id': 'debt5',
          'Fields': {'SoTienDaTra': 0, 'SoTienConNo': 10000000},
          'Unset': <String>[],
        },
        {
          'Collection': 'HoaDonBan',
          'Id': 'sale5',
          'Fields': {
            'SoTienDaTra': 0,
            'SoTienConNo': 10000000,
            'SoTienKhachDua': 20000,
          },
          'Unset': <String>[],
        },
      ],
      'Locks': [
        {'Collection': 'HoaDonBan', 'Id': 'sale5'},
        {'Collection': 'SoNo', 'Id': 'debt5'},
      ],
    });
    await db
        .collection('HoaDonBan')
        .updateOne(
          {'_id': 'sale5'},
          {
            r'$set': {'SuaXoaDangLuu': plan5},
          },
        );
    await db
        .collection('SoNo')
        .updateOne(
          {'_id': 'debt5'},
          {
            r'$set': {'SuaXoaDangLuu': plan5},
          },
        );
    final scan5 = await service.scan();
    final issue5 = scan5.issues.where((item) => item.orderId == 5).toList();
    check(
      issue5.length == 1 && issue5.single.fixable,
      'Đơn có trường kiểu double vẫn được nhận là sửa được',
    );
    final run5 = await service.repair();
    check(
      run5.results.any(
        (result) => result.orderId == 5 && result.ok && result.fixed,
      ),
      'Sửa được đơn có trường tiền/Id kiểu double',
    );
    final fixed5 = await get('HoaDonBan', 'sale5');
    check(
      fixed5['TongTienHang'] is int &&
          fixed5['GiamGia'] is int &&
          fixed5['TongThanhToan'] is int &&
          fixed5['SoTienDaTra'] is int &&
          fixed5['SoTienConNo'] is int &&
          fixed5['SoTienKhachDua'] is int &&
          fixed5['TienThua'] is int &&
          fixed5['IdKH'] is int &&
          fixed5['IdHoaDon'] is int,
      'Các trường validator được chuẩn hóa từ double sang int',
    );
    check(
      fixed5['SoTienDaTra'] == 0 &&
          fixed5['SoTienConNo'] == 10000000 &&
          fixed5['SoTienKhachDua'] == 0 &&
          fixed5['TienThua'] == 0,
      'Header sau chuẩn hóa vẫn đúng số liệu',
    );
    final finished5 = await get('_record_changes', plan5);
    check(
      finished5['State'] == 'done' &&
          finished5['Released'] == true &&
          fixed5['SuaXoaDangLuu'] == null,
      'Kế hoạch double được hoàn tất và giải phóng khóa',
    );
    check(
      await db.collection('_fix_history').count() == 2,
      'Lần sửa double được ghi lịch sử',
    );
    stdout.writeln('$checks checks passed.');
  } finally {
    await db.drop();
    await service.close();
  }
}
