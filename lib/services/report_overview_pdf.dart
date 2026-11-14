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
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
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
    final rowsByTitle = {for (final block in blocks) block.$1: block.$2};
    final totalIncome = _blockAmount(rowsByTitle['THU'], 'Tổng thu');
    final totalExpense = _blockAmount(rowsByTitle['CHI'], 'Tổng chi');
    rowsByTitle['CHÊNH LỆCH'] = [
      [
        'Tổng thu trừ tổng chi',
        null,
        null,
        null,
        null,
        totalIncome == null || totalExpense == null
            ? null
            : totalIncome - totalExpense,
      ],
    ];
    const sectionOrder = [
      'BÁN HÀNG',
      'CẦM ĐỒ',
      'THU KHÁC',
      'CHI KHÁC',
      'TRẢ LÃI VAY VỐN',
      'KẾT QUẢ',
    ];
    const cashOrder = ['THU', 'CHI', 'CHÊNH LỆCH'];
    const balanceOrder = ['KHO HÀNG', 'CỬA HÀNG NỢ', 'KHÁCH HÀNG NỢ'];
    const line = PdfColor.fromInt(0xFFD5DDD8);
    pw.Widget renderBlock(String title) {
      final rows = rowsByTitle[title] ?? const <List<dynamic>>[];
      final accent = _blockAccent(title);
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: pw.BoxDecoration(
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          border: pw.Border.all(color: line, width: 0.4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(font: bold, fontSize: 9, color: accent),
            ),
            pw.Divider(color: line, height: 8, thickness: 0.3),
            if (title == 'BÁN HÀNG' || title == 'KHO HÀNG')
              pw.TableHelper.fromTextArray(
                headers: title == 'KHO HÀNG'
                    ? const ['', 'Xe mới', 'Xe cũ', 'Phụ tùng', 'Tổng']
                    : [for (final column in section.columns) column.label],
                data: [
                  for (final row in rows)
                    [
                      for (final value
                          in title == 'KHO HÀNG'
                              ? [row[0], row[1], row[2], row[3], row[5]]
                              : row)
                        value == null
                            ? (title == 'KHO HÀNG' ? '—' : '')
                            : value is num
                            ? amount(value)
                            : '$value',
                    ],
                ],
                columnWidths: title == 'KHO HÀNG'
                    ? const {
                        0: pw.FlexColumnWidth(1.5),
                        1: pw.FlexColumnWidth(1.2),
                        2: pw.FlexColumnWidth(1.2),
                        3: pw.FlexColumnWidth(1.2),
                        4: pw.FlexColumnWidth(1.3),
                      }
                    : const {
                        0: pw.FlexColumnWidth(1.7),
                        1: pw.FlexColumnWidth(1.15),
                        2: pw.FlexColumnWidth(1.15),
                        3: pw.FlexColumnWidth(1.15),
                        4: pw.FlexColumnWidth(1.15),
                        5: pw.FlexColumnWidth(1.2),
                      },
                headerStyle: pw.TextStyle(
                  font: bold,
                  fontSize: 7.5,
                  color: accent,
                ),
                cellStyle: const pw.TextStyle(fontSize: 7.5),
                cellPadding: const pw.EdgeInsets.symmetric(
                  horizontal: 3,
                  vertical: 3,
                ),
                border: pw.TableBorder.all(color: line, width: 0.3),
                cellAlignments: {
                  for (
                    var i = 1;
                    i < (title == 'KHO HÀNG' ? 5 : section.columns.length);
                    i++
                  )
                    i: pw.Alignment.centerRight,
                },
              )
            else
              for (final row in rows)
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.Padding(
                          padding: pw.EdgeInsets.only(
                            left: '${row[0]}'.startsWith(' ') ? 12 : 0,
                          ),
                          child: pw.Text(
                            '${row[0]}'.trim(),
                            style: const pw.TextStyle(fontSize: 9),
                          ),
                        ),
                      ),
                      pw.Text(
                        row.last is num ? amount(row.last) : '—',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                          font: _emphasized('${row[0]}') ? bold : regular,
                          fontSize: title == 'KẾT QUẢ' || title == 'CHÊNH LỆCH'
                              ? 12
                              : 9,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      );
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 28),
        header: (context) => pw.Column(
          children: [
            pw.Text(
              'BÁO CÁO TỔNG',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(font: bold, fontSize: 14),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              period,
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.Text(
              'Cập nhật ${DateFormat('dd/MM/yyyy HH:mm').format(loadedAt)}',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.SizedBox(height: 8),
          ],
        ),
        build: (context) => [
          for (var i = 0; i < sectionOrder.length; i++) ...[
            if (i > 0) pw.SizedBox(height: 8),
            renderBlock(sectionOrder[i]),
          ],
          pw.SizedBox(height: 10),
          pw.Text(
            section.notes.join('\n'),
            style: const pw.TextStyle(fontSize: 8),
          ),
          pw.NewPage(),
          pw.Text(
            'THU CHI',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: bold, fontSize: 12),
          ),
          pw.SizedBox(height: 8),
          for (var i = 0; i < cashOrder.length; i++) ...[
            if (i > 0) pw.SizedBox(height: 8),
            renderBlock(cashOrder[i]),
          ],
          pw.NewPage(),
          for (var i = 0; i < balanceOrder.length; i++) ...[
            if (i > 0) pw.SizedBox(height: 8),
            renderBlock(balanceOrder[i]),
          ],
        ],
      ),
    );
    return pdf.save();
  }

  static bool _emphasized(String label) => const {
    'Lãi',
    'Lợi nhuận tổng',
    'Tổng thu',
    'Tổng chi',
    'Tổng thu trừ tổng chi',
    'Tổng cửa hàng nợ',
    'Tổng khách hàng nợ',
  }.contains(label.trim());

  static num? _blockAmount(List<List<dynamic>>? rows, String label) {
    for (final row in rows ?? const <List<dynamic>>[]) {
      if (row.isNotEmpty && '${row[0]}'.trim() == label) {
        final value = row.last;
        return value is num ? value : null;
      }
    }
    return null;
  }

  static PdfColor _blockAccent(String title) => switch (title) {
    'CẦM ĐỒ' => const PdfColor.fromInt(0xFF8B45C4),
    'THU KHÁC' => const PdfColor.fromInt(0xFF2F6FE4),
    'CHI KHÁC' ||
    'TRẢ LÃI VAY VỐN' ||
    'CHI' => const PdfColor.fromInt(0xFFD23B4A),
    'BÁN HÀNG' ||
    'KẾT QUẢ' ||
    'THU' ||
    'CHÊNH LỆCH' ||
    'KHO HÀNG' => const PdfColor.fromInt(0xFF0E8A6A),
    'CỬA HÀNG NỢ' => const PdfColor.fromInt(0xFFD23B4A),
    'KHÁCH HÀNG NỢ' => const PdfColor.fromInt(0xFF2F6FE4),
    _ => const PdfColor.fromInt(0xFF65736B),
  };
}
