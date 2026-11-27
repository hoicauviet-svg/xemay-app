import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../controllers/cart_controller.dart';
import '../../models/repositories/inventory_repository.dart';
import '../../models/repositories/service_repository.dart';
import '../../models/services/service_models.dart';
import '../../services/mongo_inventory_repository.dart';
import '../../services/mongo_service_repository.dart';
import '../../controllers/sales_controller.dart';
import '../../models/printing/sales_invoice_data.dart';
import '../../core/formatters/inventory_formatters.dart';
import '../../core/formatters/money_input_formatter.dart';
import 'product_name_field.dart';
import 'service_name_field.dart';
import 'sales_order_preview_popup.dart';
import '../widgets/form_section.dart';
import '../customers/customer_editor_popup.dart';
import 'sales_customer_picker.dart';

class SalesTab extends StatefulWidget {
  const SalesTab({
    super.key,
    required this.controller,
    this.inventoryRepositoryFactory,
    this.serviceRepositoryFactory,
  });
  final SalesController controller;
  final InventoryRepository Function()? inventoryRepositoryFactory;
  final ServiceRepository Function()? serviceRepositoryFactory;
  @override
  State<SalesTab> createState() => _SalesTabState();
}

class _SalesTabState extends State<SalesTab> {
  final _form = GlobalKey<FormState>();
  final _paymentFieldsScroll = ScrollController();
  final _productRows = <_ProductRow>[_ProductRow.blank()];
  final _serviceRows = <_ServiceRow>[_ServiceRow.blank()];
  InventoryRepository? _inventory;
  ServiceRepository? _services;
  InventoryRepository get _inventoryRepo => _inventory ??=
      widget.inventoryRepositoryFactory?.call() ?? MongoInventoryRepository();
  ServiceRepository get _serviceRepo => _services ??=
      widget.serviceRepositoryFactory?.call() ?? MongoServiceRepository();

  @override
  void initState() {
    super.initState();
    final products = [
      for (final item in sale.cart.items.where((item) => !item.service))
        _ProductRow.linked(item),
    ];
    if (products.isNotEmpty) _productRows.addAll(products);
    final linked = [
      for (final item in sale.cart.items.where((item) => item.service))
        _ServiceRow.linked(item),
    ];
    if (linked.isNotEmpty) _serviceRows.addAll(linked);
  }

  @override
  void dispose() {
    _paymentFieldsScroll.dispose();
    for (final row in _productRows) {
      row.dispose();
    }
    for (final row in _serviceRows) {
      row.dispose();
    }
    final inventory = _inventory;
    final services = _services;
    _inventory = null;
    _services = null;
    inventory?.close();
    services?.close();
    super.dispose();
  }

