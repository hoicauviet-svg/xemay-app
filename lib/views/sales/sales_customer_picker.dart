import 'package:flutter/material.dart';
import '../../controllers/sales_controller.dart';

class SalesCustomerPicker extends StatefulWidget {
  const SalesCustomerPicker({super.key, required this.controller});
  final SalesController controller;
  static double controlHeight(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge!;
    final lineHeight =
        (MediaQuery.textScalerOf(context).scale(style.fontSize ?? 16) *
                (style.height ?? 1.5))
            .ceilToDouble();
    return (lineHeight + 24).clamp(48.0, double.infinity);
  }

  static double footerHeight(BuildContext context) =>
      (MediaQuery.textScalerOf(context).scale(12) * 1.5).ceilToDouble() * 2 + 8;
  @override
  State<SalesCustomerPicker> createState() => _SalesCustomerPickerState();
}

class _SalesCustomerPickerState extends State<SalesCustomerPicker> {
  late final TextEditingController _text;
  final _focus = FocusNode();
  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.controller.customerQuery);
  }

  @override
  void didUpdateWidget(covariant SalesCustomerPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_text.text != widget.controller.customerQuery) {
      _text.value = TextEditingValue(
        text: widget.controller.customerQuery,
        selection: TextSelection.collapsed(
          offset: widget.controller.customerQuery.length,
        ),
      );
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawAutocomplete<Map<String, dynamic>>(
    textEditingController: _text,
    focusNode: _focus,
    displayStringForOption: (row) => '${row['TenKhachHang']}',
    optionsBuilder: (value) => widget.controller.searchCustomers(value.text),
    onSelected: (row) {
      widget.controller.selectCustomer(row);
      _focus.unfocus();
    },
    fieldViewBuilder: (context, text, focus, onSubmit) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListenableBuilder(
          listenable: focus,
          builder: (context, _) => Container(
            key: const ValueKey('sales-customer-surface'),
            height: SalesCustomerPicker.controlHeight(context),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: focus.hasFocus
                    ? const Color(0xFF176455)
                    : const Color(0xFFE0E7E9),
              ),
            ),
            child: TextField(
              key: const ValueKey('sales-customer-search'),
              controller: text,
              focusNode: focus,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlignVertical: TextAlignVertical.center,
              onChanged: widget.controller.customerTextChanged,
              decoration: InputDecoration(
                hintText: 'Tìm tên, điện thoại hoặc mã khách hàng',
                prefixIcon: const Icon(Icons.search, size: 20),
                prefixIconConstraints: BoxConstraints.tightFor(
                  width: 48,
                  height: SalesCustomerPicker.controlHeight(context) - 2,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.only(right: 12),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                suffixIcon: widget.controller.customerQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Bỏ chọn khách hàng',
                        onPressed: widget.controller.clearCustomer,
                        icon: const Icon(Icons.close, size: 18),
                      ),
              ),
            ),
          ),
        ),
        SizedBox(
          key: const ValueKey('sales-customer-details'),
          height: SalesCustomerPicker.footerHeight(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _detailLine(
                widget.controller.customerError ??
                    (widget.controller.customer == null
                        ? ''
                        : '#${widget.controller.customer!['IdKH']} · ${widget.controller.customer!['SoDienThoai'] ?? ''}'),
                error: widget.controller.customerError != null,
              ),
              _detailLine(
                widget.controller.customer == null
                    ? ''
                    : 'Địa chỉ: ${_address(widget.controller.customer!)}',
              ),
            ],
          ),
        ),
      ],
    ),
    optionsViewBuilder: (context, onSelected, options) => Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 310,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final row in options)
                  ListTile(
                    dense: true,
                    title: Text('${row['TenKhachHang']}'),
                    subtitle: Text(
                      '#${row['IdKH']} · ${row['SoDienThoai'] ?? ''}',
                    ),
                    onTap: () => onSelected(row),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  String _address(Map<String, dynamic> customer) {
    final value = customer['DiaChiHienThi'] ?? customer['DiaChiChiTiet'];
    return value == null || value.toString().trim().isEmpty
        ? '—'
        : value.toString();
  }

  Widget _detailLine(String value, {bool error = false}) => Tooltip(
    message: value,
    child: Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        height: 1.5,
        color: error
            ? Theme.of(context).colorScheme.error
            : const Color(0xFF6E7D83),
      ),
    ),
  );
}
