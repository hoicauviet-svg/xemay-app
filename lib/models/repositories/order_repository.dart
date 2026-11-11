import '../maintenance/record_maintenance.dart';
import '../orders/order_details.dart';

abstract class OrderRepository {
  RecordMaintenance? get maintenance => null;
  Future<OrderDetails> load(int orderId);
  Future<void> pay(
    int orderId, {
    required DateTime date,
    required int amount,
    int? interest,
    required String notes,
    required String requestId,
    DateTime? nextAppointment,
  });
  Future<void> close();
}
