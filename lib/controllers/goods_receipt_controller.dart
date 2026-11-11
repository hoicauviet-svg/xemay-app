import 'package:flutter/foundation.dart';
import '../models/goods_receipt/goods_receipt_models.dart';
import '../models/inventory/inventory_models.dart';
import '../models/repositories/directory_repository.dart';

/// Manages receipt drafts and validation.
class GoodsReceiptController extends ChangeNotifier {
  GoodsReceiptController(
    this.type, {
    this.targetBatchId,
    this.directoryRepository,
  }) {
    _single = [ReceiptLineDraft(_nextId++)];
    _batch = [ReceiptLineDraft(_nextId++)];
  }
  final ReceiptProductType type;
  final DirectoryRepository? directoryRepository;
  List<VehicleBrand> brands = [];
  bool brandsLoading = false, _disposed = false;
  String? brandsError;
  Future<void> loadBrands() async {
    if (!type.isVehicle ||
        directoryRepository == null ||
        brandsLoading ||
        _disposed) {
      return;
    }
    brandsLoading = true;
    brandsError = null;
    notifyListeners();
    try {
      final result = await directoryRepository!.vehicleBrands();
      if (_disposed) return;
      brands = result;
    } catch (_) {
      if (_disposed) return;
      brandsError = 'Chưa tải được hãng xe. Bấm thử lại.';
    }
    brandsLoading = false;
    notifyListeners();
  }

  void selectBrand(ReceiptLineDraft line, int? id) => updateLine(line, (d) {
    d.brandId = id;
    d.brandName = id == null ? '' : brands.firstWhere((b) => b.id == id).name;
  });
  static String? optionalMoneyError(String text) {
    if (text.trim().isEmpty) return null;
    final value = int.tryParse(text.trim());
    return RegExp(r'^\d+$').hasMatch(text.trim()) && value != null && value >= 0
        ? null
        : 'Nhập số tiền không âm hoặc để trống';
  }

  final int? targetBatchId;
  ReceiptMode _mode = ReceiptMode.single;
  int _nextId = 1;
  late final List<ReceiptLineDraft> _single, _batch;
  DateTime date = DateTime.now();
  String partner = '', notes = '', carrier = '';
  String? _enteredPaidAmount;
  String get paidAmount => _enteredPaidAmount ?? '$total';
  set paidAmount(String value) => _enteredPaidAmount = value;
  String? carrierId;
  int get singlePaid => int.tryParse(paidAmount.trim()) ?? 0;
  int get singleRemaining => total - singlePaid;
  void setPaidAmount(String value) {
    paidAmount = value;
    notifyListeners();
  }

  void selectCarrier(String id, String name) {
    carrierId = id;
    carrier = name;
    notifyListeners();
  }

  void changeCarrier(String name) {
    carrierId = null;
    carrier = name;
    notifyListeners();
  }

  String? singlePaymentError(String? value) {
    final text = (value ?? '').trim();
    final amount = int.tryParse(text);
    if (!RegExp(r'^\d+$').hasMatch(text) || amount == null || amount < 0) {
      return 'Nhập số tiền không âm';
    }
    if (amount > total) return 'Số tiền đã trả không được vượt tổng tiền nhập';
    return null;
  }

  String? partnerId;
  final batch = BatchReceiptDraft();
  bool _batchConfirmed = false;
  bool get isBatchConfirmed => _batchConfirmed;
  bool get showProductForm => _mode == ReceiptMode.single || _batchConfirmed;
  int get batchQuantity => int.tryParse(batch.quantity) ?? 0;
  int get batchTotal => int.tryParse(batch.totalAmount) ?? 0;
  int get batchPaid => int.tryParse(batch.paidAmount) ?? 0;
  int get batchRemaining => batchTotal - batchPaid;
  bool get canAddLine =>
      _mode == ReceiptMode.batch &&
      _batchConfirmed &&
      (!type.isVehicle || _batch.length < batchQuantity);

