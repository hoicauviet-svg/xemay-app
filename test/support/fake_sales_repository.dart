import 'package:xemay_app/models/repositories/sales_repository.dart';
import 'package:xemay_app/models/sales/sale_models.dart';

class FakeSalesRepository implements SalesRepository {
  bool fail = false, uncertain = false;
  int calls = 0;
  SaleDraft? lastDraft;
  final requestIds = <String>[];
  @override
  Future<SaleSaveResult> save(SaleDraft draft, String requestId) async {
    calls++;
    lastDraft = draft;
    requestIds.add(requestId);
    if (fail) throw SaleSaveException('Lỗi lưu kiểm thử', uncertain: uncertain);
    return SaleSaveResult(501, requestId: requestId);
  }

  @override
  Future<List<SaleSaveResult>> recoverPending() async => [];
  @override
  Future<void> close() async {}
}
