enum ReceiptMode { batch, single }

enum ReceiptProductType {
  newVehicle('Nhập xe mới'),
  usedVehicle('Mua xe cũ'),
  part('Nhập phụ tùng');

  const ReceiptProductType(this.title);
  final String title;
  bool get isVehicle => this != part;
}

class ReceiptCostDraft {
  DateTime date = DateTime.now();
  String amount = '', notes = '';
}

class ReceiptCost {
  const ReceiptCost(this.date, this.amount, this.notes);
  final DateTime date;
  final int amount;
  final String notes;
  Map<String, dynamic> toMap() => {
    'Ngay': DateTime.utc(date.year, date.month, date.day),
    'SoTien': amount,
    'GhiChu': notes,
  };
}

class ReceiptLineDraft {
  ReceiptLineDraft(this.id);
  final int id;
  final List<ReceiptCostDraft> costs = [];
  int get totalCosts =>
      costs.fold(0, (sum, c) => sum + (int.tryParse(c.amount) ?? 0));
  String name = '';
  String quantity = '1';
  String unitPrice = '';
  String frameNumber = '';
  String engineNumber = '';
  String plate = '';
  String color = '';
  int? brandId;
  String brandName = '';
  String salePrice = '',
      registrationFee = '',
      vehicleNotes = '',
      productCode = '';
  String unit = 'cái';
}

class ReceiptLine {
  const ReceiptLine({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.frameNumber,
    required this.engineNumber,
    required this.plate,
    this.color = '',
    this.costs = const [],
    this.brandId,
    this.brandName = '',
    this.salePrice,
    this.registrationFee,
    this.vehicleNotes = '',
    this.productCode = '',
    this.unit = 'cái',
  });
  final List<ReceiptCost> costs;
  int get totalCosts => costs.fold(0, (sum, c) => sum + c.amount);
  final String name, frameNumber, engineNumber, plate, color;
  final int quantity, unitPrice;
  final int? brandId, salePrice, registrationFee;
  final String brandName, vehicleNotes, productCode, unit;
  int get amount => quantity * unitPrice;

  Map<String, dynamic> toVehicleFields(
    ReceiptProductType type, {
    required int vehicleId,
    required int productId,
  }) {
    if (!type.isVehicle) throw StateError('Phụ tùng không tạo bản ghi xe');
    return {
      'IdXe': vehicleId,
      'IdSanPham': productId,
      'IdHangXe': brandId,
      'TenXe': name,
      'GiaNhap': unitPrice,
      'ChiPhi': costs.map((c) => c.toMap()).toList(),
      'TongChiPhi': totalCosts,
      'GiaBan': salePrice,
      'TinhTrang': true,
      'TinhTrangXe': type == ReceiptProductType.newVehicle ? 'moi' : 'cu',
      'LoaiSanPhamNguon': type == ReceiptProductType.newVehicle
          ? 'xe_moi'
          : 'xe_cu',
      'DonViTinh': 'chiếc',
      'QuanLyTonKho': 'tung_chiec',
    };
  }

  Map<String, dynamic> toVehicleDetailFields(
    ReceiptProductType type, {
    required int vehicleId,
    int? batchId,
  }) {
    if (type == ReceiptProductType.newVehicle) {
      return {
        'IdXe': vehicleId,
        'IdNhapHang': batchId,
        'SoKhung': frameNumber,
        'SoMay': engineNumber,
        'BienSo': plate,
        'MauSon': color,
        'TienDangKy': registrationFee,
        'TrangThai': null,
      };
    }
    if (type == ReceiptProductType.usedVehicle) {
      return {
        'IdXe': vehicleId,
        'BienSo': plate,
        'MauSon': color,
        'GhiChu': vehicleNotes,
      };
    }
    throw StateError('Phụ tùng không có chi tiết xe');
  }

  Map<String, dynamic> toCatalogFields(
    ReceiptProductType type, {
    required int productId,
    required String generatedCode,
  }) => {
    'IdSanPham': productId,
    'MaSanPham': productCode.isNotEmpty ? productCode : generatedCode,
    'TenSanPham': name,
    'LoaiSanPham': type.isVehicle ? 'xe' : 'phu_tung',
    'QuanLyTonKho': type.isVehicle ? 'tung_chiec' : 'so_luong',
    'DonViTinh': type.isVehicle ? 'chiếc' : unit,
    'IdHangXe': type.isVehicle ? brandId : null,
    'GiaBanThamKhao': type.isVehicle ? null : salePrice,
  };
  Map<String, dynamic> toPartStockFields({required int productId}) => {
    'IdSanPham': productId,
    'SoLuongTon': quantity,
    'GiaVonThamKhao': unitPrice,
  };
}

class ReceiptPreview {
  ReceiptPreview({
    required this.type,
    required this.mode,
    required this.date,
    required this.partner,
    required this.notes,
    required List<ReceiptLine> lines,
    this.paidAmount = 0,
    this.carrier = '',
    this.carrierId,
    this.batchInfo,
    this.batchId,
    this.partnerId,
  }) : lines = List.unmodifiable(lines);
  final ReceiptProductType type;
  final ReceiptMode mode;
  final DateTime date;
  final String partner, notes, carrier;
  final String? carrierId;
  final int paidAmount;
  int get remainingAmount => total - paidAmount;
  final List<ReceiptLine> lines;
  final BatchReceiptInfo? batchInfo;
  final int? batchId;
  final String? partnerId;
  int get total => lines.fold(0, (sum, line) => sum + line.amount);
  int get quantity => lines.fold(0, (sum, line) => sum + line.quantity);
}

/// Editable fields corresponding to NhapHang. The database assigns IdNhapHang.
class BatchReceiptDraft {
  String quantity = '';
  String totalAmount = '';
  String deliveredBy = '';
  String origin = '';
  String paidAmount = '0';
  String? partnerId, carrierId;
}

class BatchReceiptInfo {
  const BatchReceiptInfo({
    required this.quantity,
    required this.totalAmount,
    required this.deliveredBy,
    required this.origin,
    required this.date,
    required this.paidAmount,
    this.partnerId,
    this.carrierId,
  });
  final int quantity, totalAmount, paidAmount;
  final String deliveredBy, origin;
  final DateTime date;
  final String? partnerId, carrierId;
  int get remainingAmount => totalAmount - paidAmount;

  Map<String, Object> toDatabaseFields() => {
    'SoLuong': quantity,
    'SoTien': totalAmount,
    'NguoiCho': deliveredBy,
    'NoiNhap': origin,
    'NgayNhap': DateTime.utc(date.year, date.month, date.day),
    'SoTienDaTra': paidAmount,
    'SoTienConNo': remainingAmount,
    'IdDoiTac': ?partnerId,
    'IdVanChuyen': ?carrierId,
  };
}
