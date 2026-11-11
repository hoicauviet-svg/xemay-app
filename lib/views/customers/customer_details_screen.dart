import '../../models/customers/customer_models.dart';
import 'customer_editor_popup.dart';
import '../pawn/pawn_tab.dart';
import '../../models/repositories/pawn_repository.dart';
import '../orders/order_details_screen.dart';
import '../../models/repositories/order_repository.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../controllers/customer_details_controller.dart';
import '../../core/formatters/inventory_formatters.dart';
import '../../models/repositories/customer_repository.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/form_section.dart';
import '../widgets/scrollable_data_table.dart';

class CustomerDetailsScreen extends StatefulWidget {
  const CustomerDetailsScreen({
    super.key,
    required this.customerId,
    required this.repository,
    this.orderRepositoryFactory,
    this.pawnRepositoryFactory,
  });
  final int customerId;
  final CustomerRepository repository;
  final OrderRepository Function()? orderRepositoryFactory;
  final PawnRepository Function()? pawnRepositoryFactory;
  @override
  State<CustomerDetailsScreen> createState() => _CustomerDetailsScreenState();
}

class _CustomerDetailsScreenState extends State<CustomerDetailsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _pawnVisited = false;
  void _tabChanged() {
    if (_tabs.index == 2 && !_pawnVisited) setState(() => _pawnVisited = true);
  }

  late final CustomerDetailsController _controller;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this)..addListener(_tabChanged);
    _controller = CustomerDetailsController(
      widget.repository,
      widget.customerId,
    );
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _tabs.removeListener(_tabChanged);
    _tabs.dispose();
    _controller.dispose();
    super.dispose();
  }

  String _value(dynamic v) =>
      v == null || v.toString().trim().isEmpty ? '—' : v.toString();
  String _date(dynamic v) =>
      v is DateTime ? DateFormat('dd/MM/yyyy').format(v) : _value(v);
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppTopBar(
        title: 'Khách hàng #${widget.customerId}',
        bottom: TabBar(
          controller: _tabs,
          tabAlignment: TabAlignment.start,
          isScrollable: true,
          tabs: [
            Tab(text: 'Thông tin'),
            Tab(text: 'Đơn hàng'),
            Tab(text: 'Cầm đồ'),
          ],
        ),
      ),
      body: ListenableBuilder(
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
          final customer = _controller.customer!;
          return TabBarView(
            controller: _tabs,
            children: [
              Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: FormSection(
                        title: 'Thông tin khách hàng',
                        children: [
                          ResponsiveFormFields(
                            fields: [
                              _info('Mã khách hàng', '#${customer['IdKH']}'),
                              _info(
                                'Tên khách hàng',
                                _value(customer['TenKhachHang']),
                              ),
                              _info(
                                'Số điện thoại',
                                _value(customer['SoDienThoai']),
                              ),
                              _info('CCCD', _value(customer['SoCCCD'])),
                              _info('CMND', _value(customer['SoCMND'])),
                              _info(
                                'Ngày cấp',
                                CustomerDraft.formatIssueDate(
                                  customer['NgayCap'],
                                ),
                              ),
                              _info('Nơi cấp', _value(customer['NoiCap'])),
                              _info(
                                'Địa chỉ chi tiết',
                                _value(customer['DiaChiHienThi']),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            key: const ValueKey('customer-edit'),
                            onPressed: _busy ? null : () => _edit(customer),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Sửa'),
                          ),
                          TextButton.icon(
                            key: const ValueKey('customer-delete'),
                            onPressed: _busy ? null : () => _delete(customer),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Xóa'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Expanded(child: _orders()),
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_controller.orders!.total} đơn hàng',
                            ),
                          ),
                          IconButton(
                            tooltip: 'Trang đơn hàng trước',
                            onPressed: _controller.page > 0
                                ? () =>
                                      _controller.goToPage(_controller.page - 1)
                                : null,
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Text(
                            '${_controller.page + 1} / ${_controller.pageCount}',
                          ),
                          IconButton(
                            tooltip: 'Trang đơn hàng sau',
                            onPressed:
                                _controller.page + 1 < _controller.pageCount
                                ? () =>
                                      _controller.goToPage(_controller.page + 1)
                                : null,
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_pawnVisited)
                PawnTab(
                  customerId: widget.customerId,
                  readOnly: true,
                  repository: widget.pawnRepositoryFactory?.call(),
                )
              else
                const SizedBox.shrink(),
            ],
          );
        },
      ),
    ),
  );
  Widget _info(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 12, color: Color(0xFF6E7D83)),
      ),
      const SizedBox(height: 6),
      SelectableText(
        value,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
    ],
  );
  Future<void> _edit(Map<String, dynamic> customer) async {
    final saved = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CustomerEditorPopup(
        initial: customer,
        onCreate: (draft) => widget.repository.update(widget.customerId, draft),
      ),
    );
    if (saved == null || !mounted) return;
    await _controller.load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cập nhật khách hàng thành công')),
    );
  }

  Future<void> _delete(Map<String, dynamic> customer) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa khách hàng'),
        content: Text(
          'Xóa khách hàng "${customer['TenKhachHang']}" (#${customer['IdKH']}) khỏi danh sách?',
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
    if (confirm != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repository.delete(customer);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is CustomerException
                  ? error.message
                  : 'Không xóa được khách hàng. Vui lòng thử lại.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openOrder(Map<String, dynamic> row) async {
    final repository = widget.orderRepositoryFactory?.call();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => OrderDetailsScreen(
          orderId: (row['MaDonHang'] as num).toInt(),
          repository: repository,
        ),
      ),
    );
    if (repository != null) await repository.close();
    if (mounted) await _controller.load();
  }

  Widget _orders() {
    final rows = _controller.orders!.rows;
    if (rows.isEmpty) {
      return const Center(child: Text('Khách hàng chưa có đơn bán hàng.'));
    }
    return LayoutBuilder(
      builder: (context, bounds) {
        if (bounds.maxWidth < 700) {
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (context, i) {
              final r = rows[i];
              return ListTile(
                onTap: () => _openOrder(r),
                contentPadding: EdgeInsets.zero,
                title: Text('#${r['MaDonHang']} · ${_date(r['NgayDonHang'])}'),
                subtitle: Text(
                  '${_value(r['SanPhamHienThi'])}\nSố lượng: ${_value(r['TongSoLuong'])} · ${money(r['TongTien'])}\n${_value(r['GhiChu'])}',
                ),
              );
            },
          );
        }
        return ScrollableDataTable(
          fixedHeader: true,
          fitWidth: true,
          columnWidths: const [100, 120, 260, 90, 170, 200],
          columns: const [
            DataColumn(label: Text('MÃ ĐƠN')),
            DataColumn(label: Text('NGÀY')),
            DataColumn(label: Text('SẢN PHẨM')),
            DataColumn(label: Text('SỐ LƯỢNG')),
            DataColumn(label: Text('TỔNG TIỀN')),
            DataColumn(label: Text('GHI CHÚ')),
          ],
          rows: [
            for (final r in rows)
              DataRow(
                onSelectChanged: (_) => _openOrder(r),
                cells: [
                  DataCell(Text('#${r['MaDonHang']}')),
                  DataCell(Text(_date(r['NgayDonHang']))),
                  DataCell(Text(_value(r['SanPhamHienThi']))),
                  DataCell(Text(_value(r['TongSoLuong']))),
                  DataCell(Text(money(r['TongTien']))),
                  DataCell(Text(_value(r['GhiChu']))),
                ],
              ),
          ],
        );
      },
    );
  }
}
