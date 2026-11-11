import '../maintenance/record_line_delete_button.dart';
import '../../models/maintenance/record_maintenance.dart';
import '../maintenance/record_actions.dart';
import '../maintenance/record_recovery_button.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mongo_dart/mongo_dart.dart' show ObjectId;
import '../../controllers/order_details_controller.dart';
import '../../core/formatters/inventory_formatters.dart';
import '../../models/orders/order_details.dart';
import '../../models/repositories/order_repository.dart';
import '../../services/mongo_order_repository.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/form_section.dart';
import '../sales/sales_order_preview_popup.dart';
import '../widgets/scrollable_data_table.dart';
import 'order_payment_form.dart';

class OrderDetailsScreen extends StatefulWidget {
  const OrderDetailsScreen({super.key, required this.orderId, this.repository});
  final int orderId;
  final OrderRepository? repository;
  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen>
    with SingleTickerProviderStateMixin {
  late final OrderDetailsController _controller;
  late final TabController _tabs;
  dynamic _selectedPayment;
  bool _deletePayment = false;
  bool _editing = false;
  bool _deleting = false;
  void _choosePayment(dynamic id, bool deleting) {
    setState(() {
      _selectedPayment = id;
      _deletePayment = deleting;
    });
    _tabs.animateTo(0);
  }

  void _clearPayment() {
    setState(() {
      _selectedPayment = null;
      _deletePayment = false;
      _editing = false;
    });
  }

  Future<void> _openPrint(OrderDetails order, int tab) async {
    try {
      final data = order.toInvoice(widget.orderId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => SalesOrderPreviewPopup(data: data, initialTab: tab),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa mở được bản in. Vui lòng thử lại.')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _controller = OrderDetailsController(
      widget.repository ?? MongoOrderRepository(),
      widget.orderId,
    );
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _controller.dispose();
    if (widget.repository == null) unawaited(_controller.repository.close());
    super.dispose();
  }

  String _value(dynamic value) =>
      value == null || '$value'.trim().isEmpty ? '' : '$value';
  String _date(dynamic value) =>
      value is DateTime ? DateFormat('dd/MM/yyyy').format(value) : '';
  String _money(dynamic value) => value == null ? '' : money(value);
  Future<void> _pay(
    DateTime date,
    int amount,
    int interest,
    String notes,
    String id,
    DateTime? nextAppointment,
  ) async {
    await _controller.repository.pay(
      widget.orderId,
      date: date,
      amount: amount,
      interest: interest,
      notes: notes,
      requestId: id,
      nextAppointment: nextAppointment,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Thanh toán thành công')));
    _tabs.animateTo(2);
    await _controller.load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppTopBar(
      title: 'Đơn hàng #${widget.orderId}',
      actions: [
        RecordRecoveryButton(
          repository: _controller.repository.maintenance,
          onChanged: _controller.load,
        ),
      ],
    ),
    body: Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE5EAED)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerColor: Colors.transparent,
            labelColor: const Color(0xFF176455),
            indicatorColor: const Color(0xFF176455),
            tabs: const [
              Tab(text: 'Thông tin'),
              Tab(text: 'Danh sách sản phẩm'),
              Tab(text: 'Lịch sử thanh toán'),
              Tab(text: 'Thanh toán'),
            ],
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              if (_controller.loading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (_controller.error != null) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_controller.error!),
                      TextButton(
                        onPressed: _controller.load,
                        child: const Text('Thử lại'),
                      ),
                    ],
                  ),
                );
              }
              final order = _controller.data;
              if (order == null) return const SizedBox.shrink();
              return TabBarView(
                controller: _tabs,
                children: [
                  _information(order),
                  _products(order),
                  _payments(order),
                  OrderPaymentForm(order: order, onSave: _pay),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
  Widget _information(OrderDetails order) {
    final maintenance = _controller.repository.maintenance;
    if (maintenance != null && (_editing || _selectedPayment != null)) {
      return RecordEditor(
        key: ValueKey('inline:$_selectedPayment:$_deletePayment:$_editing'),
        repository: maintenance,
        kind: RecordKind.order,
        id: widget.orderId,
        paymentId: _selectedPayment,
        deleting: _selectedPayment != null && _deletePayment,
        embedded: true,
        onSaved: () async {
          _clearPayment();
          await _controller.load();
        },
        onDeleted: () => Navigator.pop(context),
        onCancel: _clearPayment,
      );
    }
    return _summary(order);
  }

  Future<void> _deleteOrder() async {
    final maintenance = _controller.repository.maintenance;
    if (maintenance == null || _deleting) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa đơn hàng'),
        content: Text(
          'Xóa đơn hàng #${widget.orderId} cùng chi tiết và các phiếu thu liên quan? Sản phẩm sẽ được hoàn lại tồn kho.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await maintenance.delete(
        RecordKind.order,
        widget.orderId,
        requestId: ObjectId().oid,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is RecordChangeException
                  ? error.message
                  : 'Chưa xóa được đơn hàng. Vui lòng thử lại.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Widget _summary(OrderDetails order) {
    final h = order.header, c = order.customer;
    final canChange = _controller.repository.maintenance != null;
    final fields = {
      'Mã đơn hàng': '#${widget.orderId}',
      'Ngày bán': _date(h['NgayMua']),
      'Khách hàng': _value(c?['TenKhachHang']),
      'Số điện thoại': _value(c?['SoDienThoai']),
      'Địa chỉ': _value(c?['DiaChiHienThi'] ?? c?['DiaChiChiTiet']),
      'Tiền hàng': _money(order.goodsTotal ?? order.total),
      'Giảm giá': _money(order.discount),
      'Tổng thanh toán': _money(order.total),
      'Đã thanh toán': _money(order.paid),
      'Còn nợ': _money(order.due),
      'Ngày hẹn thanh toán': _date(h['NgayHen']),
      'Ngày tính lãi': _date(h['NgayTinhLai']),
      'Ghi chú': _value(h['GhiChu']),
    };
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            child: FormSection(
              title: null,
              children: [
                ResponsiveFormFields(
                  compact: true,
                  fields: [
                    for (final field in fields.entries)
                      InputDecorator(
                        decoration: InputDecoration(labelText: field.key),
                        child: SelectableText(field.value),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                if (canChange) ...[
                  OutlinedButton.icon(
                    onPressed: _deleting
                        ? null
                        : () => setState(() => _editing = true),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Sửa'),
                  ),
                  TextButton.icon(
                    key: const ValueKey('order-delete'),
                    onPressed: _deleting ? null : _deleteOrder,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(_deleting ? 'Đang xóa…' : 'Xóa'),
                  ),
                ],
                OutlinedButton.icon(
                  key: const ValueKey('print-order-invoice'),
                  onPressed: _deleting ? null : () => _openPrint(order, 0),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('In hóa đơn'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('print-order-contract'),
                  onPressed: _deleting ? null : () => _openPrint(order, 1),
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('In hợp đồng'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _products(OrderDetails order) => Padding(
    padding: const EdgeInsets.all(24),
    child: order.lines.isEmpty
        ? const Center(child: Text('Chưa có chi tiết sản phẩm.'))
        : ScrollableDataTable(
            fixedHeader: true,
            columns: const [
              DataColumn(label: Text('SẢN PHẨM / DỊCH VỤ')),
              DataColumn(label: Text('THÔNG TIN')),
              DataColumn(label: Text('SỐ LƯỢNG')),
              DataColumn(label: Text('ĐƠN GIÁ')),
              DataColumn(label: Text('THÀNH TIỀN')),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final l in order.lines)
                DataRow(
                  cells: [
                    DataCell(Text(_value(l['TenSanPham']))),
                    DataCell(
                      Text(
                        l['IdXe'] == null
                            ? ''
                            : 'Xe #${l['IdXe']} · Số khung: ${_value(l['SoKhung'])} · Số máy: ${_value(l['SoMay'])} · Biển số: ${_value(l['BienSo'])} · Màu sơn: ${_value(l['MauSon'])}',
                      ),
                    ),
                    DataCell(Text(_value(l['SoLuong']))),
                    DataCell(Text(_money(OrderDetails.unitPrice(l)))),
                    DataCell(
                      Text(
                        _money(
                          l['ThanhTien'] ??
                              (OrderDetails.unitPrice(l) != null &&
                                      l['SoLuong'] is num
                                  ? OrderDetails.unitPrice(l)! *
                                        (l['SoLuong'] as num)
                                  : null),
                        ),
                      ),
                    ),
                    DataCell(
                      RecordLineDeleteButton(
                        repository: _controller.repository.maintenance,
                        kind: RecordKind.order,
                        parentId: widget.orderId,
                        lineId: l['_id'] ?? 'legacy-edit:${widget.orderId}',
                        onChanged: _controller.load,
                      ),
                    ),
                  ],
                ),
            ],
          ),
  );
  Widget _payments(OrderDetails order) => Padding(
    padding: const EdgeInsets.all(24),
    child: order.payments.isEmpty
        ? const Center(child: Text('Chưa có lịch sử thanh toán.'))
        : ScrollableDataTable(
            fixedHeader: true,
            columns: const [
              DataColumn(label: Text('MÃ THANH TOÁN')),
              DataColumn(label: Text('NGÀY')),
              DataColumn(label: Text('TIỀN TRẢ NỢ')),
              DataColumn(label: Text('LÃI ĐÃ THU')),
              DataColumn(label: Text('CÒN NỢ')),
              DataColumn(label: Text('GHI CHÚ')),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final p in order.payments)
                DataRow(
                  cells: [
                    DataCell(Text('#${p['IdTraNo']}')),
                    DataCell(Text(_date(p['NgayTra']))),
                    DataCell(Text(_money(p['SotienTra']))),
                    DataCell(Text(_money(p['LaiThu']))),
                    DataCell(Text(_money(p['SoCoNo']))),
                    DataCell(Text(_value(p['GhiChu']))),
                    DataCell(
                      RecordActions(
                        repository: _controller.repository.maintenance,
                        kind: RecordKind.order,
                        id: widget.orderId,
                        paymentId: p['_id'],
                        onSelect: (deleting) =>
                            _choosePayment(p['_id'], deleting),
                        onChanged: _controller.load,
                      ),
                    ),
                  ],
                ),
            ],
          ),
  );
}
