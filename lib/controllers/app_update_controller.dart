import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../core/app_version.dart';
import '../models/updates/app_release.dart';
import '../services/app_update_client.dart';
import '../services/update_settings_store.dart';

const compiledUpdateFeedUrl = String.fromEnvironment(
  'UPDATE_FEED_URL',
  defaultValue: githubUpdateFeedUrl,
);

enum UpdatePhase {
  idle,
  checking,
  current,
  available,
  downloading,
  ready,
  error,
}

abstract class InstallerLauncher {
  Future<void> launch(File file);
}

class WindowsSetupLauncher implements InstallerLauncher {
  @override
  Future<void> launch(File file) async {
    if (!Platform.isWindows) {
      throw const UpdateException('Tệp cài đặt chỉ chạy trên Windows.');
    }
    await Process.start(file.path, const [
      '/SILENT',
      '/NORESTART',
    ], mode: ProcessStartMode.detached);
  }
}

class AppUpdateController extends ChangeNotifier {
  AppUpdateController({
    AppUpdateClient? client,
    UpdateSettingsStore? store,
    InstallerLauncher? launcher,
    AppRelease? current,
  }) : client = client ?? HttpAppUpdateClient(),
       store = store ?? defaultUpdateSettingsStore(),
       launcher = launcher ?? WindowsSetupLauncher(),
       current = current ?? _installed;

  final AppUpdateClient client;
  final UpdateSettingsStore store;
  final InstallerLauncher launcher;
  final AppRelease current;

  static final _installed = AppRelease.parse(
    version: AppVersion.name,
    build: AppVersion.build,
  );

  UpdatePhase phase = UpdatePhase.idle;
  String feedUrl = '';
  String? message;
  AppRelease? remote;
  double? progress;
  bool _disposed = false;

  bool get busy =>
      phase == UpdatePhase.checking || phase == UpdatePhase.downloading;

  Future<void> load() async {
    final saved = (await store.load()).trim();
    if (saved == '-') {
      feedUrl = '';
    } else if (saved.isNotEmpty) {
      feedUrl = saved;
    } else {
      feedUrl = compiledUpdateFeedUrl;
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> saveFeed(String url) async {
    if (busy || _disposed) return;
    try {
      final trimmed = url.trim();
      if (trimmed.isNotEmpty) validateHttpUrl(trimmed);
      await store.save(trimmed);
      feedUrl = trimmed;
      remote = null;
      progress = null;
      phase = UpdatePhase.idle;
      message = trimmed.isEmpty
          ? 'Đã tắt kiểm tra cập nhật.'
          : 'Đã lưu địa chỉ cập nhật.';
    } on UpdateException catch (error) {
      phase = UpdatePhase.error;
      message = error.message;
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> check() async {
    if (busy || _disposed) return;
    phase = UpdatePhase.checking;
    message = null;
    remote = null;
    progress = null;
    notifyListeners();
    try {
      if (feedUrl.trim().isEmpty) await load();
      final url = feedUrl.trim();
      if (url.isEmpty) {
        throw const UpdateException(
          'Hãy nhập địa chỉ tệp phiên bản trước khi kiểm tra.',
        );
      }
      validateHttpUrl(url);
      final body = await client.fetchFeed(Uri.parse(url));
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const UpdateException('Tệp phiên bản không đúng định dạng.');
      }
      final release = AppRelease.fromManifest(
        Map<String, dynamic>.from(decoded),
      );
      if (release.url.isEmpty || release.sha256.isEmpty) {
        throw const UpdateException(
          'Tệp phiên bản thiếu địa chỉ tải hoặc mã kiểm tra.',
        );
      }
      release.validateInstaller();
      remote = release;
      if (release.isNewerThan(current)) {
        phase = UpdatePhase.available;
        message = 'Có phiên bản ${release.label}.';
      } else {
        phase = UpdatePhase.current;
        message = 'Đang dùng phiên bản mới nhất.';
      }
    } on UpdateException catch (error) {
      phase = UpdatePhase.error;
      message = error.message;
    } on FormatException {
      phase = UpdatePhase.error;
      message = 'Tệp phiên bản không đúng định dạng.';
    } catch (_) {
      phase = UpdatePhase.error;
      message = 'Chưa kiểm tra được phiên bản.';
    } finally {
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> install() async {
    final release = remote;
    if (busy || _disposed || release == null || !release.isNewerThan(current)) {
      return;
    }
    phase = UpdatePhase.downloading;
    message = 'Đang tải bản cài...';
    progress = 0;
    notifyListeners();
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}QuanLyCuaHang-Setup-${release.label}.exe',
    );
    try {
      release.validateInstaller();
      await client.download(
        Uri.parse(release.url),
        file,
        onProgress: (received, total) {
          progress = total == null || total == 0 ? null : received / total;
          if (!_disposed) notifyListeners();
        },
      );
      final digest = sha256.convert(await file.readAsBytes()).toString();
      if (digest != release.sha256) {
        if (await file.exists()) await file.delete();
        throw const UpdateException(
          'Bản cài tải về không khớp mã kiểm tra. Chưa cài đặt.',
        );
      }
      await launcher.launch(file);
      phase = UpdatePhase.ready;
      message = 'Đã mở trình cài. Ứng dụng sẽ đóng để hoàn tất cập nhật.';
    } on UpdateException catch (error) {
      phase = UpdatePhase.error;
      message = error.message;
    } catch (_) {
      phase = UpdatePhase.error;
      message = 'Chưa tải được bản cài.';
    } finally {
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }
}
