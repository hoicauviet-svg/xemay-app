import 'package:flutter/material.dart';
import 'app.dart';
import 'services/native_database_settings_repository.dart';
import 'core/config/database_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final settings = await NativeDatabaseSettingsRepository().load();
    await NativeDatabaseSettingsRepository.activate(settings);
  } catch (_) {
    DatabaseConfig.startupReadFailed = true;
  }
  runApp(const StoreApp());
}
