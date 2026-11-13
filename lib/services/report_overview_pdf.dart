import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/formatters/inventory_formatters.dart';
import '../models/reports/report_models.dart';

class ReportOverviewPdf {
  static Future<Uint8List> build(
    ReportSection section,
    ReportRange range,
    DateTime loadedAt,
  ) async {
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSerif-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSerif-Bold.ttf'),
    );
    final date = DateFormat('dd/MM/yyyy');
    final period = range.from == null && range.to == null
        ? 'Tất cả thời gian'
        : 'Từ ${range.from == null ? '' : date.format(range.from!)} đến ${range.to == null ? '' : date.format(range.to!)}';
    final pdf = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold));
    String amount(dynamic value) => value is num ? money(value) : '—';
    final blocks = <(String, List<List<dynamic>>)>[];
    String? currentTitle;
    var currentRows = <List<dynamic>>[];
    for (final row in section.rows) {
      final label = row.isEmpty ? '' : '${row[0]}';
      if (label.startsWith('@@')) {
        if (currentTitle != null) blocks.add((currentTitle, currentRows));
        currentTitle = label.substring(2);
        currentRows = [];
      } else {
        currentTitle ??= 'TỔNG HỢP';
        currentRows.add(row);
      }
    }
    if (currentTitle != null) blocks.add((currentTitle, currentRows));

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(34),
        header: (context) => pw.Column(
          children: [
            pw.Text(
              'BÁO CÁO TỔNG',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(font: bold, fontSize: 15),
            ),
            pw.SizedBox(height: 3),
            pw.Text(period, textAlign: pw.TextAlign.center),
            pw.Text(
              'Cập nhật ${DateFormat('dd/MM/yyyy HH:mm').format(loadedAt)}',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
        ),
        build: (context) => [
          for (final block in blocks) ...[
            pw.Container(
              width: double.infinity,
              margin: const pw.EdgeInsets.only(top: 8),
              padding: const pw.EdgeInsets.all(9),
              decoration: pw.BoxDecoration(
                color: _blockBackground(block.$1),
                borderRadius: const pw.BorderRadius.all(
                  pw.Radius.circular(8),
                ),
                border: pw.Border.all(color: _blockAccent(block.$1), width: 1),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Text(
                    block.$1,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      font: bold,
                      fontSize: 9.5,
                      color: _blockAccent(block.$1),
                    ),
                  ),
                  pw.Divider(
                    color: _blockAccent(block.$1),
                    height: 10,
                    thickness: 0.5,
                  ),
                  if (block.$1 == 'BÁN HÀNG')
                    pw.TableHelper.fromTextArray(
                      headers: [for (final column in section.columns) column.label],
                      data: [
                        for (final row in block.$2)
                          [
                            for (final value in row)
                              value == null
                                  ? ''
                                  : value is num
                                  ? amount(value)
                                  : '$value',
                          ],
                      ],
                      columnWidths: const {
                        0: pw.FlexColumnWidth(1.8),
                        1: pw.FlexColumnWidth(1.2),
                        2: pw.FlexColumnWidth(1.2),
                        3: pw.FlexColumnWidth(1.2),
                        4: pw.FlexColumnWidth(1.2),
                        5: pw.FlexColumnWidth(1.2),
                      },
                      headerStyle: pw.TextStyle(
                        font: bold,
                        fontSize: 9,
                        color: _blockAccent(block.$1),
                      ),
                      headerDecoration: pw.BoxDecoration(
                        color: _blockBackground(block.$1),
                      ),
                      cellStyle: const pw.TextStyle(fontSize: 9),
                      cellPadding: const pw.EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 5,
                      ),
                      border: pw.TableBorder.all(
                        color: const PdfColor.fromInt(0xFFE1E8E5),
                        width: 0.5,
                      ),
                      cellAlignments: {
                        for (var i = 1; i < section.columns.length; i++)
                          i: pw.Alignment.centerRight,
                      },
                    )
                  else
                    for (final row in block.$2)
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 3),
                        child: pw.Row(
                          children: [
                            pw.Expanded(child: pw.Text('${row[0]}')),
                            pw.SizedBox(
                              width: 165,
                              child: pw.Text(
                                row.last is num ? amount(row.last) : '—',
                                textAlign: pw.TextAlign.right,
                                style: pw.TextStyle(
                                  font: row[0] == 'Lãi' ? bold : regular,
                                  fontSize: 9.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ],
          pw.SizedBox(height: 12),
          pw.Text(
            section.notes.join('\n'),
            style: const pw.TextStyle(fontSize: 8.5),
          ),
        ],
      ),
    );
    return pdf.save();
  }

  static PdfColor _blockAccent(String title) => switch (title) {
    'THU CHI KHÁC' => const PdfColor.fromInt(0xFF2F6FE4),
    'BÁN HÀNG' || 'LÃI XE' || 'KẾT QUẢ' => const PdfColor.fromInt(0xFF0E8A6A),
    _ => const PdfColor.fromInt(0xFF65736B),
  };

  static PdfColor _blockBackground(String title) => switch (title) {
    'THU CHI KHÁC' => const PdfColor.fromInt(0xFFF3F6FD),
    'BÁN HÀNG' || 'LÃI XE' || 'KẾT QUẢ' => const PdfColor.fromInt(0xFFF1F8F5),
    _ => const PdfColor.fromInt(0xFFFAFBFC),
  };
}

