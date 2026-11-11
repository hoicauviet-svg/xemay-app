import 'package:intl/intl.dart';

class CustomerPage {
  const CustomerPage(this.rows, this.total);
  final List<Map<String, dynamic>> rows;
  final int total;
}

class CustomerDraft {
  String name = '', phone = '', address = '';
  String cccd = '', cmnd = '', issueDate = '', issuePlace = '';

  static String formatIssueDate(dynamic value) => value is DateTime
      ? DateFormat('dd/MM/yyyy').format(value)
      : '${value ?? ''}';

  String? validateIssueDate(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    try {
      if (!RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(text)) {
        throw const FormatException();
      }
      final date = DateFormat('dd/MM/yyyy').parseStrict(text);
      final now = DateTime.now();
      if (date.isAfter(DateTime(now.year, now.month, now.day))) {
        return 'Ngày cấp không được trong tương lai';
      }
      return null;
    } catch (_) {
      return 'Nhập ngày cấp hợp lệ theo dd/MM/yyyy';
    }
  }

  Map<String, dynamic> identityFields() {
    final error = validateIssueDate(issueDate);
    if (error != null) throw CustomerException(error);
    final date = issueDate.trim().isEmpty
        ? null
        : DateFormat('dd/MM/yyyy').parseStrict(issueDate.trim());
    return {
      'SoCCCD': cccd.trim(),
      'SoCMND': cmnd.trim(),
      'NgayCap': date == null
          ? null
          : DateTime.utc(date.year, date.month, date.day),
      'NoiCap': issuePlace.trim(),
    };
  }
}

class CustomerException implements Exception {
  const CustomerException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CustomerOrderPage {
  const CustomerOrderPage(this.rows, this.total);
  final List<Map<String, dynamic>> rows;
  final int total;
}
