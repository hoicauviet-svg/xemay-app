import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/batches/batch_models.dart';
import '../models/goods_receipt/goods_receipt_models.dart';
import '../models/repositories/batch_repository.dart';

class BatchDetailsController extends ChangeNotifier {
  BatchDetailsController(this.repository, ReceiptBatch batch, this.type)
    : _batch = batch;
  final BatchRepository repository;
  ReceiptBatch _batch;
  ReceiptBatch get batch => _batch;
  final ReceiptProductType type;
  List<BatchProduct> _products = const [];
  List<BatchPayment> _payments = const [];
  bool _loading = true, _disposed = false;
  int _request = 0;
  String? _error;
  String _paymentAmount = '', _paymentNotes = '';
  DateTime _paymentDate = DateTime.now();
  List<BatchProduct> get products => _products;
  List<BatchPayment> get payments => _payments;
  bool get loading => _loading;
  String? get error => _error;
  DateTime get paymentDate => _paymentDate;

  Future<void> load() async {
    if (_disposed) return;
    final request = ++_request;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await repository.connect();
      if (_disposed || request != _request) return;
      final fresh = await repository.findById(_batch.id);
      if (fresh == null) throw StateError('Lô hàng không tồn tại');
      if (_disposed || request != _request) return;
      final (products, payments) = await (
        repository.products(fresh, type),
        repository.payments(fresh.id),
      ).wait;
      if (_disposed || request != _request) return;
      _batch = fresh;
      _products = products;
      _payments = payments;
      _loading = false;
    } catch (_) {
      if (_disposed || request != _request) return;
      _loading = false;
      _error = 'Không tải được chi tiết lô hàng. Vui lòng thử lại.';
    }
    notifyListeners();
  }

  void setPaymentAmount(String value) {
    _paymentAmount = value;
    if (!_disposed) notifyListeners();
  }

  num? get remainingAfterPayment {
    final due = batch.remaining;
    final amount = int.tryParse(_paymentAmount) ?? 0;
    if (due == null || !due.isFinite || amount < 0 || amount > due) return null;
    return due - amount;
  }

  void setPaymentNotes(String value) => _paymentNotes = value;
  void setPaymentDate(DateTime value) {
    _paymentDate = value;
    notifyListeners();
  }

  String? validatePayment() {
    if (_loading || _error != null) {
      return 'Vui lòng tải lại thông tin lô hàng trước khi thanh toán.';
    }
    return paymentAmountError(_paymentAmount);
  }

  String? paymentAmountError(String text) {
    final amount = int.tryParse(text);
    if (amount == null || amount <= 0) {
      return 'Số tiền thanh toán phải lớn hơn 0.';
    }
    final remaining = batch.remaining;
    if (remaining == null || !remaining.isFinite) {
      return 'Chưa xác định được số tiền còn nợ của lô.';
    }
    if (remaining <= 0) return 'Lô hàng không còn nợ cần thanh toán.';
    if (amount > remaining) {
      return 'Số tiền thanh toán không được vượt tổng nợ.';
    }
    return null;
  }

  BatchPaymentPreview previewPayment({
    List<PaymentDocument> documents = const [],
  }) {
    final error = validatePayment();
    if (error != null) throw StateError(error);
    return BatchPaymentPreview(
      documents: List.unmodifiable(documents),
      batchId: batch.id,
      amount: int.parse(_paymentAmount),
      date: _paymentDate,
      notes: _paymentNotes.trim(),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    super.dispose();
  }
}
