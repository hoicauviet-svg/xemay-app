import '../models/printing/sales_invoice_data.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:mongo_dart/mongo_dart.dart' show ObjectId;
import '../models/repositories/sales_repository.dart';
import '../models/sales/sale_models.dart';
import 'package:flutter/foundation.dart';
import '../models/repositories/customer_repository.dart';
import '../models/customers/customer_models.dart';
import 'cart_controller.dart';

class SalesController extends ChangeNotifier {
  SalesController(this.cart, this.customers, {this.salesRepository}) {
    cart.addListener(_cartChanged);
  }
  final CartController cart;
  final CustomerRepository customers;
  final SalesRepository? salesRepository;
  bool saving = false, awaitingConfirmation = false;
  String? saveError;
  int? lastSavedId;
  String? _requestId;
  SaleDraft? _pendingDraft;
  Timer? _saveRetry, _recoveryRetry;
  bool get editingLocked => saving || awaitingConfirmation;
  Map<String, dynamic>? customer;
  String customerQuery = '', discountText = '', paidText = '', notes = '';
  String? customerError;
  DateTime date = DateTime.now();
  DateTime? paymentDueDate, interestDate;
  bool get hasDebt => (due ?? 0) > 0;
  String? get dueDateError => !hasDebt
      ? null
      : paymentDueDate == null
      ? 'Chọn ngày hẹn thanh toán'
      : SaleDraft.calendarDate(
          paymentDueDate!,
        ).isBefore(SaleDraft.calendarDate(date))
      ? 'Ngày hẹn không được trước ngày bán'
      : null;
  String? get interestDateError => !hasDebt
      ? null
      : interestDate == null
      ? 'Chọn ngày tính lãi'
      : SaleDraft.calendarDate(
          interestDate!,
        ).isBefore(SaleDraft.calendarDate(date))
      ? 'Ngày tính lãi không được trước ngày bán'
      : null;
  void setPaymentDueDate(DateTime value) {
    paymentDueDate = value;
    notifyListeners();
  }

  void setInterestDate(DateTime value) {
    interestDate = value;
    notifyListeners();
  }

  int revision = 0;
  bool _disposed = false;
  void _cartChanged() {
    if (!_disposed) notifyListeners();
  }

  int? _amount(String text) => text.trim().isEmpty
      ? 0
      : RegExp(r'^\d+$').hasMatch(text.trim())
      ? int.tryParse(text.trim())
      : null;
  int? get subtotal =>
      cart.items.any(
        (i) =>
            i.unitPrice == null ||
            i.unitPrice! < 0 ||
            i.quantity < 1 ||
            i.unitPrice! > SaleDraft.maxMoney ~/ i.quantity,
      )
      ? null
      : cart.items.fold<int>(0, (sum, i) => sum + i.total!);
  int? get discount => _amount(discountText);
  int? get paid => _amount(paidText);
  String? get discountError => discount == null || discount! < 0
      ? 'Nhập số tiền giảm giá hợp lệ'
      : subtotal != null && discount! > subtotal!
      ? 'Giảm giá vượt quá tiền hàng'
      : null;
  String? get paidError =>
      paid == null || paid! < 0 ? 'Nhập số tiền thanh toán hợp lệ' : null;
  int? get total =>
      subtotal == null || discountError != null ? null : subtotal! - discount!;
  int? get due =>
      total == null || paidError != null ? null : math.max(0, total! - paid!);
  int? get change =>
      total == null || paidError != null ? null : math.max(0, paid! - total!);
  void setDiscount(String value) {
    discountText = value;
    notifyListeners();
  }

  void setPaid(String value) {
    paidText = value;
    notifyListeners();
  }

  void setDate(DateTime value) {
    date = value;
    notifyListeners();
  }

  void customerTextChanged(String value) {
    customerQuery = value;
    customer = null;
    customerError = null;
    notifyListeners();
  }

  void selectCustomer(Map<String, dynamic> value) {
    customer = Map.of(value);
    customerQuery = '${value['TenKhachHang']}';
    customerError = null;
    notifyListeners();
  }

  void clearCustomer() {
    customer = null;
    customerQuery = '';
    customerError = null;
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> searchCustomers(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final result = await customers.fetch(search: query);
      if (_disposed || customerQuery != query) return [];
      customerError = null;
      notifyListeners();
      return result.rows;
    } catch (_) {
      if (!_disposed && customerQuery == query) {
        customerError = 'Chưa tìm được khách hàng. Vui lòng thử lại.';
        notifyListeners();
      }
      return [];
    }
  }

  Future<Map<String, dynamic>> createCustomer(CustomerDraft draft) =>
      customers.create(draft);

  String? get validationError {
    if (cart.items.isEmpty) return 'Vui lòng thêm sản phẩm hoặc dịch vụ.';
    if (customer == null && customerQuery.trim().isNotEmpty) {
      return 'Chọn khách hàng trong danh sách hoặc để trống ô khách hàng.';
    }
    if (subtotal == null) {
      return 'Vui lòng nhập giá bán hợp lệ cho từng sản phẩm.';
    }
    return discountError ?? paidError ?? dueDateError ?? interestDateError;
  }

