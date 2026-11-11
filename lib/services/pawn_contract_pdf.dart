import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/printing/pawn_contract_data.dart';

class PawnContractPdf {
  static Future<Uint8List> build(PawnContractData data) async {
    final template =
        jsonDecode(
              await rootBundle.loadString(
                'assets/templates/pawn_contract.json',
              ),
            )
            as Map<String, dynamic>;
    final regular = await rootBundle.load('assets/fonts/NotoSerif-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/NotoSerif-Bold.ttf');
    final italic = await rootBundle.load('assets/fonts/NotoSerif-Italic.ttf');
    final theme = pw.ThemeData.withFont(
      base: pw.Font.ttf(regular),
      bold: pw.Font.ttf(bold),
      italic: pw.Font.ttf(italic),
    );
    final values = data.values;
    final document = pw.Document(
      title: 'Hợp đồng cầm đồ #${data.id}',
      theme: theme,
    );
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(54, 24, 27, 24),
        theme: theme,
        build: (_) => [
          for (final paragraph in template['paragraphs'] as List)
            pw.Padding(
              padding: pw.EdgeInsets.only(
                bottom: paragraph['kind'] == 'title' ? 10 : 3,
              ),
              child: pw.Container(
                width: double.infinity,
                child: pw.Text(
                  (paragraph['text'] as String).replaceAllMapped(
                    RegExp(r'\{(\w+)\}'),
                    (m) => values[m[1]] ?? m[0]!,
                  ),
                  textAlign:
                      [
                        'title',
                        'header',
                        'subtitle',
                      ].contains(paragraph['kind'])
                      ? pw.TextAlign.center
                      : paragraph['kind'] == 'date'
                      ? pw.TextAlign.right
                      : pw.TextAlign.left,
                  style: pw.TextStyle(
                    fontSize: paragraph['kind'] == 'title'
                        ? 15
                        : paragraph['kind'] == 'header'
                        ? 12
                        : 11,
                    fontWeight:
                        [
                          'title',
                          'header',
                          'section',
                        ].contains(paragraph['kind'])
                        ? pw.FontWeight.bold
                        : pw.FontWeight.normal,
                  ),
                ),
              ),
            ),
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < 3; i++)
                  pw.Expanded(
                    child: pw.Column(
                      children: [
                        pw.Text(
                          template['signatures'][i] as String,
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 64),
                        if (i == 2)
                          pw.Text(
                            template['lenderName'] as String,
                            style: const pw.TextStyle(fontSize: 11),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    return document.save();
  }
}
