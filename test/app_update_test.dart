import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/controllers/app_update_controller.dart';
import 'package:xemay_app/core/app_version.dart';
import 'package:xemay_app/models/updates/app_release.dart';
import 'package:xemay_app/services/app_update_client.dart';
import 'package:xemay_app/services/update_settings_store.dart';
import 'package:xemay_app/views/settings/app_update_panel.dart';
import 'package:xemay_app/views/settings/settings_tab.dart';
import 'support/fake_database_settings_repository.dart';

const _sha = 'abababababababababababababababababababababababababababababababab';

AppRelease _release({
  String version = '1.0.1',
  int build = 2,
  String url = 'https://updates.example/setup.exe',
  String sha256 = _sha,
}) => AppRelease.parse(
  version: version,
  build: build,
  notes: 'Sửa lỗi',
  url: url,
  sha256: sha256,
);

class _Client implements AppUpdateClient {
  _Client(this.body, {this.bytes = const [1, 2, 3, 4]});
  final String body;
  final List<int> bytes;
  int fetches = 0;

  @override
  Future<String> fetchFeed(Uri url) async {
    fetches += 1;
    if (body == 'down') {
      throw const UpdateException('Chưa kết nối được máy chủ cập nhật.');
    }
    return body;
  }

  @override
  Future<void> download(
    Uri url,
    File destination, {
    void Function(int received, int? total)? onProgress,
  }) async {
    onProgress?.call(bytes.length, bytes.length);
    await destination.writeAsBytes(bytes, flush: true);
  }
}

class _RealHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final created = super.createHttpClient(context);
    created.connectionTimeout = const Duration(seconds: 20);
    return created;
  }
}

class _Launcher implements InstallerLauncher {
  File? launched;
  @override
  Future<void> launch(File file) async => launched = file;
}

AppUpdateController _controller({
  required _Client client,
  UpdateSettingsStore? store,
  InstallerLauncher? launcher,
}) => AppUpdateController(
  client: client,
  store:
      store ?? MemoryUpdateSettingsStore('https://updates.example/latest.json'),
  launcher: launcher ?? _Launcher(),
);

