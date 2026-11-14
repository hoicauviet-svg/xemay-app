import 'package:flutter/material.dart';

void showUnsyncedDataToast(
  BuildContext context, {
  required VoidCallback onSync,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 8),
      content: const Text(
        'Có dữ liệu chưa đồng bộ. Hãy đồng bộ với MongoDB Cloud.',
      ),
      action: SnackBarAction(label: 'Đồng bộ', onPressed: onSync),
    ),
  );
}
