import 'package:flutter/material.dart';
import '../../core/formatters/inventory_formatters.dart';
import '../../models/inventory/inventory_models.dart';
import '../../models/repositories/inventory_repository.dart';

class ProductSuggestion {
  const ProductSuggestion.vehicle(this.row) : vehicle = true;
  const ProductSuggestion.part(this.row) : vehicle = false;
  final Map<String, dynamic> row;
  final bool vehicle;

  String get name => cleanName(row[vehicle ? 'TenXe' : 'TenSanPham']);
  String get cartKey =>
      '${vehicle ? 'xe' : 'pt'}-${row[vehicle ? 'IdXe' : 'IdSanPham']}';

  String get detail {
    if (vehicle) {
      return 'Xe · #${row['IdXe']} · Số khung: ${_text(row['SoKhung'])} · Số máy: ${_text(row['SoMay'])}';
    }
    return 'Phụ tùng · Mã ${_text(row['MaSanPham'] ?? row['IdSanPham'])}';
  }

  static String _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? '—' : text;
  }
}

class ProductNameField extends StatefulWidget {
  const ProductNameField({
    super.key,
    required this.controller,
    required this.repository,
    required this.fieldKey,
    required this.onChanged,
    required this.onSelected,
  });
  final TextEditingController controller;
  final InventoryRepository repository;
  final String fieldKey;
  final ValueChanged<String> onChanged;
  final ValueChanged<ProductSuggestion> onSelected;

  @override
  State<ProductNameField> createState() => _ProductNameFieldState();
}

class _ProductNameFieldState extends State<ProductNameField> {
  final _focus = FocusNode();
  int _request = 0;
  String? _error;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<Iterable<ProductSuggestion>> _search(String raw) async {
    final term = raw.trim();
    if (term.isEmpty) {
      _setError(null);
      return const [];
    }
    final request = ++_request;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted ||
        request != _request ||
        widget.controller.text.trim() != term) {
      return const [];
    }
    try {
      await widget.repository.connect();
      final found = await Future.wait([
        for (final condition in ['moi', 'cu'])
          widget.repository.fetch(
            InventorySection.vehicles,
            search: term,
            condition: condition,
            availability: 'available',
            pageSize: 30,
          ),
        widget.repository.fetch(
          InventorySection.parts,
          search: term,
          availability: 'available',
          pageSize: 30,
        ),
      ]);
      if (!mounted || request != _request) return const [];
      _setError(null);
      final vehicles = <String, ProductSuggestion>{};
      for (final page in found.take(2)) {
        for (final row in page.rows) {
          final item = ProductSuggestion.vehicle(row);
          vehicles.putIfAbsent(item.cartKey, () => item);
        }
      }
      return [
        ...vehicles.values,
        for (final row in found[2].rows) ProductSuggestion.part(row),
      ];
    } catch (_) {
      if (!mounted || request != _request) return const [];
      _setError('Chưa tìm được sản phẩm. Kiểm tra dữ liệu trên máy.');
      return const [];
    }
  }

  void _setError(String? value) {
    if (!mounted || _error == value) return;
    setState(() => _error = value);
  }

  @override
  Widget build(BuildContext context) => RawAutocomplete<ProductSuggestion>(
    textEditingController: widget.controller,
    focusNode: _focus,
    displayStringForOption: (item) => item.name,
    optionsBuilder: (value) => _search(value.text),
    onSelected: widget.onSelected,
    fieldViewBuilder: (context, text, focus, onSubmit) => TextField(
      key: ValueKey('sales-product-name-${widget.fieldKey}'),
      controller: text,
      focusNode: focus,
      onChanged: widget.onChanged,
      onSubmitted: (_) => onSubmit(),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Tên, mã, số khung hoặc số máy',
        floatingLabelBehavior: FloatingLabelBehavior.never,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        errorText: _error,
        errorMaxLines: 2,
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
            constraints: const BoxConstraints(maxHeight: 280, maxWidth: 560),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final item = rows[index];
                return ListTile(
                  dense: true,
                  title: Text(item.name),
                  subtitle: Text(item.detail),
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
