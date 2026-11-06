import '../services/service_models.dart';

abstract class ServiceRepository {
  Future<ServicePage> fetch({String search = ''});
  Future<ServiceItem> create(ServiceDraft draft);
  Future<ServiceItem> update(String id, ServiceDraft draft);
  Future<void> delete(String id);
  Future<void> close();
}
