import 'report_excel_encoder.dart';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:intl/intl.dart';
import '../models/reports/report_models.dart';

/// Exports the displayed report snapshot. It never reloads or changes source data.
class ReportExcelService {
  static Future<bool> save(
    ReportKind kind,
    ReportSection section,
    ReportRange range,
    DateTime loadedAt,
  ) => _save(kind, section, range, loadedAt);

  static Future<bool> saveNamed(
    String title,
    ReportSection section,
    DateTime loadedAt, {
    ReportKind kind = ReportKind.debts,
  }) => _save(kind, section, ReportRange(), loadedAt, title: title);

  static Future<bool> _save(
    ReportKind kind,
    ReportSection section,
    ReportRange range,
    DateTime loadedAt, {
    String? title,
  }) async {
    final name =
        'Bao_cao_${title?.replaceAll(' ', '_') ?? kind.name}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
    final target = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Excel',
          extensions: ['xlsx'],
          uniformTypeIdentifiers: ['org.openxmlformats.spreadsheetml.sheet'],
        ),
      ],
    );
    if (target == null) return false;
    final bytes = await Isolate.run(
      () => ReportExcelEncoder.encode(
        kind,
        section,
        range,
        loadedAt,
        title: title,
      ),
    );
    final path = target.path.toLowerCase().endsWith('.xlsx')
        ? target.path
        : '${target.path}.xlsx';
    await XFile.fromData(
      bytes,
      name: name,
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    ).saveTo(path);
    return true;
  }

  static Uint8List encode(
    ReportKind kind,
    ReportSection section,
    ReportRange range,
    DateTime loadedAt,
  ) => ReportExcelEncoder.encode(kind, section, range, loadedAt);
}
