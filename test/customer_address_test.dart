import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/services/customer_address.dart';
import 'package:xemay_app/models/pawn/pawn_models.dart';
import 'package:xemay_app/models/printing/pawn_contract_data.dart';

void main() {
  test('Legacy addresses are flattened without duplicate locality', () {
    expect(
      mergedCustomerAddress(' Số 008, tổ 3 ', ' Mậu A, Văn Yên, Yên Bái '),
      'Số 008, tổ 3, Mậu A, Văn Yên, Yên Bái',
    );
    expect(
      mergedCustomerAddress('Thôn 1, Xã kiểm thử', 'Xã kiểm thử'),
      'Thôn 1, Xã kiểm thử',
    );
    expect(mergedCustomerAddress(null, 'Mậu A'), 'Mậu A');
    expect(mergedCustomerAddress('Thôn 1', null), 'Thôn 1');
  });
  test('Printed contracts use complete flat customer address without Xa', () {
    final data = PawnContractData(
      PawnDetails(
        contract: {'IdCamDo': 1, 'SoTienVay': 1000000},
        customer: {'DiaChiChiTiet': 'Số 008, tổ 3, Mậu A, Văn Yên, Yên Bái'},
        payments: [],
      ),
    );
    expect(data.values['address'], 'Số 008, tổ 3, Mậu A, Văn Yên, Yên Bái');
  });
}
