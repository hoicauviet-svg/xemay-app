import '../reports/report_models.dart';

abstract class ReportsRepository {
  Future<ReportsData> load(ReportRange range);
  Future<void> close();
}