  ReceiptMode get mode => _mode;
  List<ReceiptLineDraft> get lines =>
      List.unmodifiable(_mode == ReceiptMode.single ? _single : _batch);
  int quantityOf(ReceiptLineDraft line) =>
      type.isVehicle ? 1 : int.tryParse(line.quantity.trim()) ?? 0;
  int amountOf(ReceiptLineDraft line) =>
      quantityOf(line) * (int.tryParse(line.unitPrice.trim()) ?? 0);
  int get total => lines.fold(0, (sum, line) => sum + amountOf(line));
  int get totalQuantity => lines.fold(0, (sum, line) => sum + quantityOf(line));

  void setMode(ReceiptMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }

  void setDate(DateTime value) {
    date = value;
    if (_mode == ReceiptMode.batch) _batchConfirmed = false;
    notifyListeners();
  }

  void updateLine(
    ReceiptLineDraft line,
    void Function(ReceiptLineDraft) update,
  ) {
    if (!showProductForm || !lines.contains(line)) return;
    update(line);
    notifyListeners();
  }

  void addLine() {
    if (!canAddLine) return;
    _batch.add(ReceiptLineDraft(_nextId++));
    notifyListeners();
  }

  void removeLine(ReceiptLineDraft line) {
    if (_mode != ReceiptMode.batch || !_batchConfirmed || _batch.length <= 1) {
      return;
    }
    _batch.remove(line);
    notifyListeners();
  }

  void updateBatch(void Function(BatchReceiptDraft) update) {
    update(batch);
    _batchConfirmed = false;
    notifyListeners();
  }

  void selectBatchPartner(String id, String name) => updateBatch((d) {
    d.partnerId = id;
    d.origin = name;
  });
  void selectBatchCarrier(String id, String name) => updateBatch((d) {
    d.carrierId = id;
    d.deliveredBy = name;
  });
  void changeBatchPartner(String name) => updateBatch((d) {
    d.partnerId = null;
    d.origin = name;
  });
  void changeBatchCarrier(String name) => updateBatch((d) {
    d.carrierId = null;
    d.deliveredBy = name;
  });
  void selectPartner(String id, String name) {
    partnerId = id;
    partner = name;
    notifyListeners();
  }

  void changePartner(String name) {
    partnerId = null;
    partner = name;
    notifyListeners();
  }

  String? validateBatch() {
    if (batchQuantity <= 0) return 'Số lượng lô phải lớn hơn 0.';
    final total = int.tryParse(batch.totalAmount);
    if (total == null || total < 0) return 'Vui lòng nhập tổng tiền lô hợp lệ.';
    if (batch.deliveredBy.trim().isEmpty || batch.carrierId == null) {
      return 'Vui lòng chọn vận chuyển từ danh mục hoặc bấm + để thêm.';
    }
    if (batch.origin.trim().isEmpty || batch.partnerId == null) {
      return 'Vui lòng chọn đối tác / nhà cung cấp từ danh mục hoặc bấm + để thêm.';
    }
    final paid = int.tryParse(batch.paidAmount);
    if (paid == null || paid < 0) return 'Số tiền đã trả không hợp lệ.';
    if (paid > total) return 'Số tiền đã trả không được lớn hơn tổng tiền lô.';
    return null;
  }

  String? confirmBatch() {
    final error = validateBatch();
    if (error != null) return error;
    _batchConfirmed = true;
    notifyListeners();
    return null;
  }

  void editBatch() {
    _batchConfirmed = false;
    notifyListeners();
  }

  BatchReceiptInfo get batchInfo => BatchReceiptInfo(
    quantity: batchQuantity,
    totalAmount: batchTotal,
    deliveredBy: batch.deliveredBy.trim(),
    origin: batch.origin.trim(),
    date: date,
    paidAmount: batchPaid,
    partnerId: batch.partnerId,
    carrierId: batch.carrierId,
  );

