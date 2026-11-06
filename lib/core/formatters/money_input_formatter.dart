import 'package:flutter/services.dart';

/// Keep persisted amounts as digits while displaying Vietnamese grouping.
String ungroupMoney(String value) => value.replaceAll(RegExp(r'[.,\s]'), '');
String groupMoney(String value) => ungroupMoney(value).replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (match) => '${match[1]}.',
);

class MoneyInputFormatter extends TextInputFormatter {
  const MoneyInputFormatter();
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    var digitCursor = -1;
    // Deleting a grouping dot should remove a digit instead of restoring the dot.
    if (oldValue.selection.isCollapsed &&
        newValue.selection.isCollapsed &&
        oldValue.text.length == newValue.text.length + 1 &&
        oldValue.text.replaceAll(RegExp(r'\D'), '') == digits) {
      final cursor = oldValue.selection.extentOffset;
      final backwards = newValue.selection.extentOffset < cursor;
      final before = oldValue.text
          .substring(0, cursor.clamp(0, oldValue.text.length))
          .replaceAll(RegExp(r'\D'), '')
          .length;
      final remove = backwards ? before - 1 : before;
      if (remove >= 0 && remove < digits.length) {
        digits = digits.substring(0, remove) + digits.substring(remove + 1);
        digitCursor = remove;
      }
    }
    final grouped = groupMoney(digits);
    int offset(int position) {
      if (position < 0) return grouped.length;
      final count = digitCursor >= 0
          ? digitCursor
          : newValue.text
                .substring(0, position.clamp(0, newValue.text.length))
                .replaceAll(RegExp(r'\D'), '')
                .length;
      if (count == 0) return 0;
      int seen = 0;
      for (int i = 0; i < grouped.length; i++) {
        if (grouped[i] != '.') seen++;
        if (seen == count) return i + 1;
      }
      return grouped.length;
    }

    return TextEditingValue(
      text: grouped,
      selection: TextSelection(
        baseOffset: offset(newValue.selection.baseOffset),
        extentOffset: offset(newValue.selection.extentOffset),
      ),
    );
  }
}
