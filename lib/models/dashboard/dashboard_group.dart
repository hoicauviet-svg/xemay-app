import 'dashboard_module.dart';

/// Business groups shared by the sidebar and section tabs.
enum DashboardGroup {
  products('Sản phẩm', [
    DashboardModule.newVehicles,
    DashboardModule.usedVehicles,
    DashboardModule.parts,
    DashboardModule.services,
  ]),
  customers('Khách hàng', [
    DashboardModule.customers,
    DashboardModule.customerMerge,
  ]),
  partners('Đối tác / nhà cung cấp', [
    DashboardModule.partners,
    DashboardModule.carriers,
  ]),
  pawn('Cầm đồ', [DashboardModule.pawnContracts]),
  finance('Tài chính', [
    DashboardModule.cashbook,
    DashboardModule.fundingLoans,
    DashboardModule.openingDebt,
  ]),
  reports('Báo cáo', [DashboardModule.reports]),
  settings('Cài đặt', [DashboardModule.settings]);

  const DashboardGroup(this.label, this.modules);
  final String label;
  final List<DashboardModule> modules;
}
