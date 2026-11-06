class CustomerPage {
  const CustomerPage(this.rows, this.total);
  final List<Map<String, dynamic>> rows;
  final int total;
}

class CustomerDraft {
  String name = '', phone = '', address = '';
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
