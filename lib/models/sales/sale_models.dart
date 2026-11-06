class SaleDraft {
  SaleDraft({
    required this.lines,
    required this.date,
    required this.discount,
    required this.paid,
    this.customerId,
    this.notes = '',
    this.paymentDueDate,
    this.interestDate,
    this.debtDatesVersion = 1,
  });
  final List<SaleLine> lines;
  final DateTime date;
  final DateTime? paymentDueDate, interestDate;
  final int debtDatesVersion;
  final int discount, paid;
  final int? customerId;
  final String notes;
  static const maxMoney = 1000000000000000;
  int get subtotal => lines.fold(0, (sum, line) => sum + line.total);
  int get total => subtotal - discount;
  int get collected => paid < total ? paid : total;
  int get due => total - collected;
  int get change => paid - collected;
  String? get error {
    if (lines.isEmpty) return 'Vui lòng thêm sản phẩm hoặc dịch vụ.';
    if (lines.length > 1000 || notes.length > 10000) {
      return 'Đơn có quá nhiều mặt hàng hoặc ghi chú quá dài.';
    }
    if (lines.map((l) => l.key).toSet().length != lines.length) {
      return 'Đơn có dòng sản phẩm bị trùng.';
    }
    if (lines.any((l) => l.error != null)) {
      return 'Thông tin sản phẩm hoặc giá bán không hợp lệ.';
    }
    if (discount < 0 ||
        paid < 0 ||
        subtotal > maxMoney ||
        paid > maxMoney ||
        discount > subtotal) {
      return 'Số tiền đơn hàng không hợp lệ.';
    }
    if (due > 0 && customerId == null) {
      return 'Vui lòng chọn khách hàng để ghi nhận công nợ.';
    }
    if (due > 0 && debtDatesVersion >= 1) {
      if (paymentDueDate == null || interestDate == null) {
        return 'Vui lòng chọn ngày hẹn thanh toán và ngày tính lãi.';
      }
      if (calendarDate(paymentDueDate!).isBefore(storedDate) ||
          calendarDate(interestDate!).isBefore(storedDate)) {
        return 'Ngày hẹn thanh toán và ngày tính lãi không được trước ngày bán.';
      }
    }
    return null;
  }

  static DateTime calendarDate(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);
  static String dateText(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  DateTime? get storedDueDate =>
      due > 0 && paymentDueDate != null ? calendarDate(paymentDueDate!) : null;
  DateTime? get storedInterestDate =>
      due > 0 && interestDate != null ? calendarDate(interestDate!) : null;

  Map<String, dynamic> toMap() => {
    'IdKH': customerId,
    if (debtDatesVersion >= 1) ...{
      'PhienBanNgayCongNo': debtDatesVersion,
      'NgayHen': storedDueDate == null ? null : dateText(storedDueDate!),
      'NgayTinhLai': storedInterestDate == null
          ? null
          : dateText(storedInterestDate!),
    },
    'NgayBan':
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
    'GhiChu': notes,
    'GiamGia': discount,
    'SoTienKhachDua': paid,
    'ChiTiet': lines.map((l) => l.toMap()).toList(),
  };
  factory SaleDraft.fromMap(Map<String, dynamic> row) => SaleDraft(
    lines: (row['ChiTiet'] as List)
        .map((l) => SaleLine.fromMap(Map<String, dynamic>.from(l as Map)))
        .toList(),
    date: DateTime.parse(row['NgayBan'] as String),
    paymentDueDate: row['NgayHen'] == null
        ? null
        : DateTime.parse(row['NgayHen'] as String),
    interestDate: row['NgayTinhLai'] == null
        ? null
        : DateTime.parse(row['NgayTinhLai'] as String),
    debtDatesVersion: row['PhienBanNgayCongNo'] as int? ?? 0,
    discount: row['GiamGia'] as int,
    paid: row['SoTienKhachDua'] as int,
    customerId: row['IdKH'] as int?,
    notes: row['GhiChu'] as String,
  );
  DateTime get storedDate => DateTime.utc(date.year, date.month, date.day);
}

class SaleLine {
  const SaleLine({
    required this.kind,
    required this.name,
    required this.quantity,
    required this.price,
    this.productId,
    this.vehicleId,
    this.serviceId,
  });
  final String kind, name;
  final int quantity, price;
  final int? productId, vehicleId;
  final String? serviceId;
  String get key =>
      '$kind-${kind == 'xe'
          ? vehicleId
          : kind == 'dich_vu'
          ? serviceId
          : productId}';
  int get total => price * quantity;
  String? get error {
    if (name.trim().isEmpty ||
        quantity < 1 ||
        price < 0 ||
        price > SaleDraft.maxMoney ||
        quantity > 1000000 ||
        price > SaleDraft.maxMoney ~/ quantity) {
      return 'Dòng hàng không hợp lệ';
    }
    return switch (kind) {
      'xe' =>
        productId == null ||
                vehicleId == null ||
                quantity != 1 ||
                serviceId != null
            ? 'Xe không hợp lệ'
            : null,
      'phu_tung' =>
        productId == null || vehicleId != null || serviceId != null
            ? 'Phụ tùng không hợp lệ'
            : null,
      'dich_vu' =>
        serviceId == null ||
                serviceId!.isEmpty ||
                productId != null ||
                vehicleId != null
            ? 'Dịch vụ không hợp lệ'
            : null,
      _ => 'Loại hàng không hợp lệ',
    };
  }

  Map<String, dynamic> toMap() => {
    'LoaiSanPham': kind,
    'TenSanPham': name,
    'IdSanPham': productId,
    'IdXe': vehicleId,
    'IdDichVu': serviceId,
    'SoLuong': quantity,
    'DonGia': price,
  };
  factory SaleLine.fromMap(Map<String, dynamic> row) => SaleLine(
    kind: row['LoaiSanPham'] as String,
    name: row['TenSanPham'] as String,
    quantity: row['SoLuong'] as int,
    price: row['DonGia'] as int,
    productId: row['IdSanPham'] as int?,
    vehicleId: row['IdXe'] as int?,
    serviceId: row['IdDichVu'] as String?,
  );
}

class SaleSaveResult {
  const SaleSaveResult(this.invoiceId, {this.requestId});
  final int invoiceId;
  final String? requestId;
}

class SaleSaveException implements Exception {
  const SaleSaveException(this.message, {this.uncertain = false});
  final String message;
  final bool uncertain;
}
