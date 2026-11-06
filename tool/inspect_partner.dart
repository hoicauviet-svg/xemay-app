import 'dart:io';
import 'package:xemay_app/services/mongo_partner_repository.dart';

Future<void> main() async {
  final repo = MongoPartnerRepository();
  try {
    final result = await repo.purchaseOrders('6ae6fc0bbd3bec742df90fb2');
    stdout.writeln({
      'total': result.total,
      'orders': result.rows.map((r) => r['MaDonHang']).toList(),
    });
    if (!result.rows.any(
      (r) => r['IdMuaNguon'] == 34907 || r['MaDonHang'] == 34907,
    )) {
      throw StateError('Missing order 34907');
    }
  } finally {
    await repo.close();
  }
}
