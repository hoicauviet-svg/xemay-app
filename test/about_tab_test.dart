import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/services/external_link_opener.dart';
import 'package:xemay_app/views/about/about_tab.dart';

void main() {
  test('External link opener accepts only HTTPS URLs', () async {
    await expectLater(
      openExternalLink('http://hoicau.net/'),
      throwsFormatException,
    );
    await expectLater(
      openExternalLink('khong-phai-link'),
      throwsFormatException,
    );
  });

  testWidgets('About tab keeps the website, collection and support links', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AboutTab(openLink: (url) async => opened.add(url)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Xe Máy Toàn Hợp'), findsNothing);
    expect(find.text('Thiết kế bởi HoiCau.net'), findsNothing);
    expect(
      find.text(
        'Phần mềm quản lý cửa hàng xe và phụ tùng, hoạt động offline trên máy tính.',
      ),
      findsNothing,
    );
    expect(find.text('Hoạt động offline'), findsNothing);
    expect(find.text('Dữ liệu MongoDB cục bộ'), findsNothing);
    expect(find.text(websiteUrl), findsOneWidget);
    expect(find.text(collectionUrl), findsOneWidget);
    expect(find.text(supportUrl), findsOneWidget);

    await tester.tap(find.text(websiteUrl));
    await tester.pump();
    expect(opened, [websiteUrl]);

    await tester.tap(find.text(collectionUrl));
    await tester.pump();
    expect(opened, [websiteUrl, collectionUrl]);

    await tester.tap(find.text(supportUrl));
    await tester.pump();
    expect(opened, [websiteUrl, collectionUrl, supportUrl]);
    expect(tester.takeException(), isNull);
  });
}
