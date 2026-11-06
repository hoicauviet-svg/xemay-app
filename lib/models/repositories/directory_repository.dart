import '../directory/directory_models.dart';
import '../inventory/inventory_models.dart';

abstract class DirectoryRepository {
  Future<List<DirectoryEntry>> fetch(DirectoryKind kind);
  Future<DirectoryEntry> create(DirectoryEntryDraft draft);
  Future<DirectoryEntry> update(String id, DirectoryEntryDraft draft);
  Future<void> delete(DirectoryEntry entry);
  Future<List<VehicleBrand>> vehicleBrands();
  Future<void> close();
}
