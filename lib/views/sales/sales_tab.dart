import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../controllers/cart_controller.dart';
import '../../controllers/sales_controller.dart';
import '../../models/printing/sales_invoice_data.dart';
import '../../core/formatters/inventory_formatters.dart';
import 'sales_order_preview_popup.dart';
import '../widgets/form_section.dart';
import '../customers/customer_editor_popup.dart';
import 'sales_customer_picker.dart';

class SalesTab extends StatefulWidget {
  const SalesTab({
    super.key,
    required this.controller,
    required this.onAddProducts,
    required this.onAddServices,
  });
  final SalesController controller;
  final VoidCallback onAddProducts, onAddServices;
  @override
  State<SalesTab> createState() => _SalesTabState();
}

class _SalesTabState extends State<SalesTab> {
  final _form = GlobalKey<FormState>();
  final _paymentFieldsScroll = ScrollController();
  @override
  void dispose() {
    _paymentFieldsScroll.dispose();
    super.dispose();
  }

  SalesController get sale => widget.controller;
  static const _green = Color(0xFF176455);
  String _amount(int? value) => value == null ? '—' : money(value);
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

  final _addKey = GlobalKey();
  Future<void> _showAddMenu() async {
    final button = _addKey.currentContext!.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final origin = button.localToGlobal(Offset.zero, ancestor: overlay);
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        origin & button.size,
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          value: 'product',
          child: ListTile(
            leading: Icon(Icons.inventory_2_outlined),
            title: Text('Thêm sản phẩm'),
          ),
        ),
        PopupMenuItem(
          value: 'service',
          child: ListTile(
            leading: Icon(Icons.build_outlined),
            title: Text('Thêm dịch vụ'),
          ),
        ),
      ],
    );
    if (!mounted) return;
    if (selected == 'product') widget.onAddProducts();
    if (selected == 'service') widget.onAddServices();
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
                                ? 300
                                : bounds.maxHeight * .48,
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
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
            builder: (context, bounds) {
              final title = Text(
                'Sản phẩm & dịch vụ (${sale.cart.items.length})',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              );
              final add = Tooltip(
                message: 'Thêm sản phẩm / dịch vụ',
                child: FilledButton.icon(
                  key: _addKey,
                  onPressed: _showAddMenu,
                  icon: const Icon(Icons.add, size: 24),
                  label: const Text(
                    'Thêm sản phẩm / dịch vụ',
                    maxLines: 2,
                    textAlign: TextAlign.center,
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
              );
              return bounds.maxWidth >= 600
                  ? Row(
                      children: [
                        Expanded(child: title),
                        const SizedBox(width: 12),
                        add,
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        title,
                        const SizedBox(height: 10),
                        SizedBox(width: double.infinity, child: add),
                      ],
                    );
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Padding(padding: const EdgeInsets.all(12), child: _lines()),
        ),
      ],
    ),
  );

  Widget _lines({bool shrinkWrap = false}) {
    if (sale.cart.items.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5EAED)),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.shopping_bag_outlined,
                  size: 48,
                  color: Color(0xFF93A6A0),
                ),
                SizedBox(height: 16),
                Text(
                  'Chưa chọn sản phẩm bán hàng',
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Text(
                  'Thêm xe, phụ tùng hoặc dịch vụ để lập đơn.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Color(0xFF6E7D83)),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: EdgeInsets.zero,
      itemCount: sale.cart.items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _line(sale.cart.items[index]),
    );
  }

  Widget _line(CartItem item) => LayoutBuilder(
    builder: (context, bounds) =>
        bounds.maxWidth >= 850 ? _compactLine(item) : _stackedLine(item),
  );

  Widget _compactLine(CartItem item) => Container(
    key: ValueKey('sales-line-${item.key}'),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFE5EAED)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.service
                    ? 'Dịch vụ'
                    : item.vehicle
                    ? 'Xe · #${item.product['IdXe']}'
                    : 'Phụ tùng · #${item.product['IdSanPham']}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF6E7D83)),
              ),
              if (item.vehicle) ...[
                const SizedBox(height: 4),
                for (final entry in {
                  'Số khung': item.product['SoKhung'],
                  'Số máy': item.product['SoMay'],
                  'Biển số': item.product['BienSo'],
                  'Màu sơn': item.product['MauSon'],
                }.entries)
                  Tooltip(
                    message: '${entry.key}: ${entry.value ?? '—'}',
                    child: Text(
                      '${entry.key}: ${entry.value == null || entry.value.toString().trim().isEmpty ? '—' : entry.value}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6E7D83),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 125,
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Số lượng',
              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  tooltip: 'Giảm số lượng ${item.name}',
                  onPressed: !item.vehicle && item.quantity > 1
                      ? () => sale.cart.setQuantity(item, item.quantity - 1)
                      : null,
                  icon: const Icon(Icons.remove, size: 16),
                  constraints: const BoxConstraints.tightFor(
                    width: 30,
                    height: 30,
                  ),
                  style: IconButton.styleFrom(
                    fixedSize: const Size.square(30),
                    minimumSize: const Size.square(30),
                    maximumSize: const Size.square(30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.standard,
                  ),
                  padding: EdgeInsets.zero,
                ),
                Text('${item.quantity}'),
                IconButton(
                  tooltip: 'Tăng số lượng ${item.name}',
                  onPressed:
                      !item.vehicle &&
                          (item.service ||
                              item.quantity <
                                  (item.product['SoLuongTon'] as num))
                      ? () => sale.cart.setQuantity(item, item.quantity + 1)
                      : null,
                  icon: const Icon(Icons.add, size: 16),
                  constraints: const BoxConstraints.tightFor(
                    width: 30,
                    height: 30,
                  ),
                  style: IconButton.styleFrom(
                    fixedSize: const Size.square(30),
                    minimumSize: const Size.square(30),
                    maximumSize: const Size.square(30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.standard,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 170,
          child: TextFormField(
            key: ValueKey('sales-price-${item.key}'),
            initialValue: item.priceText,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Đơn giá',
              suffixText: 'đ',
              hintText: 'Nhập giá bán',
            ),
            onChanged: (v) => sale.cart.setPrice(item, v),
            validator: (_) => item.unitPrice == null || item.unitPrice! < 0
                ? 'Nhập giá bán từ 0 đồng'
                : null,
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 145,
          child: _paymentAmount('Thành tiền', _amount(item.total)),
        ),
        IconButton(
          tooltip: 'Bỏ khỏi đơn',
          onPressed: () => sale.cart.remove(item),
          icon: const Icon(
            Icons.delete_outline,
            size: 20,
            color: Color(0xFFB44141),
          ),
        ),
      ],
    ),
  );

  Widget _stackedLine(CartItem item) => Container(
    key: ValueKey('sales-line-${item.key}'),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE5EAED)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF3EF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                item.service
                    ? Icons.build_outlined
                    : item.vehicle
                    ? Icons.two_wheeler
                    : Icons.settings_outlined,
                color: _green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    item.service
                        ? 'Dịch vụ'
                        : item.vehicle
                        ? 'Xe · #${item.product['IdXe']}'
                        : 'Phụ tùng · #${item.product['IdSanPham']}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6E7D83),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Bỏ khỏi đơn',
              onPressed: () => sale.cart.remove(item),
              icon: const Icon(Icons.delete_outline, color: Color(0xFFB44141)),
            ),
          ],
        ),
        if (item.vehicle)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                for (final e in {
                  'Số khung': item.product['SoKhung'],
                  'Số máy': item.product['SoMay'],
                  'Biển số': item.product['BienSo'],
                  'Màu sơn': item.product['MauSon'],
                }.entries)
                  Text(
                    '${e.key}: ${e.value == null || e.value.toString().trim().isEmpty ? '—' : e.value}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6E7D83),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 140,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Số lượng',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      tooltip: 'Giảm số lượng ${item.name}',
                      onPressed: !item.vehicle && item.quantity > 1
                          ? () => sale.cart.setQuantity(item, item.quantity - 1)
                          : null,
                      icon: const Icon(Icons.remove, size: 18),
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                    Text('${item.quantity}'),
                    IconButton(
                      tooltip: 'Tăng số lượng ${item.name}',
                      onPressed:
                          !item.vehicle &&
                              (item.service ||
                                  item.quantity <
                                      (item.product['SoLuongTon'] as num))
                          ? () => sale.cart.setQuantity(item, item.quantity + 1)
                          : null,
                      icon: const Icon(Icons.add, size: 18),
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 180,
              child: TextFormField(
                key: ValueKey('sales-price-${item.key}'),
                initialValue: item.priceText,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Đơn giá',
                  suffixText: 'đ',
                  hintText: 'Nhập giá bán',
                ),
                onChanged: (v) => sale.cart.setPrice(item, v),
                validator: (_) => item.unitPrice == null || item.unitPrice! < 0
                    ? 'Nhập giá bán từ 0 đồng'
                    : null,
              ),
            ),
            SizedBox(
              width: 160,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Thành tiền',
                    style: TextStyle(fontSize: 12, color: Color(0xFF6E7D83)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _amount(item.total),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _green,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
  Widget _payment() => FormSection(
    key: const ValueKey('sales-payment'),
    title: null,
    children: [
      LayoutBuilder(
        builder: (context, bounds) {
          final fields = <Widget>[
            TextFormField(
              key: ValueKey('sales-discount-${sale.revision}'),
              enabled: !sale.editingLocked,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              initialValue: sale.discountText,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Giảm giá',
                suffixText: 'đ',
                hintText: '0',
              ),
              onChanged: sale.setDiscount,
              validator: (_) => sale.discountError,
            ),
            TextFormField(
              key: ValueKey('sales-paid-${sale.revision}'),
              enabled: !sale.editingLocked,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              initialValue: sale.paidText,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Khách thanh toán',
                suffixText: 'đ',
                hintText: '0',
              ),
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
              _paymentAmount('Tiền hàng', _amount(sale.subtotal)),
              _paymentAmount(
                'Tổng thanh toán',
                _amount(sale.total),
                prominent: true,
              ),
              _paymentAmount('Còn phải thu', _amount(sale.due)),
              if ((sale.change ?? 0) > 0)
                _paymentAmount('Tiền thừa trả khách', _amount(sale.change)),
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
                          sale.cart.items.isEmpty ||
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
  Widget _paymentAmount(String label, String value, {bool prominent = false}) =>
      Column(
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
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: prominent ? _green : const Color(0xFF1D3036),
            ),
          ),
        ],
      );
}
