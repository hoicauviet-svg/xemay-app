import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/core/theme/app_theme.dart';
import 'package:xemay_app/views/widgets/scrollable_data_table.dart';

void main() {
  testWidgets(
    'Header stays fixed vertically and follows the same horizontal viewport as cells',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 300,
              child: ScrollableDataTable(
                fixedHeader: true,
                columnWidths: const [200, 400, 200],
                columns: const [
                  DataColumn(label: Text('Mã')),
                  DataColumn(label: Text('Tên')),
                  DataColumn(label: Text('Giá')),
                ],
                rows: [
                  for (var i = 0; i < 50; i++)
                    DataRow(
                      cells: [
                        DataCell(Text('$i')),
                        DataCell(Text('Hàng $i')),
                        DataCell(Text('100000')),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      final heading = find.byKey(const ValueKey('fixed-table-heading'));
      final before = tester.getRect(heading);
      final rowBefore = tester.getTopLeft(find.text('Hàng 0'));
      await tester.drag(
        find.byKey(const ValueKey('fixed-table-body')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(heading).top, before.top);
      expect(tester.getRect(heading).height, before.height);
      expect(tester.getTopLeft(find.text('Hàng 0')).dy, lessThan(rowBefore.dy));
      final headerX = tester.getTopLeft(find.text('Tên')).dx;
      await tester.drag(
        find.byKey(const ValueKey('fixed-table-horizontal')),
        const Offset(-220, 0),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Tên')).dx, lessThan(headerX));
      expect(
        tester.getTopLeft(find.text('Tên')).dx,
        closeTo(tester.getTopLeft(find.text('Hàng 0')).dx, 0.1),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
