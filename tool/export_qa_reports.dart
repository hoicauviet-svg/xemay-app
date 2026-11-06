import 'dart:convert';
import 'dart:io';
import 'package:xemay_app/services/mongo_reports_repository.dart';
import 'package:xemay_app/models/reports/report_models.dart';
import 'package:xemay_app/services/report_excel_encoder.dart';

Map<String, dynamic> section(ReportSection s) => {
  'columns': s.columns.map((c) => c.label).toList(),
  'rows': s.rows,
  'totals': s.totals,
  'notes': s.notes,
};
Future<void> main(List<String> args) async {
  final repo = MongoReportsRepository(uri: args[0]);
  final out = Directory(args[1]);
  out.createSync(recursive: true);
  try {
    for (final period in {
      'all': ReportRange(),
      'november': ReportRange(
        from: DateTime(2026, 11, 1),
        to: DateTime(2026, 11, 30),
      ),
      'today': ReportRange(
        from: DateTime(2026, 11, 5),
        to: DateTime(2026, 11, 5),
      ),
    }.entries) {
      final data = await repo.load(period.value);
      final json = {
        'sections': {
          for (final e in data.sections.entries) e.key.name: section(e.value),
        },
        'salesGroups': {
          for (final e in data.salesByGroup.entries)
            e.key.name: section(e.value),
        },
        'receiptGroups': {
          for (final e in data.receiptsByGroup.entries)
            e.key.name: section(e.value),
        },
        'customerAging': {
          'within': data.customerAging.within,
          'overdue': data.customerAging.overdue,
          'undated': data.customerAging.undated,
        },
        'pawnAging': {
          'within': data.pawnAging.within,
          'overdue': data.pawnAging.overdue,
          'undated': data.pawnAging.undated,
        },
      };
      File('${out.path}/reports-${period.key}.json').writeAsStringSync(
        JsonEncoder.withIndent(
          '  ',
          (v) => v is DateTime ? v.toIso8601String() : v.toString(),
        ).convert(json),
      );
      for (final e in data.sections.entries) {
        File('${out.path}/${period.key}-${e.key.name}.xlsx').writeAsBytesSync(
          ReportExcelEncoder.encode(
            e.key,
            e.value,
            period.value,
            DateTime.now(),
          ),
        );
      }
    }
    stdout.writeln(
      'Exported all report sections, product groups, aging and XLSX for all/November/today.',
    );
  } finally {
    await repo.close();
  }
}