  String? validate() {
    if (_mode == ReceiptMode.single && targetBatchId == null) {
      if (carrier.trim().isNotEmpty && carrierId == null) {
        return 'Vui lòng chọn vận chuyển từ danh mục hoặc bấm + để thêm.';
      }
      final paymentError = singlePaymentError(paidAmount);
      if (paymentError != null) return paymentError;
    }

    if (_mode == ReceiptMode.single &&
        targetBatchId == null &&
        partner.trim().isNotEmpty &&
        partnerId == null) {
      return 'Vui lòng chọn đối tác / nhà cung cấp từ danh mục.';
    }
    if (_mode == ReceiptMode.batch) {
      final error = validateBatch();
      if (error != null) return error;
      if (!_batchConfirmed) {
        return 'Vui lòng hoàn tất thông tin lô trước khi thêm sản phẩm.';
      }
      if (totalQuantity > batchQuantity) {
        return 'Số lượng sản phẩm vượt số lượng đã khai báo của lô.';
      }
    }
    final frames = <String>{}, engines = <String>{};
    for (final line in lines) {
      if (line.name.trim().isEmpty) {
        return 'Vui lòng nhập tên cho từng dòng hàng.';
      }
      for (final cost in line.costs) {
        if (cost.amount.trim().isEmpty ||
            optionalMoneyError(cost.amount) != null) {
          return 'Vui lòng nhập số tiền chi phí hợp lệ.';
        }
      }
      final price = int.tryParse(line.unitPrice.trim());
      if (price == null || price < 0) {
        return 'Giá nhập phải là số nguyên không âm.';
      }
      if (quantityOf(line) <= 0) return 'Số lượng phải lớn hơn 0.';
      if (optionalMoneyError(line.salePrice) != null) {
        return 'Giá bán không hợp lệ.';
      }
      if (type == ReceiptProductType.newVehicle &&
          optionalMoneyError(line.registrationFee) != null) {
        return 'Tiền đăng ký không hợp lệ.';
      }
      if (!type.isVehicle && line.unit.trim().isEmpty) {
        return 'Vui lòng nhập đơn vị tính.';
      }
      if (type == ReceiptProductType.newVehicle) {
        final frame = line.frameNumber.trim().toUpperCase();
        final engine = line.engineNumber.trim().toUpperCase();
        if (frame.isNotEmpty && !frames.add(frame)) {
          return 'Số khung bị trùng trong phiếu nhập.';
        }
        if (engine.isNotEmpty && !engines.add(engine)) {
          return 'Số máy bị trùng trong phiếu nhập.';
        }
      }
    }
    return null;
  }

  ReceiptPreview preview() {
    final error = validate();
    if (error != null) throw StateError(error);
    return ReceiptPreview(
      type: type,
      batchId: targetBatchId,
      paidAmount: mode == ReceiptMode.single && targetBatchId == null
          ? singlePaid
          : 0,
      carrier: mode == ReceiptMode.single && targetBatchId == null
          ? carrier.trim()
          : '',
      carrierId: mode == ReceiptMode.single && targetBatchId == null
          ? carrierId
          : null,
      partnerId: mode == ReceiptMode.batch ? batch.partnerId : partnerId,
      mode: mode,
      date: date,
      partner: mode == ReceiptMode.batch ? batch.origin.trim() : partner.trim(),
      batchInfo: mode == ReceiptMode.batch ? batchInfo : null,
      notes: notes.trim(),
      lines: [
        for (final line in lines)
          ReceiptLine(
            costs: List.unmodifiable(
              line.costs.map(
                (c) => ReceiptCost(
                  c.date,
                  int.parse(c.amount.trim()),
                  c.notes.trim(),
                ),
              ),
            ),
            name: line.name.trim(),
            quantity: quantityOf(line),
            unitPrice: int.parse(line.unitPrice.trim()),
            frameNumber: type == ReceiptProductType.newVehicle
                ? line.frameNumber.trim()
                : '',
            engineNumber: type == ReceiptProductType.newVehicle
                ? line.engineNumber.trim()
                : '',
            plate: line.plate.trim(),
            color: type.isVehicle ? line.color.trim() : '',
            brandId: type.isVehicle ? line.brandId : null,
            brandName: type.isVehicle ? line.brandName : '',
            salePrice: line.salePrice.trim().isEmpty
                ? null
                : int.parse(line.salePrice.trim()),
            registrationFee:
                type == ReceiptProductType.newVehicle &&
                    line.registrationFee.trim().isNotEmpty
                ? int.parse(line.registrationFee.trim())
                : null,
            vehicleNotes: type == ReceiptProductType.usedVehicle
                ? line.vehicleNotes.trim()
                : '',
            productCode: type.isVehicle ? '' : line.productCode.trim(),
            unit: type.isVehicle ? 'chiếc' : line.unit.trim(),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