  /// A permissive print snapshot, separate from checkout validation.
  SalesInvoiceData previewInvoice() {
    final missingPrices = <int>{};
    final lines = <SaleLine>[];
    final vehicles = <int, Map<String, dynamic>>{};
    for (var i = 0; i < cart.items.length; i++) {
      final item = cart.items[i];
      final price = item.unitPrice;
      if (price == null ||
          price < 0 ||
          price > SaleDraft.maxMoney ~/ item.quantity)
        missingPrices.add(i);
      lines.add(
        SaleLine(
          kind: item.service
              ? 'dich_vu'
              : item.vehicle
              ? 'xe'
              : 'phu_tung',
          name: item.name,
          quantity: item.quantity,
          price: missingPrices.contains(i) ? 0 : price!,
          productId: item.service ? null : item.product['IdSanPham'] as int?,
          vehicleId: item.vehicle ? item.product['IdXe'] as int? : null,
          serviceId: item.service ? item.product['_id'] as String : null,
        ),
      );
      if (item.vehicle && item.product['IdXe'] is int)
        vehicles[item.product['IdXe']] = Map<String, dynamic>.from(
          item.product,
        );
    }
    final blank = <String>{
      if (cart.items.isEmpty || missingPrices.isNotEmpty) 'subtotal',
      if (discountText.trim().isEmpty || discountError != null) 'discount',
      if (paidText.trim().isEmpty || paidError != null) ...[
        'paid',
        'collected',
        'due',
        'change',
      ],
      if (cart.items.isEmpty ||
          missingPrices.isNotEmpty ||
          discountError != null) ...[
        'total',
        'collected',
        'due',
        'change',
      ],
    };
    return SalesInvoiceData(
      allowIncomplete: true,
      blankFields: blank,
      blankPriceLines: missingPrices,
      draft: SaleDraft(
        lines: lines,
        date: date,
        discount: discountError == null ? discount! : 0,
        paid: paidError == null ? paid! : 0,
        customerId: customer?['IdKH'] as int?,
        paymentDueDate: paymentDueDate,
        interestDate: interestDate,
        notes: notes,
      ),
      customer: customer ?? {'TenKhachHang': customerQuery.trim()},
      vehicles: vehicles,
    );
  }

  SaleDraft snapshot() => SaleDraft(
    customerId: customer?['IdKH'] as int?,
    date: date,
    paymentDueDate: hasDebt ? paymentDueDate : null,
    interestDate: hasDebt ? interestDate : null,
    discount: discount!,
    paid: paid!,
    notes: notes,
    lines: cart.items
        .map(
          (item) => SaleLine(
            kind: item.service
                ? 'dich_vu'
                : item.vehicle
                ? 'xe'
                : 'phu_tung',
            name: item.name,
            quantity: item.quantity,
            price: item.unitPrice!,
            productId: item.service ? null : item.product['IdSanPham'] as int?,
            vehicleId: item.vehicle ? item.product['IdXe'] as int? : null,
            serviceId: item.service ? item.product['_id'] as String : null,
          ),
        )
        .toList(growable: false),
  );
  Future<SaleSaveResult?> save() async {
    if (_disposed || saving) return null;
    if (salesRepository == null) {
      saveError = 'Chưa kết nối chức năng lưu đơn.';
      notifyListeners();
      return null;
    }
    _saveRetry?.cancel();
    if (_pendingDraft == null) {
      final error = validationError;
      if (error != null) {
        saveError = error;
        notifyListeners();
        return null;
      }
      final draft = snapshot();
      if (draft.error != null) {
        saveError = draft.error;
        notifyListeners();
        return null;
      }
      _pendingDraft = draft;
      _requestId = ObjectId().oid;
    }
    saving = true;
    saveError = null;
    cart.setLocked(true);
    notifyListeners();
    try {
      final result = await salesRepository!.save(_pendingDraft!, _requestId!);
      if (_disposed) return result;
      saving = false;
      awaitingConfirmation = false;
      _pendingDraft = null;
      _requestId = null;
      cart.setLocked(false);
      clear();
      lastSavedId = result.invoiceId;
      notifyListeners();
      return result;
    } catch (e) {
      if (_disposed) return null;
      saving = false;
      final failure = e is SaleSaveException
          ? e
          : const SaleSaveException(
              'Chưa xác nhận được kết quả lưu. Vui lòng thử lưu lại.',
              uncertain: true,
            );
      awaitingConfirmation = failure.uncertain;
      saveError = failure.message;
      if (!failure.uncertain) {
        _pendingDraft = null;
        _requestId = null;
        cart.setLocked(false);
      } else {
        _saveRetry = Timer(
          const Duration(seconds: 10),
          () => unawaited(save()),
        );
      }
      notifyListeners();
      return null;
    }
  }

  Future<void> recover() async {
    if (salesRepository == null || _disposed) return;
    if (saving || awaitingConfirmation) {
      _recoveryRetry = Timer(
        const Duration(seconds: 10),
        () => unawaited(recover()),
      );
      return;
    }
    try {
      final recovered = await salesRepository!.recoverPending();
      if (_disposed) return;
      if (recovered.isNotEmpty) {
        lastSavedId = recovered.last.invoiceId;
        notifyListeners();
      }
    } catch (_) {
      if (!_disposed) {
        _recoveryRetry = Timer(
          const Duration(seconds: 10),
          () => unawaited(recover()),
        );
      }
    }
  }

  void clear() {
    if (editingLocked) return;
    saveError = null;
    lastSavedId = null;
    customer = null;
    customerQuery = '';
    customerError = null;
    discountText = '';
    paidText = '';
    notes = '';
    date = DateTime.now();
    paymentDueDate = null;
    interestDate = null;
    revision++;
    cart.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _saveRetry?.cancel();
    _recoveryRetry?.cancel();
    cart.removeListener(_cartChanged);
    unawaited(customers.close());
    if (salesRepository != null) unawaited(salesRepository!.close());
    super.dispose();
  }
}
