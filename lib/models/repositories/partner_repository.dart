import '../customers/customer_models.dart';
import 'directory_repository.dart';

abstract class PartnerRepository implements DirectoryRepository {
  Future<CustomerPage> fetchPartners({String search = '', int page = 0});
  Future<Map<String, dynamic>?> findPartner(String id);
  Future<CustomerOrderPage> purchaseOrders(String partnerId, {int page = 0});
}
