import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/printing/sale_contract_data.dart';
import '../models/printing/sales_invoice_data.dart';

class SaleContractPdf {
  static const _body = 10.2;
  static const _title = 14.0;

  static Future<Uint8List> build(SalesInvoiceData data) async {
    final template =
        jsonDecode(
              await rootBundle.loadString(
                'assets/templates/sale_contract.json',
              ),
            )
            as Map<String, dynamic>;
    final regular = await rootBundle.load('assets/fonts/NotoSerif-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/NotoSerif-Bold.ttf');
    final theme = pw.ThemeData.withFont(
      base: pw.Font.ttf(regular),
      bold: pw.Font.ttf(bold),
    );
    final contract = SaleContractData(data);
    final values = contract.values;
    String fill(String text) => text.replaceAllMapped(
      RegExp(r'\{(\w+)\}'),
      (match) => values[match[1]] ?? match[0]!,
    );
    String visible(String text) => fill(
      text,
    ).replaceAll(SaleContractData.blank, '').replaceAll('……', '').trimRight();
    final body = pw.TextStyle(fontSize: _body, height: 1.08, lineSpacing: 0.4);
    final section = pw.TextStyle(
      fontSize: _body,
      height: 1.08,
      lineSpacing: 0.4,
      fontWeight: pw.FontWeight.bold,
    );
    final document = pw.Document(title: 'Hợp đồng mua bán', theme: theme);
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(22, 16, 22, 8),
        theme: theme,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _banner(template['banner'] as Map<String, dynamic>),
            for (final paragraph in template['paragraphs'] as List)
              if (paragraph['kind'] == 'goods')
                for (final row in contract.goodsRows)
                  _fill([for (final part in row) _Span(part)], body, section)
              else if (paragraph['kind'] == 'fill')
                _fill(
                  _spans(paragraph['parts'] as List, visible),
                  body,
                  section,
                )
              else
                _paragraph(
                  fill(paragraph['text'] as String),
                  paragraph['kind'] as String,
                  body,
                  section,
                ),
            pw.SizedBox(height: 8),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (final signature in template['signatures'] as List)
                  pw.Expanded(
                    child: pw.Text(
                      signature as String,
                      textAlign: pw.TextAlign.center,
                      style: section,
                    ),
                  ),
              ],
            ),
            pw.Spacer(),
            pw.Text(
              template['note'] as String,
              style: pw.TextStyle(fontSize: _body - 0.6, height: 1),
            ),
          ],
        ),
      ),
    );
    return document.save();
  }

  static pw.Widget _banner(Map<String, dynamic> banner) {
    final head = pw.TextStyle(
      fontSize: 10,
      height: 1.05,
      fontWeight: pw.FontWeight.bold,
    );
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          banner['nation'] as String,
          textAlign: pw.TextAlign.center,
          style: head,
        ),
        pw.Text(
          banner['motto'] as String,
          textAlign: pw.TextAlign.center,
          style: head,
        ),
        pw.Text(
          banner['mark'] as String,
          textAlign: pw.TextAlign.center,
          style: const pw.TextStyle(fontSize: 10, height: 1),
        ),
        pw.SizedBox(height: 2),
        pw.Center(
          child: pw.Text(
            banner['title'] as String,
            style: pw.TextStyle(
              fontSize: _title,
              fontWeight: pw.FontWeight.bold,
              height: 1,
            ),
          ),
        ),
        pw.SizedBox(height: 2),
      ],
    );
  }

  static List<_Span> _spans(List raw, String Function(String) visible) => [
    for (final item in raw)
      if (item is String)
        _Span(visible(item))
      else
        _Span(
          visible(item['text'] as String? ?? ''),
          flex: item['flex'] as int? ?? 1,
          bold: item['bold'] == true,
        ),
  ];

  static pw.Widget _paragraph(
    String text,
    String kind,
    pw.TextStyle body,
    pw.TextStyle section,
  ) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 1.1),
    child: pw.Text(text, style: kind == 'section' ? section : body),
  );

  static pw.Widget _fill(
    List<_Span> parts,
    pw.TextStyle body,
    pw.TextStyle section,
  ) {
    final written = parts.fold<int>(0, (sum, part) => sum + part.text.length);
    if (written > 115) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 1.1),
        child: pw.RichText(
          text: pw.TextSpan(
            children: [
              for (final part in parts)
                pw.TextSpan(text: part.text, style: part.bold ? section : body),
            ],
          ),
        ),
      );
    }
    final dots = pw.TextStyle(fontSize: _body, height: 1, letterSpacing: 0.8);
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 0.8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          for (final part in parts) ...[
            if (part.text.isNotEmpty)
              pw.Text(part.text, style: part.bold ? section : body),
            if (part.flex > 0)
              pw.Expanded(
                flex: part.flex,
                child: pw.Text(
                  '.' * 240,
                  maxLines: 1,
                  softWrap: false,
                  overflow: pw.TextOverflow.clip,
                  style: dots,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Span {
  const _Span(this.text, {this.flex = 1, this.bold = false});
  final String text;
  final int flex;
  final bool bold;
}
