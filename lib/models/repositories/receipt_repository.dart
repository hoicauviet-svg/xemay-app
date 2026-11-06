import '../goods_receipt/goods_receipt_models.dart';

abstract class ReceiptRepository {
  Future<void> save(ReceiptPreview receipt, String requestId);
  Future<void> close();
}
