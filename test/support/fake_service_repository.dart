import 'package:xemay_app/models/services/service_models.dart';
import 'package:xemay_app/models/repositories/service_repository.dart';

class FakeServiceRepository implements ServiceRepository {
  bool failSave = false, failLoad = false, closed = false;
  String lastSearch = '';
  final items = <ServiceItem>[];
  @override
  Future<ServicePage> fetch({String search = ''}) async {
    if (failLoad) throw StateError('offline');
    lastSearch = search;
    final term = search.toLowerCase().trim();
    final rows = items
        .where(
          (i) =>
              i.name.toLowerCase().contains(term) ||
              i.description.toLowerCase().contains(term),
        )
        .toList();
    return ServicePage(rows, rows.length);
  }

  @override
  Future<ServiceItem> create(ServiceDraft draft) async {
    if (failSave) throw StateError('offline');
    final item = ServiceItem(
      id: 'service-${items.length}',
      name: draft.name.trim(),
      description: draft.description.trim(),
      price: draft.parsedPrice!,
      cost: draft.parsedCost ?? 0,
    );
    items.add(item);
    return item;
  }

  @override
  Future<ServiceItem> update(String id, ServiceDraft draft) async =>
      ServiceItem(
        id: id,
        name: draft.name,
        description: draft.description,
        price: draft.parsedPrice!,
        cost: draft.parsedCost ?? 0,
      );
  @override
  Future<void> delete(String id) async {}
  @override
  Future<void> close() async {
    closed = true;
  }
}
