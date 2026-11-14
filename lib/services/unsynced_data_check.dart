import '../models/repositories/database_settings_repository.dart';
import '../models/settings/database_settings.dart';

/// Compares the saved local and cloud databases without showing progress.
class UnsyncedDataCheck {
  const UnsyncedDataCheck(this.repository);
  final DatabaseSettingsRepository repository;

  Future<CloudComparison?> pendingComparison() async {
    final settings = await repository.load();
    final local = settings.mongoUri.trim();
    final cloud = settings.cloudUri.trim();
    if (local.isEmpty || cloud.isEmpty || local == cloud) return null;
    final comparison = await repository.compareCloud(
      sourceUri: local,
      targetUri: cloud,
    );
    return comparison.needsSync ? comparison : null;
  }
}
