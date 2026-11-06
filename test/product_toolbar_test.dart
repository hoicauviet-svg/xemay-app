import 'support/fake_inventory_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/core/theme/app_theme.dart';
import 'package:xemay_app/models/dashboard/dashboard_module.dart';
import 'package:xemay_app/views/products/product_tab.dart';

void main() {
  for (final density in [VisualDensity.standard, VisualDensity.compact]) {
    for (final module in [
      DashboardModule.newVehicles,
      DashboardModule.usedVehicles,
      DashboardModule.parts,
    ]) {
      testWidgets(
        'Visible search border and button match for ${module.name} at $density',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light.copyWith(
                visualDensity: density,
                platform: TargetPlatform.macOS,
              ),
              home: Scaffold(
                body: ProductTab(
                  module: module,
                  repository: FakeInventoryRepository(),
                ),
              ),
            ),
          );
          final search = tester.getRect(
            find.byKey(ValueKey('product-search-${module.name}')),
          );
          // Measure the painted Material inside the button, not its outer hit target.
          final surface = find.descendant(
            of: find.byKey(ValueKey('product-add-${module.name}')),
            matching: find.byType(Material),
          );
          final button = tester.getRect(surface);
          expect(search.height, 48);
          expect(button.height, search.height);
          expect(button.top, search.top);
          expect(button.bottom, search.bottom);
          await tester.tap(find.byType(TextField));
          await tester.pumpAndSettle();
          expect(tester.getRect(surface).height, search.height);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
