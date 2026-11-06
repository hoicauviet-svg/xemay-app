import 'dart:convert';

class CustomerDuplicateGroup {
  const CustomerDuplicateGroup(this.value, this.customers);
  final String value;
  final List<Map<String, dynamic>> customers;
}

String normalizeCustomerText(Object? value) => (value ?? '')
    .toString()
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), ' ');

String normalizeCustomerPhone(Object? value) {
  var phone = (value ?? '').toString().replaceAll(RegExp(r'\D'), '');
  if (phone.startsWith('84') && phone.length >= 11) {
    phone = '0${phone.substring(2)}';
  }
  return phone.length >= 7 && !RegExp(r'^0+$').hasMatch(phone) ? phone : '';
}

List<CustomerDuplicateGroup> findCustomerDuplicates(
  List<Map<String, dynamic>> rows,
) {
  final groups = <String, Map<int, Map<String, dynamic>>>{};
  for (final row in rows) {
    if (row['DaXoa'] == true ||
        row['AnKhoiDanhSachKhachHang'] == true ||
        row['IdKH'] is! int) {
      continue;
    }
    final name = normalizeCustomerText(row['TenKhachHang']);
    final address = normalizeCustomerText(
      row['DiaChiHienThi'] ?? row['DiaChiChiTiet'],
    );
    final phone = normalizeCustomerPhone(row['SoDienThoai']);
    // Missing values do not establish that these are the same person.
    if (name.isEmpty || address.isEmpty || phone.isEmpty) continue;
    final key = jsonEncode([name, phone, address]);
    (groups[key] ??= {})[row['IdKH'] as int] = row;
  }
  final result = <CustomerDuplicateGroup>[];
  for (final entry in groups.entries.where((e) => e.value.length > 1)) {
    final members = entry.value.values.toList()
      ..sort((a, b) => (a['IdKH'] as int).compareTo(b['IdKH'] as int));
    final fields = jsonDecode(entry.key) as List;
    result.add(CustomerDuplicateGroup(fields.join(' · '), members));
  }
  result.sort((a, b) {
    final count = b.customers.length.compareTo(a.customers.length);
    return count != 0 ? count : a.value.compareTo(b.value);
  });
  return result;
}

List<Map<String, dynamic>> searchCustomers(
  List<Map<String, dynamic>> rows,
  String search,
) {
  final term = normalizeCustomerText(search);
  final digits = search.replaceAll(RegExp(r'\D'), '');
  final normalizedPhone = normalizeCustomerPhone(search);
  final phone = normalizedPhone.isNotEmpty
      ? normalizedPhone
      : digits.length >= 3
      ? digits
      : '';
  return rows.where((row) {
    if (row['DaXoa'] == true ||
        row['AnKhoiDanhSachKhachHang'] == true ||
        row['IdKH'] is! int) {
      return false;
    }
    return term.isEmpty ||
        [
          'IdKH',
          'TenKhachHang',
          'DiaChiHienThi',
          'DiaChiChiTiet',
          'SoDienThoai',
        ].any((field) => normalizeCustomerText(row[field]).contains(term)) ||
        (phone.isNotEmpty &&
            normalizeCustomerPhone(row['SoDienThoai']).contains(phone));
  }).toList();
}
