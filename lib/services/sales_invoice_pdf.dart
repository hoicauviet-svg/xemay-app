import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/printing/sales_invoice_data.dart';

class SalesInvoicePdf {
  static Future<Uint8List> build(SalesInvoiceData data) async {
    final regular = await rootBundle.load('assets/fonts/NotoSerif-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/NotoSerif-Bold.ttf');
    final theme = pw.ThemeData.withFont(
      base: pw.Font.ttf(regular),
      bold: pw.Font.ttf(bold),
    );
    final doc = pw.Document(
      title: data.saved
          ? 'Hóa đơn bán hàng #${data.invoiceId}'
          : 'Hóa đơn bán hàng - bản nháp',
      theme: theme,
    );
    final draft = data.draft;
    String money(num value) =>
        '${NumberFormat('#,##0', 'vi_VN').format(value)} đ';
    String date(DateTime value) => DateFormat('dd/MM/yyyy').format(value);
    pw.Widget text(String value, {bool bold = false, double size = 10}) =>
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: size,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        );
    pw.Widget cell(String value, {bool bold = false, bool right = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: pw.Align(
            alignment: right
                ? pw.Alignment.centerRight
                : pw.Alignment.centerLeft,
            child: text(value, bold: bold),
          ),
        );
    pw.Widget amount(
      String label,
      num value, {
      bool bold = false,
      String? field,
    }) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        children: [
          pw.Expanded(child: text(label, bold: bold)),
          text(
            data.blankFields.contains(field) ? '' : money(value),
            bold: bold,
          ),
        ],
      ),
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        maxPages: 100,
        margin: const pw.EdgeInsets.all(32),
        theme: theme,
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            text(
              data.saved
                  ? 'Hóa đơn #${data.invoiceId}'
                  : 'Bản nháp • Đơn hàng chưa lưu',
              size: 8,
            ),
            text('Trang ${context.pageNumber}/${context.pagesCount}', size: 8),
          ],
        ),
        build: (_) => [
          text('CỬA HÀNG XE MÁY TOÀN HỢP', bold: true, size: 14),
          pw.SizedBox(height: 5),
          text('Số 008, Tổ 3, Khu phố II, TT Mậu A, Văn Yên, Yên Bái'),
          text('Điện thoại: 0216 3835 512 • 0912 506 369'),
          pw.Divider(height: 22),
          pw.Center(child: text('HÓA ĐƠN BÁN HÀNG', bold: true, size: 17)),
          pw.Center(
            child: text(
              data.saved
                  ? 'Số đơn hàng: #${data.invoiceId}'
                  : 'BẢN NHÁP – ĐƠN HÀNG CHƯA LƯU',
              size: 9,
            ),
          ),
          pw.SizedBox(height: 14),
          text('Ngày bán: ${date(draft.date)}'),
          text('Khách hàng: ${data.customerName}'),
          text('Điện thoại: ${data.customer['SoDienThoai'] ?? ''}'),
          text('Địa chỉ: ${data.address}'),
          pw.SizedBox(height: 14),
          pw.Table(
            columnWidths: {
              0: const pw.FixedColumnWidth(36),
              1: const pw.FlexColumnWidth(3.6),
              2: const pw.FixedColumnWidth(35),
              3: const pw.FlexColumnWidth(1.5),
              4: const pw.FlexColumnWidth(1.7),
            },
            border: pw.TableBorder.all(color: PdfColors.grey400, width: .5),
            children: [
              pw.TableRow(
                repeat: true,
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  cell('STT', bold: true),
                  cell('Sản phẩm / dịch vụ', bold: true),
                  cell('SL', bold: true, right: true),
                  cell('Đơn giá', bold: true, right: true),
                  cell('Thành tiền', bold: true, right: true),
                ],
              ),
              for (var i = 0; i < draft.lines.length; i++)
                pw.TableRow(
                  children: [
                    cell('${i + 1}'),
                    cell(
                      [
                        draft.lines[i].name,
                        if (draft.lines[i].kind == 'dich_vu') 'Dịch vụ',
                        for (final field in const {
                          'SoKhung': 'Số khung',
                          'SoMay': 'Số máy',
                          'BienSo': 'Biển số',
                        }.entries)
                          if ('${data.vehicles[draft.lines[i].vehicleId]?[field.key] ?? ''}'
                              .trim()
                              .isNotEmpty)
                            '${field.value}: ${data.vehicles[draft.lines[i].vehicleId]![field.key]}',
                      ].join('\n'),
                    ),
                    cell('${draft.lines[i].quantity}', right: true),
                    cell(
                      data.blankPriceLines.contains(i)
                          ? ''
                          : money(draft.lines[i].price),
                      right: true,
                    ),
                    cell(
                      data.blankPriceLines.contains(i)
                          ? ''
                          : money(draft.lines[i].total),
                      right: true,
                    ),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    amount('Tiền hàng', draft.subtotal, field: 'subtotal'),
                    amount('Giảm giá', draft.discount, field: 'discount'),
                    amount(
                      'Tổng thanh toán',
                      draft.total,
                      bold: true,
                      field: 'total',
                    ),
                    amount('Khách thanh toán', draft.paid, field: 'paid'),
                    if (draft.change > 0 &&
                        !data.blankFields.contains('change'))
                      amount(
                        'Thanh toán cho đơn',
                        draft.collected,
                        field: 'collected',
                      ),
                    if (draft.change > 0 &&
                        !data.blankFields.contains('change'))
                      amount(
                        'Tiền thừa trả khách',
                        draft.change,
                        field: 'change',
                      ),
                    amount('Còn phải thu', draft.due, bold: true, field: 'due'),
                    if (draft.storedDueDate != null)
                      text(
                        'Ngày hẹn thanh toán: ${date(draft.storedDueDate!)}',
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (draft.notes.trim().isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 10),
              child: text('Ghi chú: ${draft.notes.trim()}'),
            ),
          pw.SizedBox(height: 24),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              text('Khách hàng', bold: true),
              text('Người bán hàng', bold: true),
            ],
          ),
          pw.SizedBox(height: 50),
        ],
      ),
    );
    return doc.save();
  }
}
