import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/models/orders/order_details.dart';

void main() {
  OrderDetails order({
    Map<String, dynamic> header = const {},
    List<Map<String, dynamic>> lines = const [],
  }) => OrderDetails(
    header: header,
    customer: null,
    lines: lines,
    debts: [
      {'SoTienDaTra': 50000, 'SoTienConNo': 50000},
    ],
    payments: [],
  );
  test(
    'Legacy sale price supplies goods and total while paid and debt stay separate',
    () {
      final old = order(
        lines: [
          {'DonGia': null, 'DonGiaHienThi': 100000, 'SoLuong': 1},
        ],
      );
      expect(old.goodsTotal, 100000);
      expect(old.total, 100000);
      expect(old.separateTotal, isFalse);
      expect(old.paid, 50000);
      expect(old.due, 50000);
    },
  );
  test(
    'Discounted orders retain actual net total and unrecorded prices stay blank',
    () {
      final discounted = order(
        header: {
          'TongTienHang': 100000,
          'GiamGia': 10000,
          'TongThanhToan': 90000,
        },
        lines: [
          {'DonGia': 100000, 'SoLuong': 1},
        ],
      );
      expect(discounted.goodsTotal, 100000);
      expect(discounted.total, 90000);
      expect(discounted.separateTotal, isTrue);
      expect(
        order(
          lines: [
            {'DonGia': null, 'SoLuong': 1},
          ],
        ).total,
        isNull,
      );
      expect(
        order(
          header: {'GiamGia': 10000},
          lines: [
            {'DonGia': 100000, 'SoLuong': 1},
          ],
        ).total,
        90000,
      );
    },
  );
}
