import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/app.dart';
import 'package:xemay_app/views/splash/splash_screen.dart';

void _noop() {}

void main() {
  test('Splash logo is included in the asset bundle', () async {
    final data = await rootBundle.load('assets/images/SplashLogo.png');
    expect(data.lengthInBytes, greaterThan(0));
  });

  testWidgets('Splash shows the logo then reveals the app', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SplashGate(
          duration: Duration(milliseconds: 600),
          child: Scaffold(body: Text('Trang chính')),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('splash-logo')), findsOneWidget);
    expect(find.text('Xe Máy Toàn Hợp'), findsOneWidget);
    expect(find.text('Trang chính'), findsNothing);

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Đang khởi động…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('splash-logo')), findsNothing);
    expect(find.text('Trang chính'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Splash drives the motorcycle from left to right', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: SplashScreen(onFinished: _noop, duration: Duration(seconds: 3)),
      ),
    );
    await tester.pump();
    final logoBox = tester.widget<ConstrainedBox>(
      find.byKey(const ValueKey('splash-logo-box')),
    );
    expect(logoBox.constraints.maxWidth, 260);
    final title = tester.widget<Text>(find.text('Xe Máy Toàn Hợp'));
    expect(title.style?.fontSize, 34);

    final motorcycle = find.byKey(const ValueKey('splash-motorcycle'));
    final start = tester.getTopLeft(motorcycle).dx;
    await tester.pump(const Duration(milliseconds: 800));
    final moved = tester.getTopLeft(motorcycle).dx;
    expect(moved, greaterThan(start));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('StoreApp only shows the splash when enabled', (tester) async {
    await tester.pumpWidget(const StoreApp(showSplash: true));
    expect(find.byKey(const ValueKey('splash-logo')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
