import 'package:flutter/material.dart';

void showUnsyncedDataToast(
  BuildContext context, {
  required VoidCallback onSync,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 8),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Có dữ liệu chưa đồng bộ. Hãy đồng bộ với MongoDB Cloud.',
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () =>
                    ScaffoldMessenger.of(context).hideCurrentSnackBar(),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: const Text('Bỏ qua'),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  onSync();
                },
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: const Text('Đồng bộ'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
