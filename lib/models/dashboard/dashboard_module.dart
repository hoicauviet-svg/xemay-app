/// Child functions displayed as tabs inside dashboard groups.
enum DashboardModule {
  customers('Khách hàng'),
  customerMerge('Gộp khách hàng'),
  partners('Đối tác'),
  carriers('Vận chuyển'),
  newVehicles('Xe mới'),
  usedVehicles('Xe cũ'),
  parts('Phụ tùng'),
  receiptNewVehicles('Nhập xe mới'),
  receiptUsedVehicles('Mua xe cũ'),
  receiptParts('Nhập phụ tùng'),
  services('Dịch vụ'),
  customerDebt('Công nợ bán hàng'),
  supplierDebt('Công nợ nhập hàng'),
  pawnContracts('Cầm đồ'),
  cashbook('Thu chi'),
  fundingLoans('Vay vốn'),
  openingDebt('Nợ cũ'),
  reports('Báo cáo'),
  settings('Cài đặt'),
  vehicleBrands('Hãng xe'),
  localities('Xã / địa chỉ');

  const DashboardModule(this.label);
  final String label;
}

extension ProductModuleLabels on DashboardModule {
  String? get entryTitle => switch (this) {
    DashboardModule.newVehicles => 'Nhập xe mới',
    DashboardModule.usedVehicles => 'Mua xe cũ',
    DashboardModule.parts => 'Nhập phụ tùng',
    _ => null,
  };

  String get searchHint => switch (this) {
    DashboardModule.newVehicles => 'Tìm xe mới…',
    DashboardModule.usedVehicles => 'Tìm xe cũ…',
    DashboardModule.parts => 'Tìm phụ tùng…',
    _ => 'Tìm kiếm…',
  };
}
