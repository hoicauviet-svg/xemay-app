import 'package:xemay_app/models/finance/finance_list_report.dart';
import 'package:xemay_app/services/report_excel_encoder.dart';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/models/reports/report_models.dart';
import 'package:xemay_app/services/report_excel_service.dart';

void main() {
  test(
    'Finance exports use their own title and preserve all filtered totals',
    () {
      final loans = FinanceListReport.funding(
        [
          {
            'IdVayVon': 1,
            'DoiTac': 'Đối tác',
            'SoTienVay': 1000000,
            'TongConNo': 700000,
          },
        ],
        status: 'all',
        search: 'Đối tác',
      );
      final old = FinanceListReport.opening([
        {
          'Id': 1,
          'KhachHang': {'TenKhachHang': 'Khách'},
          'TongNo': 1000000,
          'SoTienDaTra': 300000,
          'SoCoNo': 700000,
        },
      ]);
      for (final entry in {'Vay vốn': loans, 'Nợ cũ': old}.entries) {
        final zip = ZipDecoder().decodeBytes(
          ReportExcelEncoder.encode(
            ReportKind.debts,
            entry.value,
            ReportRange(),
            DateTime(2026, 11, 4),
            title: entry.key,
          ),
        );
        expect(
          utf8
              .decode(zip.findFile('xl/workbook.xml')!.content as List<int>)
              .contains('name="${entry.key}"'),
          true,
        );
        final sheet = utf8.decode(
          zip.findFile('xl/worksheets/sheet1.xml')!.content as List<int>,
        );
        expect(sheet.contains('BÁO CÁO ${entry.key.toUpperCase()}'), true);
        expect(sheet.contains('<v>700000</v>'), true);
      }
      expect(loans.notes.single.contains('Tất cả; Tìm kiếm: Đối tác'), true);
      expect(loans.rows.single[3], 300000);
      expect(old.totals['Còn nợ'], 700000);
    },
  );

  test(
    'Excel exports every voucher with numeric money, real dates, multiline text and safe text values',
    () {
      final section = ReportSection(
        columns: const [
          ReportColumn('Mã'),
          ReportColumn('Ngày'),
          ReportColumn('Khách hàng'),
          ReportColumn('Sản phẩm / dịch vụ'),
          ReportColumn('Doanh thu', money: true),
        ],
        rows: [
          for (var i = 0; i < 40; i++)
            [
              12345 + i,
              DateTime.utc(2026, 11, 4),
              'Nguyễn Văn An & <B>',
              '=SUM(A1)\nDịch vụ: Thay dầu × 2',
              i == 0 ? null : 1000.5,
            ],
        ],
        totals: const {'Số đơn': 40, 'Doanh thu': null},
        notes: const ['Giữ dữ liệu thiếu dưới dạng ô trống.'],
      );
      final bytes = ReportExcelService.encode(
        ReportKind.sales,
        section,
        ReportRange(from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 4)),
        DateTime(2026, 11, 4, 12),
      );
      final archive = ZipDecoder().decodeBytes(bytes);
      String file(String name) =>
          utf8.decode(archive.findFile(name)!.content as List<int>);
      final sheet = file('xl/worksheets/sheet1.xml');
      expect(archive.findFile('[Content_Types].xml'), isNotNull);
      expect(sheet.contains('Nguyễn Văn An &amp; &lt;B&gt;'), isTrue);
      expect(sheet.contains('=SUM(A1)\nDịch vụ: Thay dầu × 2'), isTrue);
      expect(sheet.contains('<f'), isFalse);
      expect(
        RegExp(
          r'<c r="A\d+" s="3" t="inlineStr"><is><t xml:space="preserve">12\d{3}</t></is></c>',
        ).allMatches(sheet).length,
        40,
      );
      expect(sheet.contains('<v>1000.5</v>'), isTrue);
      expect(sheet.contains('<v>46330</v>'), isTrue);
      expect(sheet.contains('s="4"/>'), isTrue);
      expect(file('xl/styles.xml').contains('dd/mm/yyyy'), isTrue);
    },
  );
  test(
    'All report types produce named Excel workbooks including empty reports',
    () {
      final report = ReportCalculator.build(range: ReportRange(), source: {});
      for (final kind in report.sections.keys) {
        final archive = ZipDecoder().decodeBytes(
          ReportExcelService.encode(
            kind,
            report.sections[kind]!,
            ReportRange(),
            DateTime(2026, 11, 4),
          ),
        );
        final workbook = utf8.decode(
          archive.findFile('xl/workbook.xml')!.content as List<int>,
        );
        expect(workbook.contains('name="${kind.label}"'), isTrue);
      }
    },
  );
}
