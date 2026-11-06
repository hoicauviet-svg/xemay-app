import 'package:xemay_app/models/directory/directory_models.dart';
import 'package:xemay_app/models/inventory/inventory_models.dart';
import 'package:xemay_app/models/repositories/directory_repository.dart';

class FakeDirectoryRepository implements DirectoryRepository {
  final entries = <DirectoryEntry>[
    const DirectoryEntry(
      id: 'partner-test',
      kind: DirectoryKind.partner,
      name: 'Nơi nhập thử',
      phone: '0900000001',
      address: 'Địa chỉ thử',
    ),
    const DirectoryEntry(
      id: 'carrier-test',
      kind: DirectoryKind.carrier,
      name: 'Người giao thử',
      phone: '0900000002',
      plate: 'TEST-01',
    ),
  ];
  bool failSave = false, failBrands = false;
  @override
  Future<List<VehicleBrand>> vehicleBrands() async {
    if (failBrands) throw StateError('offline');
    return const [VehicleBrand(1, 'Honda'), VehicleBrand(2, 'Yamaha')];
  }

  int saves = 0;
  @override
  Future<List<DirectoryEntry>> fetch(DirectoryKind kind) async =>
      entries.where((e) => e.kind == kind).toList();
  @override
  Future<DirectoryEntry> create(DirectoryEntryDraft draft) async {
    if (failSave) throw StateError('test failure');
    saves++;
    final entry = DirectoryEntry(
      id: 'created-$saves',
      kind: draft.kind,
      name: draft.name.trim(),
      phone: draft.phone,
      address: draft.address,
      taxCode: draft.taxCode,
      representative: draft.representative,
      plate: draft.plate,
      notes: draft.notes,
    );
    entries.add(entry);
    return entry;
  }

  @override
  Future<DirectoryEntry> update(String id, DirectoryEntryDraft draft) async {
    if (failSave) throw StateError('offline');
    final i = entries.indexWhere((e) => e.id == id && e.kind == draft.kind);
    if (i < 0) throw StateError('missing');
    final entry = DirectoryEntry(
      id: id,
      kind: draft.kind,
      name: draft.name,
      phone: draft.phone,
      address: draft.address,
      taxCode: draft.taxCode,
      representative: draft.representative,
      plate: draft.plate,
      notes: draft.notes,
    );
    entries[i] = entry;
    return entry;
  }

  @override
  Future<void> delete(DirectoryEntry entry) async {
    if (failSave) throw StateError('offline');
    entries.removeWhere((e) => e.id == entry.id && e.kind == entry.kind);
  }

  @override
  Future<void> close() async {}
}
