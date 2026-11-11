import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/models/printing/sales_invoice_data.dart';
import 'package:xemay_app/models/sales/sale_models.dart';
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
  testWidgets(
    'Preview contains invoice print and contract placeholder on narrow windows',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SalesOrderPreviewPopup(data: sample())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('In hóa đơn bán hàng'), findsOneWidget);
      final contract = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'In hợp đồng mua bán'),
      );
      expect(contract.onPressed, isNull);
      expect(
        find.text('Hợp đồng mua bán: chờ mẫu bạn cung cấp.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Print failure after save does not save the invoice again', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var saves = 0, builds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SalesOrderPreviewPopup(
            data: sample(),
            onSave: () async {
              saves++;
              return 501;
            },
            buildPdf: (data) async {
              builds++;
              expect(data.invoiceId, 501);
              throw StateError('PDF test failure');
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-print-sales-invoice')));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(builds, 1);
    expect(find.textContaining('Đơn #501 đã lưu.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('print-sales-invoice')));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(builds, 2);
    expect(tester.takeException(), isNull);
  });
}
