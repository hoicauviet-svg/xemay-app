import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/models/customers/customer_duplicates.dart';

void main() {
  test(
    'Require all three fields; normalize spacing/case/phone; largest group first',
    () {
      Map<String, dynamic> row(
        int id,
        String name,
        String address,
        String phone,
      ) => {
        'IdKH': id,
        'TenKhachHang': name,
        'DiaChiHienThi': address,
        'SoDienThoai': phone,
      };
      final rows = [
        row(1, ' Nguyễn   An ', ' Phố 1 ', '0901 234 567'),
        row(2, 'nguyễn an', 'phố 1', '+84 901-234-567'),
        row(3, 'Nguyễn An', 'Phố 2', '0901234567'), // same name+phone only
        row(4, 'Người khác', 'Phố 1', '0901234567'), // same address+phone only
        row(5, 'Nguyễn An', 'Phố 1', '0909999999'), // same name+address only
        for (var i = 6; i <= 8; i++) row(i, 'Trần Bình', 'Phố 3', '0912345678'),
        row(9, 'Nguyễn An', 'Phố 1', '0901234567')..['DaXoa'] = true,
      ];
      final groups = findCustomerDuplicates(rows);
      expect(groups.length, 2);
      expect(groups.first.customers.map((r) => r['IdKH']), [6, 7, 8]);
      expect(groups.last.customers.map((r) => r['IdKH']), [1, 2]);
      expect(searchCustomers(rows, '901234').length, 4);
      expect(searchCustomers(rows, 'không có'), isEmpty);
    },
  );
  test(
    'Missing name/phone/address never forms a duplicate group; customer ID is unique',
    () {
      final rows = <Map<String, dynamic>>[
        for (var id = 1; id <= 2; id++)
          {
            'IdKH': id,
            'TenKhachHang': 'An',
            'DiaChiHienThi': 'Phố 1',
            'SoDienThoai': '',
          },
        for (var id = 3; id <= 4; id++)
          {'IdKH': id, 'TenKhachHang': 'An', 'SoDienThoai': '0901234567'},
        for (var id = 5; id <= 6; id++)
          {'IdKH': id, 'DiaChiHienThi': 'Phố 1', 'SoDienThoai': '0901234567'},
        for (var id = 7; id <= 8; id++)
          {
            'IdKH': id,
            'TenKhachHang': 'An',
            'DiaChiHienThi': 'Phố 1',
            'SoDienThoai': '0000000000',
          },
        for (var i = 0; i < 2; i++)
          {
            'IdKH': 9,
            'TenKhachHang': 'An',
            'DiaChiHienThi': 'Phố 1',
            'SoDienThoai': '0901234567',
          },
      ];
      expect(findCustomerDuplicates(rows), isEmpty);
    },
  );
}
