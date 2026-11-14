import 'package:flutter/material.dart';
import '../../core/formatters/inventory_formatters.dart';
import '../../models/repositories/service_repository.dart';
import '../../models/services/service_models.dart';

class ServiceNameField extends StatefulWidget {
  const ServiceNameField({
    super.key,
    required this.controller,
    required this.repository,
    required this.fieldKey,
    required this.onChanged,
    required this.onSelected,
  });
  final TextEditingController controller;
  final ServiceRepository repository;
  final String fieldKey;
  final ValueChanged<String> onChanged;
  final ValueChanged<ServiceItem> onSelected;

  @override
  State<ServiceNameField> createState() => _ServiceNameFieldState();
}

class _ServiceNameFieldState extends State<ServiceNameField> {
  final _focus = FocusNode();
  int _request = 0;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<Iterable<ServiceItem>> _search(String raw) async {
    final term = raw.trim();
    if (term.isEmpty) return const [];
    final request = ++_request;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted ||
        request != _request ||
        widget.controller.text.trim() != term) {
      return const [];
    }
    try {
      final page = await widget.repository.fetch(search: term);
      if (!mounted || request != _request) return const [];
      return page.rows.take(8);
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) => RawAutocomplete<ServiceItem>(
    textEditingController: widget.controller,
    focusNode: _focus,
    displayStringForOption: (item) => item.name,
    optionsBuilder: (value) => _search(value.text),
    onSelected: widget.onSelected,
    fieldViewBuilder: (context, text, focus, onSubmit) => TextField(
      key: ValueKey('sales-service-name-${widget.fieldKey}'),
      controller: text,
      focusNode: focus,
      onChanged: widget.onChanged,
      onSubmitted: (_) => onSubmit(),
      decoration: const InputDecoration(
        isDense: true,
        hintText: 'Tên dịch vụ',
        floatingLabelBehavior: FloatingLabelBehavior.never,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    ),
    optionsViewBuilder: (context, select, options) {
      final rows = options.toList();
      return Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 420),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final item = rows[index];
                return ListTile(
                  dense: true,
                  title: Text(item.name),
                  subtitle: Text(money(item.price)),
                  onTap: () => select(item),
                );
              },
            ),
          ),
        ),
      );
    },
  );
}
