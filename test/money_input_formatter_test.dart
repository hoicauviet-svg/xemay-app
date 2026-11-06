import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xemay_app/core/formatters/money_input_formatter.dart';

void main() {
  const formatter = MoneyInputFormatter();
  TextEditingValue edit(String text, int cursor) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: cursor),
  );
  test(
    'Money groups typing and pasted amounts without changing their numeric value',
    () {
      for (final text in ['1000000', '1.000.000', '1,000,000']) {
        final result = formatter.formatEditUpdate(
          TextEditingValue.empty,
          edit(text, text.length),
        );
        expect(result.text, '1.000.000');
        expect(result.selection.baseOffset, 9);
        expect(int.parse(ungroupMoney(result.text)), 1000000);
      }
      expect(formatter.formatEditUpdate(edit('1', 1), edit('', 0)).text, '');
      expect(groupMoney('0'), '0');
    },
  );
  test(
    'Editing in the middle and deleting grouping separators keep the cursor usable',
    () {
      final middle = formatter.formatEditUpdate(
        edit('1.234', 3),
        edit('1.2934', 4),
      );
      expect(middle.text, '12.934');
      expect(middle.selection.baseOffset, 4);
      final backspace = formatter.formatEditUpdate(
        edit('12.345', 3),
        edit('12345', 2),
      );
      expect(backspace.text, '1.345');
      expect(backspace.selection.baseOffset, 1);
      final delete = formatter.formatEditUpdate(
        edit('12.345', 2),
        edit('12345', 2),
      );
      expect(delete.text, '1.245');
      expect(delete.selection.baseOffset, 3);
    },
  );
}
