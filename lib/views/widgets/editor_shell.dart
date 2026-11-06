import 'package:flutter/material.dart';
import 'form_popup.dart';

/// Creation can use a popup; existing records edit inside their information tab.
class EditorShell extends StatelessWidget {
  const EditorShell({
    super.key,
    required this.title,
    required this.child,
    this.canClose = true,
    this.embedded = false,
  });
  final String title;
  final Widget child;
  final bool canClose, embedded;
  @override
  Widget build(BuildContext context) => embedded
      ? child
      : FormPopup(title: title, child: child, canClose: canClose);
}
