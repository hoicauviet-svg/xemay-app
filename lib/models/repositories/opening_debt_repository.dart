import '../maintenance/record_maintenance.dart';
import '../finance/opening_debt.dart';

abstract class OpeningDebtRepository {
  RecordMaintenance? get maintenance => null;
  Future<OpeningDebtPage> list({String search = '', String status = 'open'});
  Future<OpeningDebtDetails> details(int id);
  Future<void> pay(OpeningDebtPayment payment, {required String requestId});
  Future<void> close();
}
