import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/core/config/database_config.dart';
import 'package:xemay_app/models/goods_receipt/goods_receipt_models.dart';
import 'package:xemay_app/models/products/product_details.dart';
import 'package:xemay_app/services/mongo_partner_repository.dart';
import 'package:xemay_app/services/mongo_batch_repository.dart';
import 'package:xemay_app/services/mongo_product_details_repository.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  final db = Db(DatabaseConfig.mongoUri);
  await db.open();
  final partners = MongoPartnerRepository(),
      batches = MongoBatchRepository(),
      products = MongoProductDetailsRepository();
  try {
    final marker = await db.collection('_sql_metadata').findOne({
      '_id': 'purchase_receipts_v1',
    });
    check(marker != null, 'Migration marker missing');
    final converted = await db.collection('NhapHang').find({
      'NguonDuLieu': 'HoaDonMua',
    }).toList();
    check(
      converted.length == 1922 &&
          converted.every(
            (r) => r['SoTienDaTra'] == r['SoTien'] && r['SoTienConNo'] == 0,
          ),
      'Migrated balances incorrect',
    );
    check(
      await db.collection('NhapHang').count({
            'HinhThucNhap': {r'$exists': true},
          }) ==
          0,
      'Unexpected receipt modes remain',
    );
    final source = (await db.collection('NhapHang').findOne({
      'IdMuaNguon': 34907,
    }))!;
    final orders = await partners.purchaseOrders(source['IdDoiTac'] as String);
    check(
      orders.total == 1 && orders.rows.single['IdMuaNguon'] == 34907,
      'Partner missing or duplicate migrated order',
    );
    await batches.connect();
    final batch = (await batches.findById(source['IdNhapHang'] as int))!;
    check(
      batch.remaining == 0 && batch.paid == batch.total,
      'Batch balances wrong',
    );
    final lines = await batches.products(batch, ReceiptProductType.usedVehicle);
    check(lines.length == 1, 'Migrated batch product missing');
    final history = await batches.payments(batch.id);
    check(
      history.length == 1 &&
          history.single.amount == batch.total &&
          history.single.remaining == 0,
      'Migrated initial payment missing',
    );
    final detail = await products.load(
      ProductReference(id: lines.single.vehicleId!, vehicle: true),
    );
    check(
      detail.receipts.length == 1 && detail.receipts.single['Ma'] == batch.id,
      'Product receipt duplicated or missing',
    );

    final unknown = await db.collection('Xe').find({
      'IdNhapHang': {r'$exists': true},
      'TinhTrangXe': 'chua_xac_dinh',
    }).toList();
    for (final vehicle in unknown) {
      final parent = (await batches.findById(
        (vehicle['IdNhapHang'] as num).toInt(),
      ))!;
      final linked = await batches.products(
        parent,
        ReceiptProductType.usedVehicle,
      );
      check(
        linked.any((p) => p.vehicleId == vehicle['IdXe']),
        'Explicit receipt link hidden by unknown vehicle classification',
      );
    }
    stdout.writeln(
      'PASS: 1,922 full-paid purchases, zero debt, no receipt modes, partner orders, batch products/payments and product history.',
    );
    stdout.writeln('Original purchase #34907 -> receipt #${batch.id}.');
  } finally {
    await partners.close();
    await batches.close();
    await products.close();
    await db.close();
  }
}
