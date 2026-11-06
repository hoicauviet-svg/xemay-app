import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:xemay_app/core/config/database_config.dart';
import 'package:xemay_app/models/goods_receipt/goods_receipt_models.dart';
import 'package:xemay_app/services/mongo_batch_repository.dart';

Future<void> main() async {
  final repository = MongoBatchRepository();
  final source = Db(DatabaseConfig.mongoUri);
  try {
    await repository.connect();
    await source.open();
    final page = await repository.fetch(ReceiptProductType.newVehicle);
    final expected = await source
        .collection('NhapHang')
        .count(
          MongoBatchRepository.filterFor(ReceiptProductType.newVehicle, ''),
        );
    if (page.total != expected) throw StateError('Số lô không khớp');
    final page2 = await repository.fetch(
      ReceiptProductType.newVehicle,
      page: 1,
    );
    final ids = page.batches.map((b) => b.id).toSet();
    if (page2.batches.any((b) => ids.contains(b.id))) {
      throw StateError('Trùng lô giữa các trang');
    }
    var checked = false;
    for (final batch in page.batches) {
      final products = await repository.products(
        batch,
        ReceiptProductType.newVehicle,
      );
      if (products.isEmpty) continue;
      final extensions = await source.collection('XeMoi').find({
        'IdNhapHang': batch.id,
      }).toList();
      final expectedIds = extensions.map((r) => r['IdXe']).toSet();
      if (products.length != expectedIds.length ||
          products.any(
            (p) => p.batchId != batch.id || !expectedIds.contains(p.vehicleId),
          )) {
        throw StateError('Liên kết lô và xe sai');
      }
      final first = products.first;
      final vehicle = await source.collection('Xe').findOne({
        'IdXe': first.vehicleId,
      });
      if (vehicle?['IdSanPham'] != first.productId) {
        throw StateError('Mã sản phẩm không khớp');
      }
      final history = await repository.payments(batch.id);
      final sourcePayments = await source.collection('TraNoNhapHang').find({
        'IdNhapHang': batch.id,
      }).toList();
      final paymentIds = sourcePayments
          .map((r) => r['IdTraNoNhapHang'])
          .toSet();
      if (history.length != sourcePayments.length ||
          history.any(
            (p) => p.batchId != batch.id || !paymentIds.contains(p.id),
          )) {
        throw StateError('Lịch sử thanh toán sai liên kết');
      }
      final fresh = await repository.findById(batch.id);
      if (fresh == null || fresh.remaining != batch.remaining) {
        throw StateError('Thông tin lô không khớp');
      }
      checked = true;
      break;
    }
    if (!checked && page.total > 0) {
      throw StateError('Chưa xác minh được lô có sản phẩm');
    }
    stdout.writeln(
      'PASS: $expected lots; pagination, XeMoi -> Xe -> SanPham links and TraNoNhapHang payment history verified. Read-only.',
    );
  } finally {
    await repository.close();
    if (source.isConnected) await source.close();
  }
}
