import 'package:mongo_dart/mongo_dart.dart' show ObjectId;
import '../maintenance/record_recovery_button.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../controllers/product_details_controller.dart';
import '../../core/formatters/inventory_formatters.dart';
import '../../models/products/product_details.dart';
import '../../models/repositories/product_details_repository.dart';
import '../../services/mongo_product_details_repository.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/form_section.dart';
import '../widgets/scrollable_data_table.dart';
import 'product_cost_form.dart';
import 'product_editor_popup.dart';

class ProductDetailsScreen extends StatefulWidget {
  const ProductDetailsScreen({
    super.key,
    required this.product,
    this.repository,
    this.initialTab = 0,
  });
  final ProductReference product;
  final ProductDetailsRepository? repository;
  final int initialTab;
  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen>
    with SingleTickerProviderStateMixin {
  late final ProductDetailsController _controller;
  late final TabController _tabs;
  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 5,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 4),
    );
    _controller = ProductDetailsController(
      widget.repository ?? MongoProductDetailsRepository(),
      widget.product,
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

  Future<void> _saveCost(
    DateTime date,
    int amount,
    String notes,
    String id,
  ) async {
    await _controller.addCost(
      date: date,
      amount: amount,
      notes: notes,
      requestId: id,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Thêm chi phí thành công')));
    if (_tabs.index != 3) _tabs.index = 3;
    try {
      await _controller.load(silent: true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã lưu chi phí nhưng chưa tải lại được danh sách.'),
        ),
      );
    }
  }

  bool _editing = false;
  Future<void> _delete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Xóa sản phẩm'),
        content: const Text(
          'Xóa sản phẩm này khỏi danh sách? Phiếu nhập, đơn bán, công nợ và chi phí đã ghi nhận vẫn được giữ nguyên.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _editing = true);
    try {
      await _controller.repository.archive(widget.product);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã xóa sản phẩm')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is StateError
                  ? e.message
                  : 'Không xóa được sản phẩm. Vui lòng thử lại.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  String? _costNote(ProductDetails details) {
    final info = details.information;
    if (widget.product.vehicle && info['TinhTrang'] == false) {
      return 'Xe đã bán. Chi phí vẫn được ghi nhận và tính vào lợi nhuận.';
    }
    final stock = info['SoLuongTon'];
    if (!widget.product.vehicle && stock is num && stock <= 0) {
      return 'Phụ tùng đã hết hàng. Chi phí vẫn được ghi nhận.';
    }
    return null;
  }

  String _value(dynamic v) => v == null || '$v'.trim().isEmpty ? '—' : '$v';
  String _date(dynamic v) =>
      v is DateTime ? DateFormat('dd/MM/yyyy').format(v) : '—';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => Scaffold(
      appBar: AppTopBar(
        title: 'Chi tiết sản phẩm',
        actions: [
          if (_controller.repository.maintenance != null)
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
                Tab(text: 'Thông tin sản phẩm'),
                Tab(text: 'Đơn bán'),
                Tab(text: 'Đơn nhập'),
                Tab(text: 'Danh sách chi phí'),
                Tab(text: 'Thêm chi phí'),
              ],
            ),
          ),
          Expanded(
            child: _controller.loading
                ? const Center(child: CircularProgressIndicator())
                : _controller.error != null
                ? Center(
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
                  )
                : _controller.data == null
                ? const SizedBox.shrink()
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _information(_controller.data!),
                      _orders(_controller.data!.sales, 'Chưa có đơn bán.'),
                      _orders(
                        _controller.data!.receipts,
                        'Chưa có đơn nhập.',
                        showPartner: true,
                      ),
                      _costs(_controller.data!),
                      ProductCostForm(
                        onSave: _saveCost,
                        note: _costNote(_controller.data!),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    ),
  );
  Widget _information(ProductDetails details) => ProductEditorPopup(
    product: widget.product,
    information: details.information,
    embedded: true,
    onSave: (draft) => _controller.repository.update(widget.product, draft),
    onSaved: _controller.load,
    onDelete: _delete,
  );

  Future<void> _deleteCost(Map<String, dynamic> cost) async {
    if (_editing || _controller.repository.maintenance == null) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Xóa chi phí sản phẩm'),
        content: const Text(
          'Xóa khoản chi phí này và phiếu chi tương ứng? Tổng chi phí sẽ được cập nhật lại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _editing = true);
    try {
      await _controller.repository.maintenance!.deleteCost(
        widget.product.vehicle,
        widget.product.id,
        cost,
        requestId: ObjectId().oid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã xóa chi phí')));
      try {
        await _controller.load(silent: true);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã xóa chi phí nhưng chưa tải lại được danh sách.'),
          ),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Widget _orders(
    List<Map<String, dynamic>> rows,
    String empty, {
    bool showPartner = false,
  }) => Padding(
    padding: const EdgeInsets.all(24),
    child: rows.isEmpty
        ? Center(child: Text(empty))
        : ScrollableDataTable(
            fixedHeader: true,
            columns: [
              const DataColumn(label: Text('MÃ ĐƠN')),
              if (showPartner) const DataColumn(label: Text('ĐỐI TÁC')),
              DataColumn(label: Text('NGÀY')),
              DataColumn(label: Text('SỐ LƯỢNG')),
              DataColumn(label: Text('TIỀN SẢN PHẨM')),
              DataColumn(label: Text('GHI CHÚ')),
            ],
            rows: [
              for (final r in rows)
                DataRow(
                  cells: [
                    DataCell(Text('#${r['Ma']}')),
                    if (showPartner) DataCell(Text(_value(r['DoiTac']))),
                    DataCell(Text(_date(r['Ngay']))),
                    DataCell(Text(_value(r['SoLuong']))),
                    DataCell(Text(money(r['SoTien']))),
                    DataCell(Text(_value(r['GhiChu']))),
                  ],
                ),
            ],
          ),
  );
  Widget _costs(ProductDetails details) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tổng chi phí: ${money(details.totalCosts)}',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF176455),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: details.costs.isEmpty
              ? const Center(child: Text('Chưa có chi phí.'))
              : ScrollableDataTable(
                  fixedHeader: true,
                  fitWidth: true,
                  columnWidths: const [150, 170, 280, 110],
                  columns: const [
                    DataColumn(label: Text('NGÀY')),
                    DataColumn(label: Text('SỐ TIỀN')),
                    DataColumn(label: Text('GHI CHÚ')),
                    DataColumn(label: Text('')),
                  ],
                  rows: [
                    for (var i = 0; i < details.costs.length; i++)
                      DataRow(
                        cells: [
                          DataCell(Text(_date(details.costs[i]['Ngay']))),
                          DataCell(Text(money(details.costs[i]['SoTien']))),
                          DataCell(Text(_value(details.costs[i]['GhiChu']))),
                          DataCell(
                            Align(
                              alignment: Alignment.centerRight,
                              child: Tooltip(
                                message: 'Xóa chi phí',
                                child: TextButton(
                                  key: ValueKey('delete-product-cost-$i'),
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    minimumSize: const Size(64, 36),
                                  ),
                                  onPressed:
                                      _editing ||
                                          _controller.repository.maintenance ==
                                              null
                                      ? null
                                      : () => _deleteCost(details.costs[i]),
                                  child: const Text(
                                    'Xóa',
                                    style: TextStyle(color: Color(0xFFB44141)),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
        ),
      ],
    ),
  );
}
