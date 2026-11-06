import 'package:xemay_app/models/batches/batch_models.dart';
import 'package:xemay_app/models/goods_receipt/goods_receipt_models.dart';
import 'package:xemay_app/models/repositories/batch_repository.dart';

class FakeBatchRepository extends BatchRepository {
  bool fail = false;
  int fetchCalls = 0;
  final batch = ReceiptBatch(
    id: 42,
    date: DateTime(2026, 10, 31),
    quantity: 2,
    total: 2000000,
    paid: 500000,
    remaining: 1500000,
    deliveredBy: 'Người giao thử',
    origin: 'Nơi nhập thử',
  );
  @override
  Future<void> connect() async {
    if (fail) throw StateError('offline');
  }

  @override
  Future<BatchPage> fetch(
    ReceiptProductType type, {
    int page = 0,
    int pageSize = 30,
    String search = '',
  }) async {
    fetchCalls++;
    if (type != ReceiptProductType.newVehicle || search == 'không tìm thấy') {
      return const BatchPage([], 0);
    }
    return BatchPage([batch], 1);
  }

  @override
  Future<List<BatchProduct>> products(
    ReceiptBatch batch,
    ReceiptProductType type,
  ) async => [
    BatchProduct(
      batchId: batch.id,
      productId: 1,
      vehicleId: 7,
      name: 'Xe trong lô thử',
      quantity: 1,
      cost: 1000000,
      frameNumber: 'KHUNG-LO-42',
      engineNumber: 'MAY-LO-42',
    ),
  ];
  @override
  Future<ReceiptBatch?> findById(int batchId) async =>
      batchId == batch.id ? batch : null;
  @override
  Future<List<BatchPayment>> payments(int batchId) async => [
    BatchPayment(
      id: 9,
      batchId: batchId,
      date: DateTime(2026, 10, 31),
      amount: 500000,
      remaining: 1500000,
      notes: 'Thanh toán thử',
    ),
  ];
  @override
  Future<void> pay(
    BatchPaymentPreview payment, {
    required String requestId,
  }) async {}
  @override
  Future<void> close() async {}
}
