import 'package:flutter/material.dart';
import '../../controllers/cart_controller.dart';

/// Dashboard-level entry to the cart shared by all product categories.
class DashboardCartButton extends StatelessWidget {
  const DashboardCartButton({
    super.key,
    required this.onPressed,
    this.compact = false,
    this.selected = false,
  });
  final VoidCallback onPressed;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: CartController.shared,
    builder: (context, _) {
      final icon = Badge(
        label: Text('${CartController.shared.count}'),
        isLabelVisible: CartController.shared.count > 0,
        child: const Icon(Icons.shopping_cart_outlined),
      );
      return compact
          ? IconButton(tooltip: 'Mở bán hàng', onPressed: onPressed, icon: icon)
          : Tooltip(
              message: 'Mở bán hàng',
              child: OutlinedButton.icon(
                onPressed: onPressed,
                icon: icon,
                label: const Text('Bán hàng'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: selected ? const Color(0xFFEAF3EF) : null,
                ),
              ),
            );
    },
  );
}
