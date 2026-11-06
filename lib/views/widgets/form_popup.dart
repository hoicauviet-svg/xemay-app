import 'package:flutter/material.dart';

/// Shared popup shell for scrollable forms with their own bottom actions.
class FormPopup extends StatelessWidget {
  const FormPopup({
    super.key,
    required this.title,
    required this.child,
    this.canClose = true,
  });
  final String title;
  final Widget child;
  final bool canClose;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.white,
    insetPadding: const EdgeInsets.all(20),
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: SizedBox(
      width: 960,
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Đóng',
                  onPressed: canClose ? () => Navigator.pop(context) : null,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: child),
        ],
      ),
    ),
  );
}
