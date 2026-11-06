import '../sales/sale_models.dart';

abstract class SalesRepository {
  Future<SaleSaveResult> save(SaleDraft draft, String requestId);
  Future<List<SaleSaveResult>> recoverPending();
  Future<void> close();
}
