import 'package:xemay_app/models/products/product_details.dart';
import 'package:xemay_app/services/mongo_product_details_repository.dart';
import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/models/finance/cash_category.dart';
import 'package:xemay_app/models/finance/finance_models.dart';
import 'package:xemay_app/services/mongo_finance_repository.dart';
import 'package:xemay_app/services/mongo_product_cash.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  final uri =
      'mongodb://127.0.0.1:27017/XM_cash_categories_test_${DateTime.now().microsecondsSinceEpoch}';
  final db = Db(uri);
  final repo = MongoFinanceRepository(uri: uri);
  await db.open();
  try {
    final cost = {
      'Ngay': DateTime.utc(2026, 11, 4),
      'SoTien': 150000,
      'GhiChu': 'Sửa',
      'MaYeuCau': 'repair-1',
    };
    await db.collection('Xe').insertOne({
      'IdXe': 1,
      'ChiPhi': [cost],
    });
    await db.collection('ChiTietNhapHang').insertOne({
      'IdXe': 1,
      'ChiPhi': [cost],
    });
    await db.collection('ThuChiKhac').insertOne({
      'ThuChiId': 40,
      'NgayThang': DateTime.utc(2026, 11, 4),
      'SoTien': 40000,
      'ThuChi': true,
      'LyDo': 'Thu tiền lãi nợ quá hạn khách hàng :Khách cũ',
    });
    await MongoProductCash.backfill(db);
    await MongoProductCash.backfill(db);
    await Future.wait(
      List.generate(
        3,
        (_) => MongoProductCash.record(
          db,
          source: 'Xe',
          productId: 1,
          cost: cost,
          sourceKey: 'repair-1',
        ),
      ),
    );
    check(
      await db.collection('ThuChiKhac').count({}) == 2,
      'Duplicated expense, receipt snapshot or old interest',
    );
    final voucher = await db.collection('ThuChiKhac').findOne({
      'IdDanhMuc': 'product-cost',
    });
    check(
      voucher?['SoTien'] == 150000 &&
          voucher?['ThuChi'] == false &&
          voucher?['ThuChiId'] == 41,
      'Expense fields/counter incorrect',
    );
    check(
      CashCategory.nameFor(
            (await db.collection('ThuChiKhac').findOne({'ThuChiId': 40}))!,
          ) ==
          'Lãi khách hàng trả nợ',
      'Legacy interest category missing',
    );
    final productRepo = MongoProductDetailsRepository(uri: uri);
    try {
      final token = ObjectId().oid;
      for (var i = 0; i < 2; i++) {
        await productRepo.addCost(
          const ProductReference(id: 1, vehicle: true),
          date: DateTime(2026, 11, 5),
          amount: 75000,
          notes: 'Sơn',
          requestId: token,
        );
      }
      check(
        await db.collection('ThuChiKhac').count({
              'IdDanhMuc': 'product-cost',
            }) ==
            2,
        'Saving product expense did not create exactly one extra cash voucher',
      );
      final product = await db.collection('Xe').findOne({'IdXe': 1});
      check(
        (product!['ChiPhi'] as List).length == 2,
        'Product expense itself duplicated on retry',
      );
    } finally {
      await productRepo.close();
    }
    await repo.saveCategory(
      const CashCategory('custom', 'Chi thuê kho', false),
    );
    check(
      (await repo.categories()).any((c) => c.id == 'custom'),
      'Category not created',
    );
    final draft = CashEntryDraft()
      ..income = false
      ..amount = '500000'
      ..reason = 'Tháng 11'
      ..categoryId = 'custom'
      ..categoryName = 'Chi thuê kho';
    final token = ObjectId().oid;
    await repo.createCash(draft, requestId: token);
    await repo.createCash(draft, requestId: token);
    await repo.saveCategory(
      const CashCategory('custom', 'Thuê mặt bằng', false),
    );
    await repo.archiveCategory('custom');
    await repo.createCash(draft, requestId: token);
    var rejected = false;
    try {
      await repo.createCash(
        CashEntryDraft()
          ..income = true
          ..amount = '10000'
          ..reason = 'Sai danh mục'
          ..categoryId = 'product-cost',
        requestId: ObjectId().oid,
      );
    } on FinanceException {
      rejected = true;
    }
    check(rejected, 'Expense category accepted for an income voucher');
    check(
      !(await repo.categories()).any((c) => c.id == 'custom'),
      'Archived category still active',
    );
    check(
      await db.collection('ThuChiKhac').count({'IdDanhMuc': 'custom'}) == 1,
      'Cash entry deleted/duplicated by category edit',
    );
    await repo.archiveCategory('utilities');
    check(
      !(await repo.categories()).any((c) => c.id == 'utilities'),
      'Default archive failed',
    );
    stdout.writeln(
      'PASS: source expenses, retry, receipt deduplication, preserved legacy interest, shared cash counter, category creation/rename/archive and retained vouchers.',
    );
  } finally {
    await repo.close();
    await db.drop();
    await db.close();
  }
}
