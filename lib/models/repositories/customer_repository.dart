import '../customers/customer_models.dart';

abstract class CustomerRepository {
  Future<List<Map<String, dynamic>>> localities();
  Future<CustomerPage> fetch({
    String search = '',
    String phoneFilter = 'all',
    int page = 0,
  });
  Future<Map<String, dynamic>?> findById(int customerId);
  Future<CustomerOrderPage> orders(int customerId, {int page = 0});
  Future<Map<String, dynamic>> create(CustomerDraft draft);
  Future<Map<String, dynamic>> update(int id, CustomerDraft draft);
  Future<void> delete(Map<String, dynamic> customer);
  Future<List<Map<String, dynamic>>> mergeCandidates();
  Future<List<Map<String, dynamic>>> pendingMerges();
  Future<void> merge({required int targetId, required List<int> sourceIds});
  Future<void> close();
}
