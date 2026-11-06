import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/controllers/directory_controller.dart';
import 'package:xemay_app/core/theme/app_theme.dart';
import 'package:xemay_app/models/directory/directory_models.dart';
import 'package:xemay_app/views/directory/directory_picker.dart';
import 'support/fake_directory_repository.dart';

void main() {
  for (final kind in DirectoryKind.values) {
    for (final density in [VisualDensity.standard, VisualDensity.compact]) {
      for (final scale in [1.0, 1.4]) {
        testWidgets(
          'Autocomplete border matches add surface: $kind, $density, text $scale',
          (tester) async {
            final directory = DirectoryController(FakeDirectoryRepository());
            addTearDown(directory.dispose);
            final form = GlobalKey<FormState>();
            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.light.copyWith(
                  platform: TargetPlatform.macOS,
                  visualDensity: density,
                ),
                home: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                    body: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: form,
                        child: DirectoryPicker(
                          directory: directory,
                          kind: kind,
                          fieldKey: 'geometry-picker',
                          onSelected: (_) {},
                          onTextChanged: (_) {},
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            void expectMatchingVisibleSurfaces() {
              final border = InputDecorator.containerOf(
                tester.element(find.byType(EditableText)),
              )!;
              final inputRect = border.localToGlobal(Offset.zero) & border.size;
              final buttonRect = tester.getRect(
                find.descendant(
                  of: find.byKey(ValueKey('directory-add-${kind.name}')),
                  matching: find.byType(Material),
                ),
              );
              expect(buttonRect.height, closeTo(inputRect.height, 0.1));
              expect(buttonRect.top, closeTo(inputRect.top, 0.1));
              expect(buttonRect.bottom, closeTo(inputRect.bottom, 0.1));
            }

            expectMatchingVisibleSurfaces();
            await tester.tap(find.byKey(const ValueKey('geometry-picker')));
            await tester.pumpAndSettle();
            expectMatchingVisibleSurfaces();
            form.currentState!.validate();
            await tester.pumpAndSettle();
            expectMatchingVisibleSurfaces();
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
