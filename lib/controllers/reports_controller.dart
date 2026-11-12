import '../models/maintenance/record_maintenance.dart';
import 'package:flutter/foundation.dart';
import '../models/reports/report_models.dart';
import '../models/repositories/reports_repository.dart';

class ReportsController extends ChangeNotifier {
  ReportsController(this.repository, {DateTime? now}) {
    final date = now ?? DateTime.now();
    range = ReportRange(from: date, to: date);
  }
  final ReportsRepository repository;
  late ReportRange range;
  ReportsData? data;
  bool loading = false, _disposed = false;
  int _request = 0;
  String? error;
  String cashType = 'all';
  ReportProductGroup salesGroup = ReportProductGroup.all,
      receiptsGroup = ReportProductGroup.all;
  void setProductGroup(ReportKind kind, ReportProductGroup group) {
    if (kind == ReportKind.sales) {
      salesGroup = group;
    } else {
      receiptsGroup = group;
    }
    notifyListeners();
  }

  String? cashCategory;
  List<String> get cashCategories => {
    for (final row
        in data?.sections[ReportKind.cash]?.rows ?? <List<dynamic>>[])
      if (cashType != 'all' &&
          row.length > 5 &&
          row[5] is String &&
          row[2] == (cashType == 'income' ? 'Thu' : 'Chi'))
        row[5] as String,
    ?cashCategory,
  }.toList()..sort();
  void setCashCategory(String? value) {
    cashCategory = value;
    notifyListeners();
  }

  ReportSection? section(ReportKind kind) {
    final source =
        kind == ReportKind.sales && salesGroup != ReportProductGroup.all
        ? data?.salesByGroup[salesGroup]
        : kind == ReportKind.receipts && receiptsGroup != ReportProductGroup.all
        ? data?.receiptsByGroup[receiptsGroup]
        : data?.sections[kind];
    if (source == null) return null;
    if (kind == ReportKind.cash) {
      final filtered = ReportCalculator.filterCash(
        source,
        cashType,
        category: cashCategory,
      );
      return filtered;
    }
    return source;
  }

  void setCashType(String value) {
    if (!['all', 'income', 'expense'].contains(value)) {
      throw ArgumentError.value(value);
    }
    if (cashType != value) cashCategory = null;
    cashType = value;
    notifyListeners();
  }

  Future<void> load() async {
    if (_disposed) return;
    final request = ++_request;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await repository.load(range);
      if (_disposed || request != _request) return;
      data = result;
    } catch (e) {
      if (_disposed || request != _request) return;
      error = e is RecordChangeException
          ? e.message
          : 'Chưa tải được báo cáo. Vui lòng thử lại.';
    }
    loading = false;
    notifyListeners();
  }

  void setRange(ReportRange value) {
    range = value;
    load();
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    super.dispose();
  }
}
