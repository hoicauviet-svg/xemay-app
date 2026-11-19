import 'package:flutter/material.dart';

class SyncProgressBar extends StatelessWidget {
  const SyncProgressBar({
    super.key,
    required this.active,
    required this.message,
    this.failed = false,
    this.onClose,
  });
  final bool active, failed;
  final String message;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final color = failed ? const Color(0xFFB5473D) : const Color(0xFF176455);
    return Material(
      color: Colors.white,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFE5EAED))),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (active)
                const LinearProgressIndicator(
                  minHeight: 3,
                  color: Color(0xFF176455),
                  backgroundColor: Color(0xFFE5EAED),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Icon(
                      failed
                          ? Icons.error_outline
                          : active
                          ? Icons.sync
                          : Icons.check_circle_outline,
                      size: 18,
                      color: color,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: color, fontSize: 13),
                      ),
                    ),
                    if (onClose != null)
                      TextButton(
                        key: const ValueKey('sync-dismiss'),
                        onPressed: onClose,
                        child: const Text('Bỏ qua'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
