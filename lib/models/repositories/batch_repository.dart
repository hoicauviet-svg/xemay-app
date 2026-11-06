import '../maintenance/record_maintenance.dart';
import '../batches/batch_models.dart';
import '../goods_receipt/goods_receipt_models.dart';

abstract class BatchRepository {
  RecordMaintenance? get maintenance => null;
  Future<void> connect();
  Future<BatchPage> fetch(
    ReceiptProductType type, {
    int page = 0,
    int pageSize = 30,
    String search = '',
  });
  Future<List<BatchProduct>> products(
    ReceiptBatch batch,
    ReceiptProductType type,
  );
  Future<ReceiptBatch?> findById(int batchId);
  Future<List<BatchPayment>> payments(int batchId);
  Future<void> pay(BatchPaymentPreview payment, {required String requestId});
  Future<void> close();
}
