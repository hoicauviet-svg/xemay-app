import 'dart:io';

abstract class UpdateSettingsStore {
  Future<String> load();
  Future<void> save(String url);
}

class MemoryUpdateSettingsStore implements UpdateSettingsStore {
  MemoryUpdateSettingsStore([this.value = '']);
  String value;
  @override
  Future<String> load() async => value;
  @override
  Future<void> save(String url) async => value = url.trim();
}

class FileUpdateSettingsStore implements UpdateSettingsStore {
  FileUpdateSettingsStore({Directory? this.directoryOverride});
  final Directory? directoryOverride;

  Directory get directory {
    final override = directoryOverride;
    if (override != null) return override;
    if (Platform.isWindows) {
      final base = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
      return Directory('$base\\vn.cuahang.xemayApp');
    }
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    if (Platform.isMacOS) {
      return Directory('$home/Library/Application Support/vn.cuahang.xemayApp');
    }
    return Directory('$home/.local/share/vn.cuahang.xemayApp');
  }

  File get _file =>
      File('${directory.path}${Platform.pathSeparator}update_feed.txt');

  @override
  Future<String> load() async {
    if (!await _file.exists()) return '';
    return (await _file.readAsString()).trim();
  }

  @override
  Future<void> save(String url) async {
    await directory.create(recursive: true);
    await _file.writeAsString('${url.trim()}\n', flush: true);
  }
}

UpdateSettingsStore defaultUpdateSettingsStore() =>
    Platform.environment['FLUTTER_TEST'] == 'true'
    ? MemoryUpdateSettingsStore()
    : FileUpdateSettingsStore();
