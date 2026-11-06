import '../maintenance/record_maintenance.dart';
import '../pawn/pawn_models.dart';

abstract class PawnRepository {
  RecordMaintenance? get maintenance => null;
  Future<PawnPage> fetch({
    String search = '',
    int page = 0,
    int? customerId,
    String status = 'all',
  });
  Future<int> create(PawnDraft draft, {required String requestId});
  Future<PawnDetails> details(int id);
  Future<void> pay(PawnPaymentDraft payment, {required String requestId});
  Future<void> close();
}
