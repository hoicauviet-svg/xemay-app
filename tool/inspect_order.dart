import 'dart:io';
import 'package:xemay_app/services/mongo_order_repository.dart';

Future<void> main() async {
  final repo = MongoOrderRepository();
  try {
    final d = await repo.load(151970);
    stdout.writeln({
      'goods': d.goodsTotal,
      'discount': d.discount,
      'total': d.total,
      'paid': d.paid,
      'due': d.due,
      'lines': d.lines
          .map(
            (l) => {
              'price': l['DonGiaHienThi'],
              'priceType': l['DonGiaHienThi'].runtimeType.toString(),
              'quantity': l['SoLuong'],
              'qtyType': l['SoLuong'].runtimeType.toString(),
            },
          )
          .toList(),
    });
  } finally {
    await repo.close();
  }
}
