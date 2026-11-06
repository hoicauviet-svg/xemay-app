import 'package:xemay_app/models/finance/opening_debt.dart';
import 'package:xemay_app/models/repositories/opening_debt_repository.dart';

class FakeDebts extends OpeningDebtRepository {
  String status = '', search = '';
  List<Map<String, dynamic>>? debtRows;
  OpeningDebtPayment? saved;
  final debt = <String, dynamic>{
    'Id': 17,
    'IdKH': '86',
    'TongNo': 1000000.0,
    'SoTienDaTra': 200000.0,
    'SoCoNo': 800000.0,
    'GhiChu': 'Mua xe',
  };
  final customer = <String, dynamic>{
    'TenKhachHang': 'Khách thử',
    'SoDienThoai': '0901234567',
  };
  final payments = <Map<String, dynamic>>[];
  @override
  Future<OpeningDebtPage> list({
    String search = '',
    String status = 'open',
  }) async {
    this.status = status;
    this.search = search;
    final rows =
        debtRows ??
        [
          {...debt, 'KhachHang': customer},
        ];
    return OpeningDebtPage(rows, rows.length);
  }

  @override
  Future<OpeningDebtDetails> details(int id) async =>
      OpeningDebtDetails(debt, customer, payments);
  @override
  Future<void> pay(
    OpeningDebtPayment payment, {
    required String requestId,
  }) async {
    saved = payment;
    debt['SoCoNo'] = (debt['SoCoNo'] as num) - payment.principal;
    debt['SoTienDaTra'] = (debt['SoTienDaTra'] as num) + payment.principal;
    payments.add({'Id': 1, ...payment.toFields(), 'ConNo': debt['SoCoNo']});
  }

  @override
  Future<void> close() async {}
}
