import '../reports/report_models.dart';

abstract class ReportsRepository {
  Future<ReportsData> load(
    ReportRange range, {
    ReportOrderStatus orderStatus = ReportOrderStatus.completed,
  });
  Future<void> close();
}
