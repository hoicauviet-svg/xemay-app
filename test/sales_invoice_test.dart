import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/models/printing/pawn_contract_data.dart';
import 'package:xemay_app/models/printing/sale_contract_data.dart';
import 'package:xemay_app/models/printing/sales_invoice_data.dart';
import 'package:xemay_app/models/sales/sale_models.dart';
import 'package:xemay_app/services/sale_contract_pdf.dart';
import 'package:xemay_app/services/sales_invoice_pdf.dart';
import 'package:xemay_app/views/sales/sales_order_preview_popup.dart';

SalesInvoiceData sample({bool credit = false}) => SalesInvoiceData(
  draft: SaleDraft(
    lines: const [
      SaleLine(
        kind: 'xe',
        name: 'Honda Wave Alpha',
        quantity: 1,
        price: 25000000,
        vehicleId: 7,
        productId: 1,
      ),
      SaleLine(
        kind: 'phu_tung',
        name: 'Dầu nhớt xe máy',
        quantity: 2,
        price: 150000,
        productId: 2,
      ),
      SaleLine(
        kind: 'dich_vu',
        name: 'Bảo dưỡng xe',
        quantity: 1,
        price: 150000,
        serviceId: 'service-1',
      ),
    ],
    date: DateTime(2026, 11, 11),
    discount: 450000,
    paid: credit ? 15000000 : 26000000,
    customerId: 1,
    paymentDueDate: DateTime(2026, 12, 11),
    interestDate: DateTime(2026, 12, 11),
    notes: 'Giao đủ xe, giấy đăng ký và chìa khóa.',
  ),
  customer: {
    'IdKH': 1,
    'TenKhachHang': 'Nguyễn Văn Bình',
    'SoDienThoai': '0901234567',
    'DiaChiChiTiet': 'Tổ 3',
    'DiaChiHienThi': 'Tổ 3, Mậu A, Văn Yên, Yên Bái',
  },
  vehicles: {
    7: {'SoKhung': 'KHUNG-0007', 'SoMay': 'MAY-0007', 'BienSo': '21-B1 123.45'},
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Invoice snapshots customer and cart, preserves payment and change', () {
    final customer = <String, dynamic>{'TenKhachHang': 'Khách ban đầu'};
    final lines = [
      const SaleLine(
        kind: 'dich_vu',
        name: 'Dịch vụ',
        quantity: 1,
        price: 100000,
        serviceId: 's',
      ),
    ];
    final data = SalesInvoiceData(
      draft: SaleDraft(
        lines: lines,
        date: DateTime(2026, 11, 11),
        discount: 0,
        paid: 100000,
      ),
      customer: customer,
    );
    customer['TenKhachHang'] = 'Đã đổi';
    lines.clear();
    expect(data.customerName, 'Khách ban đầu');
    expect(data.draft.lines.length, 1);
    expect(sample().draft.collected, 25000000);
    expect(sample().draft.change, 1000000);
    expect(sample().address, 'Tổ 3, Mậu A, Văn Yên, Yên Bái');
    expect(sample(credit: true).draft.due, 10000000);
    expect(sample().asSaved(501).fileName, 'hoa-don-ban-hang-501.pdf');
  });
  test(
    'Vietnamese invoice PDFs cover draft, saved credit and many products',
    () async {
      final dir = Directory('build/test-results')..createSync(recursive: true);
      for (final entry in {
        'sales-invoice-draft': sample(),
        'sales-invoice-credit': sample(credit: true).asSaved(501),
      }.entries) {
        final bytes = await SalesInvoicePdf.build(entry.value);
        expect(String.fromCharCodes(bytes.take(4)), '%PDF');
        File('${dir.path}/${entry.key}.pdf').writeAsBytesSync(bytes);
      }
      final long = SalesInvoiceData(
        draft: SaleDraft(
          lines: List.generate(
            80,
            (i) => SaleLine(
              kind: 'phu_tung',
              name:
                  'Phụ tùng số ${i + 1} – linh kiện xe máy, hàng giao đúng mô tả',
              quantity: 2,
              price: 100000 + i,
              productId: i + 1,
            ),
          ),
          date: DateTime(2026, 11, 11),
          discount: 0,
          paid: 100000000,
        ),
        customer: {'TenKhachHang': 'Khách lẻ kiểm thử'},
      ).asSaved(502);
      File(
        '${dir.path}/sales-invoice-long.pdf',
      ).writeAsBytesSync(await SalesInvoicePdf.build(long));
    },
  );
  test('Sale contract follows the Toàn Hợp form and order amounts', () {
    final contract = SaleContractData(sample());
    final values = contract.values;
    expect(values['buyerName'], 'Nguyễn Văn Bình');
    expect(values['phone'], '0901234567');
    expect(values['year'], '2026');
    expect(values['paidAmount'], '25.000.000');
    expect(values['paidWords'], vietnameseMoneyWords(25000000));
    expect(values['dueWords'], 'Không đồng');
    expect(values['toDay'], '……');
    expect(values['identityNumber'], contains('…'));
    expect(contract.goodsLines.join('\n'), contains('KHUNG-0007'));
    expect(contract.goodsLines.join('\n'), contains('MAY-0007'));
    expect(contract.goodsLines.join('\n'), contains('Dầu nhớt xe máy × 2'));
    final source = sample(credit: true);
    final credit = SaleContractData(
      SalesInvoiceData(
        draft: source.draft,
        customer: {
          ...source.customer,
          'SoCCCD': '012345678901',
          'NgayCap': DateTime.utc(2020, 2, 1),
          'NoiCap': 'Yên Bái',
        },
        vehicles: source.vehicles,
      ).asSaved(501),
    );
    expect(credit.fileName, 'hop-dong-mua-ban-501.pdf');
    expect(credit.values['identityNumber'], '012345678901');
    expect(credit.values['identityDate'], '01/02/2020');
    expect(credit.values['dueAmount'], '10.000.000');
    expect(credit.values['toDay'], '11');
    expect(credit.values['toMonth'], '12');
    expect(credit.values['commitment'], contains('Giao đủ xe'));
  });
  test('Sale contract PDF uses the Vietnamese template', () async {
    final bytes = await SaleContractPdf.build(sample(credit: true));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    final pages = RegExp(
      r'/Type\s*/Page(?!s)',
    ).allMatches(String.fromCharCodes(bytes)).length;
    expect(pages, 1);
    final dir = Directory('build/test-results')..createSync(recursive: true);
    File('${dir.path}/sale-contract-sample.pdf').writeAsBytesSync(bytes);
  });
  testWidgets(
    'Preview prints the sale contract from the order without saving it',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Uint8List? printed;
      String? fileName;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SalesOrderPreviewPopup(
              data: sample(),
              buildPdf: (_) async => Uint8List.fromList('%PDF'.codeUnits),
              buildContractPdf: (_) async =>
                  Uint8List.fromList('%PDF-contract'.codeUnits),
              printDocument: (bytes, name) async {
                printed = bytes;
                fileName = name;
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.widgetWithText(Tab, 'Hóa đơn'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Hợp đồng'), findsOneWidget);
      final invoicePrint = tester.widget<FloatingActionButton>(
        find.byKey(const ValueKey('print-sales-invoice')),
      );
      expect(invoicePrint.onPressed, isNotNull);
      await tester.tap(find.widgetWithText(Tab, 'Hợp đồng'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('print-sale-contract')));
      await tester.pump();
      expect(fileName, 'hop-dong-mua-ban-2026-11-11.pdf');
      expect(String.fromCharCodes(printed!), '%PDF-contract');
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