void main() {
  test('empty settings use the GitHub release feed', () async {
    final controller = _controller(
      client: _Client('{}'),
      store: MemoryUpdateSettingsStore(),
    );
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.feedUrl, githubUpdateFeedUrl);
    expect(
      githubUpdateFeedUrl,
      'https://github.com/hoicauviet-svg/xemay-app/releases/latest/download/latest.json',
    );
  });

  test('app version matches pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull);
    expect(AppVersion.name, match!.group(1));
    expect(AppVersion.build, int.parse(match.group(2)!));
  });

  test('release ordering uses version then build number', () {
    // Fixed fixtures test ordering independently of each release's build number.
    final current = AppRelease.parse(version: '1.0.0', build: 1);
    expect(_release().isNewerThan(current), isTrue);
    expect(
      AppRelease.parse(version: '1.0.0', build: 1).isNewerThan(current),
      isFalse,
    );
    expect(
      AppRelease.parse(version: '1.0.0', build: 2).isNewerThan(current),
      isTrue,
    );
    expect(
      () => AppRelease.parse(version: '1.0', build: 1),
      throwsA(isA<UpdateException>()),
    );
    expect(
      () => validateHttpUrl('file:///tmp/setup.exe'),
      throwsA(isA<UpdateException>()),
    );
  });

  test('check reports a newer manifest and ignores an older one', () async {
    final newer = _controller(
      client: _Client(
        jsonEncode({
          'version': '1.2.0',
          'build': 3,
          'notes': 'Thêm báo cáo',
          'url': 'https://updates.example/setup.exe',
          'sha256': _sha,
        }),
      ),
    );
    addTearDown(newer.dispose);
    await newer.check();
    expect(newer.phase, UpdatePhase.available);
    expect(newer.remote?.label, '1.2.0+3');

    final same = _controller(
      client: _Client(
        jsonEncode({
          'version': AppVersion.name,
          'build': AppVersion.build,
          'url': 'https://updates.example/setup.exe',
          'sha256': _sha,
        }),
      ),
    );
    addTearDown(same.dispose);
    await same.check();
    expect(same.phase, UpdatePhase.current);
  });

  test('check keeps a readable error when the feed is unreachable', () async {
    final controller = _controller(client: _Client('down'));
    addTearDown(controller.dispose);
    await controller.check();
    expect(controller.phase, UpdatePhase.error);
    expect(controller.message, contains('máy chủ'));
  });

  test(
    'install launches only when the downloaded file matches sha256',
    () async {
      final bytes = utf8.encode('setup-bytes');
      final digest = sha256.convert(bytes).toString();
      final launcher = _Launcher();
      final controller = _controller(
        client: _Client(
          jsonEncode({
            'version': '2.0.0',
            'build': 1,
            'url': 'https://updates.example/setup.exe',
            'sha256': digest,
          }),
          bytes: bytes,
        ),
        launcher: launcher,
      );
      addTearDown(controller.dispose);
      await controller.check();
      await controller.install();
      expect(controller.phase, UpdatePhase.ready);
      expect(launcher.launched, isNotNull);
      expect(await launcher.launched!.readAsBytes(), bytes);

      final rejected = _controller(
        client: _Client(
          jsonEncode({
            'version': '2.0.0',
            'build': 1,
            'url': 'https://updates.example/setup.exe',
            'sha256': _sha,
          }),
          bytes: bytes,
        ),
      );
      addTearDown(rejected.dispose);
      await rejected.check();
      await rejected.install();
      expect(rejected.phase, UpdatePhase.error);
      expect(rejected.message, contains('mã kiểm tra'));
    },
  );

  test('feed address is stored and an empty value turns checks off', () async {
    final store = MemoryUpdateSettingsStore();
    final controller = _controller(client: _Client('{}'), store: store);
    addTearDown(controller.dispose);
    await controller.saveFeed('https://shop.local/latest.json');
    expect(store.value, 'https://shop.local/latest.json');
    await controller.saveFeed('   ');
    expect(store.value, isEmpty);
    expect(controller.message, contains('tắt'));
    await controller.saveFeed('notaurl');
    expect(controller.phase, UpdatePhase.error);
  });

  test('http client reads a local manifest and installer', () async {
    final payload = utf8.encode('installer-body');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      if (request.uri.path == '/latest.json') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'version': '1.0.1',
            'build': 2,
            'url': 'http://127.0.0.1/setup.exe',
            'sha256': _sha,
          }),
        );
      } else {
        request.response.add(payload);
      }
      await request.response.close();
    });
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}xemay-update-test-${server.port}.exe',
    );
    addTearDown(() async {
      if (await file.exists()) await file.delete();
    });
    await HttpOverrides.runZoned(() async {
      final client = HttpAppUpdateClient();
      final body = await client.fetchFeed(
        Uri.parse('http://127.0.0.1:${server.port}/latest.json'),
      );
      expect(jsonDecode(body)['version'], '1.0.1');
      await client.download(
        Uri.parse('http://127.0.0.1:${server.port}/setup.exe'),
        file,
      );
      expect(await file.readAsBytes(), payload);
    }, createHttpClient: _RealHttp().createHttpClient);
  });

  testWidgets('settings exposes the version tab and a newer release', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _controller(
      client: _Client(
        jsonEncode({
          'version': '9.0.0',
          'build': 4,
          'notes': 'Bản thử',
          'url': 'https://updates.example/setup.exe',
          'sha256': _sha,
        }),
      ),
    );
    addTearDown(controller.dispose);
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsTab(repository: FakeDatabaseSettingsRepository()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Tab, 'Phiên bản'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AppUpdatePanel(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining(AppVersion.label), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-check-update')));
    await tester.pumpAndSettle();
    expect(find.textContaining('9.0.0+4'), findsWidgets);
    if (Platform.isWindows) {
      expect(
        find.byKey(const ValueKey('settings-install-update')),
        findsOneWidget,
      );
    } else {
      expect(find.textContaining('chỉ chạy trên Windows'), findsOneWidget);
    }
  });
}