  SalesController get sale => widget.controller;
  static const _green = Color(0xFF176455);
  static const _fieldHeight = 40.0;
  String _amount(int? value) => value == null ? '—' : money(value);
  Widget _moneyField({
    required Key key,
    required String label,
    required String hint,
    required String digits,
    required ValueChanged<String> onChanged,
    required String? Function(String?) validator,
    bool enabled = true,
    TextStyle? style,
  }) => TextFormField(
    key: key,
    enabled: enabled,
    style: style,
    initialValue: groupMoney(digits),
    keyboardType: TextInputType.number,
    inputFormatters: const [MoneyInputFormatter()],
    decoration: InputDecoration(
      labelText: label.isEmpty ? null : label,
      floatingLabelBehavior: label.isEmpty ? FloatingLabelBehavior.never : null,
      isDense: label.isEmpty,
      contentPadding: label.isEmpty
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 14)
          : null,
      suffixText: 'đ',
      hintText: hint,
    ),
    onChanged: (value) => onChanged(ungroupMoney(value)),
    validator: validator,
  );
  Future<void> _chooseDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: sale.date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (value != null && mounted) sale.setDate(value);
  }

  Future<void> _chooseDebtDate({required bool interest}) async {
    if (!sale.hasDebt || sale.editingLocked) return;
    final start = DateUtils.dateOnly(sale.date);
    final selected = interest ? sale.interestDate : sale.paymentDueDate;
    final initial =
        selected == null || DateUtils.dateOnly(selected).isBefore(start)
        ? start
        : DateUtils.dateOnly(selected);
    final value = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: start,
      lastDate: DateTime(2100),
    );
    if (value != null && mounted) {
      if (interest) {
        sale.setInterestDate(value);
      } else {
        sale.setPaymentDueDate(value);
      }
    }
  }

  Widget _debtDateField({required bool interest}) {
    final value = interest ? sale.interestDate : sale.paymentDueDate;
    final label = interest ? 'Ngày tính lãi' : 'Ngày hẹn thanh toán';
    return TextFormField(
      key: ValueKey(
        'sales-${interest ? 'interest' : 'due'}-date-${value?.toIso8601String() ?? 'empty'}',
      ),
      initialValue: value == null ? '' : DateFormat('dd/MM/yyyy').format(value),
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      readOnly: true,
      enabled: !sale.editingLocked && sale.hasDebt,
      decoration: InputDecoration(
        labelText: '$label *',
        hintText: 'Chọn ngày',
        suffixIcon: const Icon(Icons.calendar_today_outlined, size: 20),
      ),
      onTap: () => _chooseDebtDate(interest: interest),
      validator: (_) => interest ? sale.interestDateError : sale.dueDateError,
    );
  }

  Future<void> _addCustomer() async {
    FocusScope.of(context).unfocus();
    final customer = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CustomerEditorPopup(onCreate: sale.createCustomer),
    );
    if (customer != null && mounted) sale.selectCustomer(customer);
  }

  Future<void> _save() async {
    final productError = _unselectedProductError();
    if (productError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(productError)));
      return;
    }
    final serviceError = await _commitNewServices();
    if (!mounted) return;
    _syncDraftServiceSubtotal();
    if (serviceError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(serviceError)));
      return;
    }
    if (!sale.awaitingConfirmation && !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    SalesInvoiceData? printable;
    if (sale.validationError == null || sale.awaitingConfirmation) {
      try {
        printable = sale.printableInvoice();
      } catch (_) {
        printable = null;
      }
    }
    final result = await sale.save();
    if (result == null || !mounted) return;
    setState(_resetEntryRows);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã lưu đơn hàng #${result.invoiceId}')),
    );
    if (printable == null) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          SalesOrderPreviewPopup(data: printable!.asSaved(result.invoiceId)),
    );
  }

  void _preview() {
    final data = sale.previewInvoice();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SalesOrderPreviewPopup(data: data),
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 1,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5EAED)),
            ),
            child: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              dividerColor: Colors.transparent,
              labelColor: _green,
              indicatorColor: _green,
              tabs: [Tab(text: 'Bán hàng')],
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListenableBuilder(
              listenable: sale,
              builder: (context, _) => Form(
                key: _form,
                child: LayoutBuilder(
                  builder: (context, bounds) {
                    if (bounds.maxWidth >= 850 && bounds.maxHeight >= 650) {
                      return Column(
                        children: [
                          AbsorbPointer(
                            absorbing: sale.editingLocked,
                            child: _topInformation(),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: AbsorbPointer(
                              absorbing: sale.editingLocked,
                              child: _productList(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _payment(),
                        ],
                      );
                    }
                    return SingleChildScrollView(
                      child: Column(
                        children: [
                          AbsorbPointer(
                            absorbing: sale.editingLocked,
                            child: _topInformation(),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: bounds.maxHeight < 500
                                ? 360
                                : bounds.maxHeight * .72,
                            child: AbsorbPointer(
                              absorbing: sale.editingLocked,
                              child: _productList(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _payment(),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _topInformation() => LayoutBuilder(
    builder: (context, bounds) {
      final customerHeight = SalesCustomerPicker.controlHeight(context);
      final sectionHeight =
          customerHeight + SalesCustomerPicker.footerHeight(context) + 34;
      final wide = bounds.maxWidth >= 850;
      final orderWidth = wide
          ? (bounds.maxWidth - 12) * 3 / 5
          : bounds.maxWidth;
      final orderInRow = orderWidth - 32 >= 380;
      final customer = OutlinedFormSection(
        key: const ValueKey('sales-customer-section'),
        title: 'Khách hàng',
        height: sectionHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: SalesCustomerPicker(controller: sale)),
            const SizedBox(width: 10),
            SizedBox(
              width: customerHeight,
              height: customerHeight,
              child: IconButton.filled(
                key: const ValueKey('sales-customer-add'),
                tooltip: 'Thêm khách hàng mới',
                onPressed: _addCustomer,
                icon: const Icon(Icons.add),
                style: IconButton.styleFrom(
                  fixedSize: Size.square(customerHeight),
                  minimumSize: Size.square(customerHeight),
                  maximumSize: Size.square(customerHeight),
                  visualDensity: VisualDensity.standard,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
      final date = InkWell(
        onTap: _chooseDate,
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Ngày bán',
            suffixIcon: Icon(Icons.calendar_today_outlined, size: 20),
          ),
          child: Text(DateFormat('dd/MM/yyyy').format(sale.date)),
        ),
      );
      final notes = TextFormField(
        key: ValueKey('sales-notes-${sale.revision}'),
        initialValue: sale.notes,
        decoration: const InputDecoration(labelText: 'Ghi chú đơn hàng'),
        onChanged: (v) => sale.notes = v,
      );
      final order = OutlinedFormSection(
        key: const ValueKey('sales-order-section'),
        title: 'Thông tin đơn hàng',
        height: orderInRow
            ? sectionHeight
            : sectionHeight + customerHeight + 24,
        child: orderInRow
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 165, child: date),
                  const SizedBox(width: 12),
                  Expanded(child: notes),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [date, const SizedBox(height: 16), notes],
              ),
      );
      return bounds.maxWidth >= 850
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: customer),
                const SizedBox(width: 12),
                Expanded(flex: 3, child: order),
              ],
            )
          : Column(children: [customer, const SizedBox(height: 12), order]);
    },
  );

  Widget _productList() => Container(
    key: const ValueKey('sales-product-list'),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE5EAED)),
    ),
    clipBehavior: Clip.antiAlias,
    padding: const EdgeInsets.all(12),
    child: _lines(),
  );

  Widget _lines({bool shrinkWrap = false}) {
    return ListView(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: EdgeInsets.zero,
      children: [
        _orderTable(
          service: false,
          rows: [for (final row in _productRows) _productCells(row)],
          rowKey: (index) {
            final row = _productRows[index];
            final linked = _linkedProduct(row);
            return ValueKey('sales-line-${linked?.key ?? row.lineKey}');
          },
          headerAction: _addLineButton(
            tooltip: 'Thêm dòng sản phẩm',
            onPressed: sale.editingLocked
                ? null
                : () => setState(() => _productRows.add(_ProductRow.newLine())),
          ),
        ),
        _orderTable(
          service: true,
          rows: [for (final row in _serviceRows) _serviceCells(row)],
          rowKey: (index) =>
              ValueKey('sales-line-${_serviceRows[index].lineKey}'),
          headerAction: _addLineButton(
            tooltip: 'Thêm dòng dịch vụ',
            onPressed: sale.editingLocked
                ? null
                : () => setState(() => _serviceRows.add(_ServiceRow.newLine())),
          ),
        ),
      ],
    );
  }

  Widget _orderTable({
    required bool service,
    required List<List<Widget>> rows,
    required Key? Function(int index) rowKey,
    Widget? headerAction,
  }) {
    final columns = service
        ? const [
            _SaleColumn('Dịch vụ', flex: 24),
            _SaleColumn('Số lượng', flex: 11),
            _SaleColumn('Đơn giá', flex: 18),
            _SaleColumn('Thành tiền', flex: 12),
            _SaleColumn('', flex: 6),
          ]
        : const [
            _SaleColumn('Sản phẩm', flex: 18),
            _SaleColumn('Số khung', flex: 14),
            _SaleColumn('Số máy', flex: 14),
            _SaleColumn('Biển số', flex: 10),
            _SaleColumn('Màu', flex: 8),
            _SaleColumn('Số lượng', flex: 11),
            _SaleColumn('Đơn giá', flex: 18),
            _SaleColumn('Thành tiền', flex: 12),
            _SaleColumn('', flex: 6),
          ];
    return LayoutBuilder(
      builder: (context, bounds) {
        const gap = 8.0;
        const pad = 16.0;
        const actionWidth = 44.0;
        final flex = columns.fold<int>(0, (sum, column) => sum + column.flex);
        final gaps = gap * (columns.length - 1);
        final content = (bounds.maxWidth - pad - gaps).clamp(
          0.0,
          double.infinity,
        );
        final action = actionWidth < content ? actionWidth : content;
        final restFlex = flex - columns.last.flex;
        final rest = content - action;
        final widths = [
          for (var i = 0; i < columns.length; i++)
            i == columns.length - 1
                ? action
                : rest * columns[i].flex / restFlex,
        ];
        Widget line(List<Widget> cells, {bool header = false, Key? rowKey}) =>
            Container(
              key: rowKey,
              color: header ? const Color(0xFFF8FAFB) : null,
              padding: EdgeInsets.symmetric(
                horizontal: 8,
                vertical: header ? 10 : 6,
              ),
              child: Row(
                children: [
                  for (var i = 0; i < cells.length; i++) ...[
                    if (i > 0) const SizedBox(width: gap),
                    SizedBox(
                      width: widths[i],
                      child: i == cells.length - 1
                          ? Align(alignment: Alignment.center, child: cells[i])
                          : cells[i],
                    ),
                  ],
                ],
              ),
            );
        return Column(
          children: [
            line([
              for (var i = 0; i < columns.length; i++)
                i == columns.length - 1 && headerAction != null
                    ? headerAction
                    : _header(columns[i].title),
            ], header: true),
            const Divider(height: 1),
            for (var i = 0; i < rows.length; i++) ...[
              line(rows[i], rowKey: rowKey(i)),
              const Divider(height: 1),
            ],
          ],
        );
      },
    );
  }

  Widget _addLineButton({
    required String tooltip,
    required VoidCallback? onPressed,
  }) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: const Icon(Icons.add, size: 22),
    style: IconButton.styleFrom(
      backgroundColor: _green,
      foregroundColor: Colors.white,
      disabledBackgroundColor: const Color(0xFFD5E3DF),
      disabledForegroundColor: Colors.white,
      fixedSize: const Size.square(36),
      minimumSize: const Size.square(36),
      maximumSize: const Size.square(36),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: const CircleBorder(),
    ),
  );

  Widget _header(String title) => Text(
    title,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: Color(0xFF56656D),
    ),
  );

  String _cellText(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? '—' : text;
  }

  CartItem? _linkedProduct(_ProductRow row) {
    final key = row.productKey;
    if (key == null) return null;
    for (final item in sale.cart.items) {
      if (!item.service && item.key == key) return item;
    }
    return null;
  }

  void _selectProduct(_ProductRow row, ProductSuggestion pick) {
    if (_productRows.any(
      (other) => other != row && other.productKey == pick.cartKey,
    )) {
      row.name.text = row.acceptedName;
      _showProductMessage('Sản phẩm đã có trong đơn hoặc đã đủ số lượng tồn');
      setState(() {});
      return;
    }
    final previous = _linkedProduct(row);
    if (previous != null && previous.key != pick.cartKey) {
      sale.cart.remove(previous);
    }
    final linked = _linkedProduct(row);
    final added =
        linked != null ||
        sale.cart.add(
          Map<String, dynamic>.from(pick.row),
          vehicle: pick.vehicle,
        );
    if (!added) {
      row.name.text = row.acceptedName;
      _showProductMessage('Sản phẩm đã có trong đơn hoặc đã đủ số lượng tồn');
      setState(() {});
      return;
    }
    row.productKey = pick.cartKey;
    row.vehicle = pick.vehicle;
    row.acceptedName = pick.name;
    final current = _linkedProduct(row);
    if (current != null && current.priceText.trim().isEmpty) {
      final raw = current.vehicle
          ? pick.row['GiaBan']
          : pick.row['GiaBanThamKhao'];
      if (raw is num && raw >= 0 && raw == raw.roundToDouble()) {
        sale.cart.setPrice(current, raw.toInt().toString());
      }
    }
    setState(() {});
  }

  void _productNameChanged(_ProductRow row, String value) {
    if (row.productKey != null && cleanName(value) != row.acceptedName) {
      final linked = _linkedProduct(row);
      if (linked != null) sale.cart.remove(linked);
      row.productKey = null;
      row.acceptedName = '';
    }
    setState(() {});
  }

  void _removeProductRow(_ProductRow row) {
    final linked = _linkedProduct(row);
    if (linked != null) sale.cart.remove(linked);
    row.dispose();
    _productRows.remove(row);
    if (_productRows.isEmpty) _productRows.add(_ProductRow.blank());
    setState(() {});
  }

  void _showProductMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String? _unselectedProductError() {
    for (final row in _productRows) {
      if (row.name.text.trim().isEmpty) continue;
      // Identity is the selected product key, not the text shown in the field.
      // Editing the text clears the key in _productNameChanged.
      if (row.productKey == null || _linkedProduct(row) == null) {
        return 'Chọn sản phẩm từ gợi ý.';
      }
    }
    return null;
  }

  bool get _hasTypedProduct =>
      _productRows.any((row) => row.name.text.trim().isNotEmpty);

  void _resetProductRows() {
    for (final row in _productRows) {
      row.dispose();
    }
    _productRows
      ..clear()
      ..add(_ProductRow.blank());
  }

  void _resetEntryRows() {
    _resetProductRows();
    _resetServiceRows();
  }

  List<Widget> _productCells(_ProductRow row) {
    final linked = _linkedProduct(row);
    Widget plain(Object? value) => Align(
      alignment: Alignment.centerLeft,
      child: Text(
        _cellText(linked == null ? null : value),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
    );
    final source = linked?.product;
    return [
      ProductNameField(
        controller: row.name,
        repository: _inventoryRepo,
        fieldKey: row.lineKey,
        onChanged: (value) => _productNameChanged(row, value),
        onSelected: (item) => _selectProduct(row, item),
      ),
      plain(source?['SoKhung']),
      plain(source?['SoMay']),
      plain(source?['BienSo']),
      plain(source?['MauSon']),
      linked == null
          ? const Text('—', style: TextStyle(fontSize: 13))
          : _quantityBox(linked),
      SizedBox(
        height: _fieldHeight,
        width: double.infinity,
        child: _moneyField(
          key: ValueKey('sales-price-${linked?.key ?? row.lineKey}'),
          enabled: linked != null && !sale.editingLocked,
          label: '',
          hint: '0',
          digits: linked?.priceText ?? '',
          onChanged: (value) {
            final current = _linkedProduct(row);
            if (current != null) sale.cart.setPrice(current, value);
          },
          validator: (_) {
            final current = _linkedProduct(row);
            if (current == null) return null;
            return current.unitPrice == null || current.unitPrice! < 0
                ? 'Nhập giá bán từ 0 đồng'
                : null;
          },
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          _amount(linked?.total),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      IconButton(
        tooltip: 'Bỏ khỏi đơn',
        onPressed: sale.editingLocked ? null : () => _removeProductRow(row),
        icon: const Icon(
          Icons.delete_outline,
          size: 18,
          color: Color(0xFFB44141),
        ),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(),
      ),
    ];
  }

  Widget _quantityBox(CartItem item) => SizedBox(
    key: ValueKey('sales-qty-${item.key}'),
    height: _fieldHeight,
    width: double.infinity,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0E7E9)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _quantityButton(
              tooltip: 'Giảm số lượng ${item.name}',
              icon: Icons.remove,
              onPressed: !item.vehicle && item.quantity > 1
                  ? () => sale.cart.setQuantity(item, item.quantity - 1)
                  : null,
            ),
            SizedBox(width: 22, child: Center(child: Text('${item.quantity}'))),
            _quantityButton(
              tooltip: 'Tăng số lượng ${item.name}',
              icon: Icons.add,
              onPressed:
                  !item.vehicle &&
                      (item.service ||
                          item.quantity < (item.product['SoLuongTon'] as num))
                  ? () => sale.cart.setQuantity(item, item.quantity + 1)
                  : null,
            ),
          ],
        ),
      ),
    ),
  );

  CartItem? _linkedService(_ServiceRow row) {
    final id = row.serviceId;
    if (id == null) return null;
    for (final item in sale.cart.items) {
      if (item.service && item.product['_id']?.toString() == id) return item;
    }
    return null;
  }

  void _selectService(_ServiceRow row, ServiceItem item) {
    final previous = _linkedService(row);
    if (previous != null && previous.product['_id']?.toString() != item.id) {
      sale.cart.remove(previous);
    }
    row.serviceId = item.id;
    row.priceText = item.price.toString();
    row.priceEpoch++;
    final linked = _linkedService(row);
    if (linked == null) {
      sale.cart.addService(item);
    }
    final current = _linkedService(row);
    if (current != null && current.priceText != row.priceText) {
      sale.cart.setPrice(current, row.priceText);
    }
    if (current != null && current.quantity != row.quantity) {
      sale.cart.setQuantity(current, row.quantity);
    }
    _syncDraftServiceSubtotal();
    setState(() {});
  }

  void _serviceNameChanged(_ServiceRow row, String value) {
    final linked = _linkedService(row);
    if (linked != null && cleanName(value) != linked.name) {
      sale.cart.remove(linked);
      row.serviceId = null;
    }
    _syncDraftServiceSubtotal();
    setState(() {});
  }

  void _setServiceQuantity(_ServiceRow row, int quantity) {
    if (quantity < 1) return;
    row.quantity = quantity;
    final linked = _linkedService(row);
    if (linked != null) {
      sale.cart.setQuantity(linked, quantity);
    }
    _syncDraftServiceSubtotal();
    if (linked == null) setState(() {});
  }

  void _removeServiceRow(_ServiceRow row) {
    final linked = _linkedService(row);
    if (linked != null) sale.cart.remove(linked);
    row.dispose();
    _serviceRows.remove(row);
    if (_serviceRows.isEmpty) _serviceRows.add(_ServiceRow.blank());
    _syncDraftServiceSubtotal();
    setState(() {});
  }

  void _resetServiceRows() {
    for (final row in _serviceRows) {
      row.dispose();
    }
    _serviceRows
      ..clear()
      ..add(_ServiceRow.blank());
    sale.setDraftServiceSubtotal(0);
  }

  bool get _hasNamedService =>
      _serviceRows.any((row) => row.name.text.trim().isNotEmpty);

  int _draftServiceSubtotal() {
    var total = 0;
    for (final row in _serviceRows) {
      if (_linkedService(row) != null || row.name.text.trim().isEmpty) continue;
      final digits = ungroupMoney(row.priceText);
      if (!RegExp(r'^\d+$').hasMatch(digits)) continue;
      final price = int.tryParse(digits);
      if (price != null) total += price * row.quantity;
    }
    return total;
  }

  void _syncDraftServiceSubtotal() {
    if (!mounted) return;
    sale.setDraftServiceSubtotal(_draftServiceSubtotal());
  }

  Future<String?> _commitNewServices() async {
    for (final row in _serviceRows) {
      final name = row.name.text.trim();
      if (name.isEmpty || row.serviceId != null) continue;
      final digits = ungroupMoney(row.priceText);
      if (!RegExp(r'^\d+$').hasMatch(digits)) {
        return 'Nhập giá cho dịch vụ $name trước khi lưu.';
      }
      try {
        final created = await _serviceRepo.create(
          ServiceDraft()
            ..name = name
            ..price = digits
            ..cost = '0',
        );
        if (!sale.cart.addService(created)) {
          return 'Không thêm được dịch vụ $name vào đơn.';
        }
        row.serviceId = created.id;
        final item = _linkedService(row);
        if (item != null && item.priceText != digits) {
          sale.cart.setPrice(item, digits);
        }
        if (item != null && item.quantity != row.quantity) {
          sale.cart.setQuantity(item, row.quantity);
        }
      } on ServiceException catch (error) {
        return error.message;
      } catch (_) {
        return 'Chưa thêm được dịch vụ $name. Kiểm tra dữ liệu trên máy.';
      }
    }
    return null;
  }

  List<Widget> _serviceCells(_ServiceRow row) {
    final linked = _linkedService(row);
    final quantity = linked?.quantity ?? row.quantity;
    final priceText = linked?.priceText ?? row.priceText;
    final total = linked?.total;
    final parsed = RegExp(r'^\d+$').hasMatch(ungroupMoney(priceText))
        ? int.tryParse(ungroupMoney(priceText))
        : null;
    return [
      ServiceNameField(
        controller: row.name,
        repository: _serviceRepo,
        fieldKey: row.lineKey,
        onChanged: (value) => _serviceNameChanged(row, value),
        onSelected: (item) => _selectService(row, item),
      ),
      _quantityEditor(
        key: ValueKey('sales-qty-${row.lineKey}'),
        name: row.name.text,
        quantity: quantity,
        canDecrease: quantity > 1,
        canIncrease: true,
        onDecrease: () => _setServiceQuantity(row, quantity - 1),
        onIncrease: () => _setServiceQuantity(row, quantity + 1),
      ),
      SizedBox(
        height: _fieldHeight,
        width: double.infinity,
        child: _moneyField(
          key: ValueKey('sales-price-${row.lineKey}-${row.priceEpoch}'),
          label: '',
          hint: '0',
          digits: priceText,
          onChanged: (value) {
            row.priceText = value;
            final current = _linkedService(row);
            if (current != null) {
              sale.cart.setPrice(current, value);
            } else {
              setState(() {});
            }
            _syncDraftServiceSubtotal();
          },
          validator: (_) {
            if (row.name.text.trim().isEmpty) return null;
            final digits = ungroupMoney(row.priceText);
            return RegExp(r'^\d+$').hasMatch(digits)
                ? null
                : 'Nhập giá bán từ 0 đồng';
          },
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          _amount(total ?? (parsed == null ? null : parsed * quantity)),
          key: ValueKey('sales-total-${row.lineKey}'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      IconButton(
        tooltip: 'Bỏ khỏi đơn',
        onPressed: sale.editingLocked ? null : () => _removeServiceRow(row),
        icon: const Icon(
          Icons.delete_outline,
          size: 18,
          color: Color(0xFFB44141),
        ),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(),
      ),
    ];
  }

  Widget _quantityEditor({
    required Key key,
    required String name,
    required int quantity,
    required bool canDecrease,
    required bool canIncrease,
    required VoidCallback onDecrease,
    required VoidCallback onIncrease,
  }) => SizedBox(
    key: key,
    height: _fieldHeight,
    width: double.infinity,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0E7E9)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _quantityButton(
              tooltip: 'Giảm số lượng $name',
              icon: Icons.remove,
              onPressed: canDecrease ? onDecrease : null,
            ),
            SizedBox(width: 22, child: Center(child: Text('$quantity'))),
            _quantityButton(
              tooltip: 'Tăng số lượng $name',
              icon: Icons.add,
              onPressed: canIncrease ? onIncrease : null,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _quantityButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: 16),
    constraints: const BoxConstraints.tightFor(width: 28, height: 28),
    style: IconButton.styleFrom(
      fixedSize: const Size.square(28),
      minimumSize: const Size.square(28),
      maximumSize: const Size.square(28),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    ),
    padding: EdgeInsets.zero,
  );

  Widget _payment() => FormSection(
    key: const ValueKey('sales-payment'),
    title: null,
    children: [
      LayoutBuilder(
        builder: (context, bounds) {
          final fields = <Widget>[
            _moneyField(
              key: ValueKey('sales-discount-${sale.revision}'),
              enabled: !sale.editingLocked,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              label: 'Giảm giá',
              hint: '0',
              digits: sale.discountText,
              onChanged: sale.setDiscount,
              validator: (_) => sale.discountError,
            ),
            _moneyField(
              key: ValueKey('sales-paid-${sale.revision}'),
              enabled: !sale.editingLocked,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              label: 'Khách thanh toán',
              hint: '0',
              digits: sale.paidText,
              onChanged: sale.setPaid,
              validator: (_) => sale.paidError,
            ),
            _debtDateField(interest: false),
            _debtDateField(interest: true),
          ];
          final minimumWidth = fields.length * 190.0 + (fields.length - 1) * 16;
          final width = bounds.maxWidth < minimumWidth
              ? minimumWidth
              : bounds.maxWidth;
          final scrolls = width > bounds.maxWidth;
          return Scrollbar(
            controller: _paymentFieldsScroll,
            thumbVisibility: scrolls,
            child: SingleChildScrollView(
              controller: _paymentFieldsScroll,
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: EdgeInsets.only(bottom: scrolls ? 12 : 0),
                child: SizedBox(
                  width: width,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < fields.length; i++) ...[
                        if (i > 0) const SizedBox(width: 16),
                        Expanded(child: fields[i]),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 16),
      LayoutBuilder(
        builder: (context, bounds) {
          final summary = Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _paymentAmount(
                'Tiền hàng',
                _amount(sale.subtotal),
                valueKey: const ValueKey('sales-summary-subtotal'),
              ),
              _paymentAmount(
                'Tổng thanh toán',
                _amount(sale.total),
                prominent: true,
                valueKey: const ValueKey('sales-summary-total'),
              ),
              _paymentAmount(
                'Còn phải thu',
                _amount(sale.due),
                valueKey: const ValueKey('sales-summary-due'),
              ),
              if ((sale.change ?? 0) > 0)
                _paymentAmount(
                  'Tiền thừa trả khách',
                  _amount(sale.change),
                  valueKey: const ValueKey('sales-summary-change'),
                ),
            ],
          );
          final actions = Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.end,
            children: [
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: sale.saving ? null : _preview,
                  icon: const Icon(Icons.visibility_outlined, size: 20),
                  label: const Text('Xem trước đơn hàng'),
                ),
              ),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed:
                      sale.saving ||
                          (sale.cart.items.isEmpty &&
                              !_hasNamedService &&
                              !_hasTypedProduct) ||
                          sale.salesRepository == null
                      ? null
                      : _save,
                  icon: sale.saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined, size: 20),
                  label: Text(
                    sale.saving
                        ? 'Đang lưu…'
                        : sale.awaitingConfirmation
                        ? 'Thử lưu lại'
                        : 'Lưu đơn hàng',
                  ),
                ),
              ),
            ],
          );
          return bounds.maxWidth >= 750
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: summary),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: actions,
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    summary,
                    const SizedBox(height: 18),
                    Align(alignment: Alignment.centerRight, child: actions),
                  ],
                );
        },
      ),
      if (sale.saveError != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            sale.saveError!,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ),
      if (sale.lastSavedId != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            'Đã lưu đơn hàng #${sale.lastSavedId}',
            style: const TextStyle(fontSize: 14, color: _green),
          ),
        ),
    ],
  );
  Widget _paymentAmount(
    String label,
    String value, {
    bool prominent = false,
    Key? valueKey,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 14, color: Color(0xFF6E7D83)),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        key: valueKey,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: prominent ? _green : const Color(0xFF1D3036),
        ),
      ),
    ],
  );
}

class _SaleColumn {
  const _SaleColumn(this.title, {required this.flex});
  final String title;
  final int flex;
}

class _ProductRow {
  _ProductRow.blank() : lineKey = 'product-default';
  _ProductRow.newLine() : lineKey = 'product-${UniqueKey()}';
  _ProductRow.linked(CartItem item)
    : lineKey = item.key,
      productKey = item.key,
      vehicle = item.vehicle,
      acceptedName = item.name {
    name.text = item.name;
  }

  final String lineKey;
  final name = TextEditingController();
  String? productKey;
  bool vehicle = false;
  String acceptedName = '';
  void dispose() => name.dispose();
}

class _ServiceRow {
  _ServiceRow.blank() : lineKey = 'draft-default';
  _ServiceRow.newLine() : lineKey = 'draft-${UniqueKey()}';
  _ServiceRow.linked(CartItem item)
    : lineKey = item.key,
      priceText = item.priceText,
      quantity = item.quantity,
      serviceId = item.product['_id']?.toString() {
    name.text = item.name;
  }
  final String lineKey;
  final name = TextEditingController();
  String priceText = '';
  int quantity = 1;
  int priceEpoch = 0;
  String? serviceId;
  void dispose() => name.dispose();
}
