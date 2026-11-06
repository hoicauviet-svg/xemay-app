import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import '../models/reports/report_models.dart';

class ReportExcelEncoder {
  /// Minimal OOXML workbook using typed cells; user text is never a formula.
  static Uint8List encode(
    ReportKind kind,
    ReportSection section,
    ReportRange range,
    DateTime loadedAt, {
    String? title,
  }) {
    if (section.rows.length > 1048500) {
      throw StateError('Báo cáo vượt số dòng hỗ trợ của Excel.');
    }
    final count = section.columns.length;
    final last = _column(count - 1);
    final rows = StringBuffer(), merges = <String>[];
    var row = 0;
    void merged(String text, {int style = 3, double? height}) {
      row++;
      final h =
          height ??
          (text
                          .split('\n')
                          .fold<int>(
                            0,
                            (sum, line) =>
                                sum + (line.length / 110).ceil().clamp(1, 100),
                          ) *
                      16 +
                  10)
              .clamp(26, 409)
              .toDouble();
      rows.write(
        '<row r="$row" ht="$h" customHeight="1">${_cell('A$row', text, style)}</row>',
      );
      if (count > 1) merges.add('A$row:$last$row');
    }

    merged(
      'BÁO CÁO ${(title ?? kind.label).toUpperCase()}',
      style: 1,
      height: 32,
    );
    final date = DateFormat('dd/MM/yyyy');
    merged(
      kind.current
          ? 'Số dư hiện tại'
          : range.from == null && range.to == null
          ? 'Tất cả thời gian'
          : 'Từ ${range.from == null ? '' : date.format(range.from!)} đến ${range.to == null ? '' : date.format(range.to!)}',
    );
    merged('Cập nhật: ${DateFormat('dd/MM/yyyy HH:mm').format(loadedAt)}');
    row++;
    merged('Tổng hợp', style: 1, height: 28);
    for (final entry in section.totals.entries) {
      row++;
      final isCount =
          kind == ReportKind.stock ||
          [
            'Số đơn',
            'Số lô',
            'Số lượng',
            'Phiếu mới',
            'Phiếu đang cầm',
            'Tồn kho',
          ].contains(entry.key);
      rows.write(
        '<row r="$row" ht="26" customHeight="1">${_cell('A$row', entry.key, 3)}${_cell('C$row', entry.value, isCount ? 6 : 4)}</row>',
      );
      merges.add('A$row:B$row');
      if (count > 3) merges.add('C$row:$last$row');
    }
    for (final note in section.notes) {
      merged(note);
    }
    row++;
    final header = ++row;
    rows.write('<row r="$row" ht="42" customHeight="1">');
    for (var i = 0; i < count; i++) {
      rows.write(_cell('${_column(i)}$row', section.columns[i].label, 2));
    }
    rows.write('</row>');
    for (final record in section.rows) {
      row++;
      var lines = 1;
      for (var i = 0; i < count; i++) {
        final value = record[i];
        if (value is String) {
          final width = (section.columns[i].width / 7).clamp(10, 80) - 2;
          final n = value
              .split('\n')
              .fold<int>(
                0,
                (sum, line) =>
                    sum + (line.runes.length / width).ceil().clamp(1, 1000),
              );
          if (n > lines) lines = n;
        }
      }
      final height = (lines * 16 + 10).clamp(26, 409);
      rows.write('<row r="$row" ht="$height" customHeight="1">');
      for (var i = 0; i < count; i++) {
        final column = section.columns[i], value = record[i];
        final isId = column.label.startsWith('Mã');
        rows.write(
          _cell(
            '${_column(i)}$row',
            isId && value != null ? '$value' : value,
            isId
                ? 3
                : value is DateTime
                ? 5
                : column.money
                ? 4
                : value is num
                ? 6
                : 3,
          ),
        );
      }
      rows.write('</row>');
    }
    final sheet = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><dimension ref="A1:$last$row"/><sheetViews><sheetView workbookViewId="0" showGridLines="0"><pane ySplit="$header" topLeftCell="A${header + 1}" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><sheetFormatPr defaultRowHeight="26"/><cols>${[for (var i = 0; i < count; i++) '<col min="${i + 1}" max="${i + 1}" width="${(section.columns[i].width / 7).clamp(10, 80)}" customWidth="1"/>'].join()}</cols><sheetData>$rows</sheetData><autoFilter ref="A$header:$last$row"/>${merges.isEmpty ? '' : '<mergeCells count="${merges.length}">${merges.map((m) => '<mergeCell ref="$m"/>').join()}</mergeCells>'}<pageMargins left="0.3" right="0.3" top="0.5" bottom="0.5" header="0.2" footer="0.2"/><pageSetup paperSize="9" orientation="landscape" fitToWidth="1" fitToHeight="0"/></worksheet>''';
    final files = <String, String>{
      '[Content_Types].xml':
          '''<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>''',
      '_rels/.rels':
          '''<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>''',
      'xl/workbook.xml':
          '''<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="${_escape(title ?? kind.label)}" sheetId="1" r:id="rId1"/></sheets></workbook>''',
      'xl/_rels/workbook.xml.rels':
          '''<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>''',
      'xl/styles.xml': _styles,
      'xl/worksheets/sheet1.xml': sheet,
    };
    final archive = Archive();
    for (final entry in files.entries) {
      final bytes = utf8.encode(entry.value);
      archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  static String _column(int index) {
    var n = index + 1, result = '';
    while (n > 0) {
      n--;
      result = String.fromCharCode(65 + n % 26) + result;
      n ~/= 26;
    }
    return result;
  }

  static String _escape(String value) => value
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
  static String _cell(String address, dynamic value, int style) {
    if (value == null || value is num && !value.isFinite) {
      return '<c r="$address" s="$style"/>';
    }
    if (value is DateTime) {
      final day = DateTime.utc(value.year, value.month, value.day);
      var serial = day.difference(DateTime.utc(1899, 12, 30)).inDays;
      if (day.isBefore(DateTime.utc(1900, 3, 1))) serial--;
      return '<c r="$address" s="$style"><v>$serial</v></c>';
    }
    if (value is num) return '<c r="$address" s="$style"><v>$value</v></c>';
    return '<c r="$address" s="$style" t="inlineStr"><is><t xml:space="preserve">${_escape('$value')}</t></is></c>';
  }

  static const _styles =
      '''<?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="2"><numFmt numFmtId="164" formatCode="#,##0.##&quot; đ&quot;"/><numFmt numFmtId="165" formatCode="dd/mm/yyyy"/></numFmts><fonts count="3"><font><sz val="11"/><name val="Arial"/></font><font><b/><sz val="16"/><color rgb="FF176455"/><name val="Arial"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Arial"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF176455"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="7"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf><xf numFmtId="0" fontId="2" fillId="2" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf><xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf><xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyAlignment="1"><alignment vertical="top"/></xf><xf numFmtId="3" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyAlignment="1"><alignment vertical="top"/></xf></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>''';
}
