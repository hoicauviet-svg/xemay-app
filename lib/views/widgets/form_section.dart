import 'package:flutter/material.dart';

/// Shared form section used by entry screens and editor popups.
class FormSection extends StatelessWidget {
  const FormSection({super.key, required this.title, required this.children});
  final String? title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE5EAED)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Text(
            title!,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1D3036),
            ),
          ),
          const SizedBox(height: 20),
        ],
        ...children,
      ],
    ),
  );
}

class ResponsiveFormFields extends StatelessWidget {
  const ResponsiveFormFields({
    super.key,
    required this.fields,
    this.compact = false,
    this.columnSpans = const {},
  });
  final List<Widget> fields;
  final bool compact;
  final Map<int, int> columnSpans;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final columns = compact
          ? ((bounds.maxWidth + 16) / 196).floor().clamp(1, 4)
          : bounds.maxWidth >= 640
          ? 2
          : 1;
      final width = (bounds.maxWidth - (columns - 1) * 16) / columns;
      return Wrap(
        spacing: 16,
        runSpacing: 20,
        children: [
          for (int i = 0; i < fields.length; i++)
            SizedBox(
              width:
                  width * (columnSpans[i] ?? 1).clamp(1, columns) +
                  16 * ((columnSpans[i] ?? 1).clamp(1, columns) - 1),
              child: fields[i],
            ),
        ],
      );
    },
  );
}

/// Fixed-height group with a caption sitting on its outline.
class OutlinedFormSection extends StatelessWidget {
  const OutlinedFormSection({
    super.key,
    required this.title,
    required this.height,
    required this.child,
  });
  final String title;
  final double height;
  final Widget child;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE0E7E9)),
          ),
          child: child,
        ),
        Positioned(
          top: -10,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            color: Colors.white,
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF56656D),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
