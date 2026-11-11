import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/models/pawn/pawn_models.dart';
import 'package:xemay_app/models/printing/pawn_contract_data.dart';
import 'package:xemay_app/services/pawn_contract_pdf.dart';
import 'package:xemay_app/views/printing/pawn_contract_screen.dart';

PawnDetails sample({String? asset}) => PawnDetails(
  contract: {
    'IdCamDo': 123,
    'SoTienVay': 12500000.0,
    'NgayVay': DateTime.utc(2027, 1, 10),
    'NgayHan': DateTime.utc(2027, 2, 9),
    'TaiSanTheChap':
        asset ??
        'Xe máy Honda Wave, biển số 21-B1 123.45, kèm giấy đăng ký xe.',
  },
  customer: {
    'TenKhachHang': 'Nguyễn Văn Bình',
    'SoDienThoai': '0901234567',
    'DiaChiChiTiet': 'Tổ 3, thị trấn Mậu A, Văn Yên, Yên Bái',
  },
  payments: [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Vietnamese currency words handle group boundaries and maximum', () {
    expect(
      vietnameseMoneyWords(12500000),
      'Mười hai triệu năm trăm nghìn đồng chẵn',
    );
    expect(
      vietnameseMoneyWords(1000001),
      'Một triệu không trăm lẻ một đồng chẵn',
    );
    expect(vietnameseMoneyWords(21000), 'Hai mươi mốt nghìn đồng chẵn');
    expect(vietnameseMoneyWords(15000), 'Mười lăm nghìn đồng chẵn');
    expect(vietnameseMoneyWords(1000000000000000), 'Một triệu tỷ đồng chẵn');
  });
  test(
    'Print snapshot keeps saved dates and leaves missing identity blank',
    () {
      final data = PawnContractData(sample());
      expect(data.values['loanYear'], '2027');
      expect(data.values['termDays'], '30');
      expect(data.values['identityNumber'], contains('…'));
      data.identityNumber = '012345678901';
      expect(data.values['identityNumber'], '012345678901');
      expect(sample().customer!.containsKey('identityNumber'), false);
      expect(
        () => PawnContractData(
          PawnDetails(
            contract: {'IdCamDo': 1, 'SoTienVay': double.nan},
            payments: [],
          ),
        ),
        throwsFormatException,
      );
    },
  );
  test('PDF embeds Vietnamese fonts and supports long collateral', () async {
    final data = PawnContractData(sample())
      ..identityNumber = '012345678901'
      ..identityDate = '01/02/2020'
      ..identityPlace = 'Yên Bái';
    final bytes = await PawnContractPdf.build(data);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    final dir = Directory('build/test-results')..createSync(recursive: true);
    File('${dir.path}/pawn-contract-sample.pdf').writeAsBytesSync(bytes);
    final long = await PawnContractPdf.build(
      PawnContractData(
        sample(
          asset: List.filled(
            15,
            'Xe máy kèm giấy đăng ký, chìa khóa và mô tả tình trạng tài sản.',
          ).join(' '),
        ),
      ),
    );
    File('${dir.path}/pawn-contract-long.pdf').writeAsBytesSync(long);
  });
  testWidgets('Supplemental print form opens without modifying saved pawn', (
    tester,
  ) async {
    final details = sample();
    await tester.pumpWidget(
      MaterialApp(home: PawnContractScreen(details: details)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Xem trước & in'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'CMND / CCCD'),
      '012345678901',
    );
    expect(details.customer!.keys, isNot(contains('identityNumber')));
    expect(tester.takeException(), isNull);
  });
}
