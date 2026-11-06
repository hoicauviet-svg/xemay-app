import 'package:flutter/material.dart';

/// Shared page header. Use as Scaffold.appBar so Back stays at the window edge.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    super.key,
    required this.title,
    this.onBack,
    this.showBackButton = true,
    this.actions = const [],
    this.bottom,
  });

  final String title;
  final VoidCallback? onBack;
  final bool showBackButton;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) => AppBar(
    automaticallyImplyLeading: false,
    leadingWidth: 48,
    leading: showBackButton
        ? IconButton(
            tooltip: 'Quay lại',
            onPressed: onBack ?? () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back),
          )
        : null,
    title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
    centerTitle: false,
    titleSpacing: showBackButton ? 8 : 16,
    titleTextStyle: const TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: Color(0xFF1D3036),
    ),
    backgroundColor: Colors.white,
    foregroundColor: const Color(0xFF1D3036),
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    shape: const Border(bottom: BorderSide(color: Color(0xFFE5EAED))),
    actions: actions,
    bottom: bottom,
  );
}
