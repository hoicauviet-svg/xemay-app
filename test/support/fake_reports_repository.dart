import 'package:xemay_app/models/reports/report_models.dart';
import 'package:xemay_app/models/repositories/reports_repository.dart';

class FakeReportsRepository extends ReportsRepository {
  ReportRange? lastRange;
  bool fail = false;
  int loads = 0;
  Map<String, List<Map<String, dynamic>>> source = {};
  @override
  Future<ReportsData> load(ReportRange range) async {
    loads++;
    lastRange = range;
    if (fail) throw StateError('Unavailable');
    return ReportCalculator.build(range: range, source: source);
  }

  @override
  Future<void> close() async {}
}
