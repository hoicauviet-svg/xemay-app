import '../../models/products/product_list_report.dart';
import '../../models/reports/report_models.dart';
import '../finance/finance_list_widgets.dart';
import 'dart:async';
import '../../controllers/cart_controller.dart';
import 'package:flutter/material.dart';
import '../../controllers/service_controller.dart';
import '../../core/formatters/inventory_formatters.dart';
import '../../models/services/service_models.dart';
import '../../models/repositories/service_repository.dart';
import '../../services/mongo_service_repository.dart';
import '../widgets/scrollable_data_table.dart';
import 'service_editor_popup.dart';

class ServiceTab extends StatefulWidget {
  const ServiceTab({super.key, this.repository, this.exportReport});
  final ServiceRepository? repository;
  final Future<bool> Function(String, ReportSection, DateTime)? exportReport;
  @override
  State<ServiceTab> createState() => _ServiceTabState();
}

class _ServiceTabState extends State<ServiceTab>
    with AutomaticKeepAliveClientMixin {
  late final ServiceController _controller;
  final _focus = FocusNode();
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    _controller = ServiceController(
      widget.repository ?? MongoServiceRepository(),
    );
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _edit(ServiceItem item) async {
    final saved = await showDialog<ServiceItem>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          ServiceEditorPopup(controller: _controller, existing: item),
    );
    if (saved != null && mounted) await _controller.load();
  }

  Future<void> _delete(ServiceItem item) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Xóa dịch vụ'),
        content: Text(
          'Xóa "${item.name}" khỏi danh sách? Các đơn đã bán vẫn được giữ nguyên.',
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
    if (yes != true) return;
    try {
      await _controller.repository.delete(item.id);
      if (mounted) await _controller.load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không xóa được dịch vụ. Vui lòng thử lại.'),
          ),
        );
      }
    }
  }

  Widget _actions(ServiceItem item) => IconButtonTheme(
    data: IconButtonThemeData(
      style: IconButton.styleFrom(
        fixedSize: const Size.square(36),
        minimumSize: const Size.square(36),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Cập nhật dịch vụ',
          onPressed: () => _edit(item),
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: 'Xóa dịch vụ',
          onPressed: () => _delete(item),
          icon: const Icon(Icons.delete_outline, color: Color(0xFFB44141)),
        ),
        _addToOrder(item),
      ],
    ),
  );

  Future<void> _add() async {
    final item = await showDialog<ServiceItem>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ServiceEditorPopup(controller: _controller),
    );
    if (item != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã thêm dịch vụ')));
      await _controller.load();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5EAED)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ListenableBuilder(
                    listenable: _focus,
                    builder: (context, _) => Container(
                      key: const ValueKey('service-search'),
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _focus.hasFocus
                              ? const Color(0xFF176455)
                              : const Color(0xFFE0E7E9),
                        ),
                      ),
                      child: TextField(
                        focusNode: _focus,
                        onChanged: _controller.searchChanged,
                        textAlignVertical: TextAlignVertical.center,
                        decoration: const InputDecoration(
                          hintText: 'Tìm tên, mô tả dịch vụ…',
                          prefixIcon: Icon(Icons.search, size: 20),
                          prefixIconConstraints: BoxConstraints.tightFor(
                            width: 48,
                            height: 46,
                          ),
                          contentPadding: EdgeInsets.only(right: 12),
                          isDense: true,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton.filled(
                    key: const ValueKey('service-add'),
                    tooltip: 'Thêm dịch vụ',
                    onPressed: _add,
                    icon: const Icon(Icons.add),
                    style: IconButton.styleFrom(
                      fixedSize: const Size.square(48),
                      minimumSize: const Size.square(48),
                      maximumSize: const Size.square(48),
                      visualDensity: VisualDensity.standard,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: EdgeInsets.zero,
                      backgroundColor: const Color(0xFF176455),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                if (!_controller.loading &&
                    _controller.error == null &&
                    _controller.data != null) ...[
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 48,
                    child: FinanceExcelButton(
                      key: const ValueKey('service-export-excel'),
                      title: 'Dịch vụ',
                      section: _report,
                      loadedAt: _controller.loadedAt ?? DateTime.now(),
                      exporter: widget.exportReport,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  ReportSection get _report => ProductListReport.services(
    _controller.data?.rows ?? [],
    search: _controller.search,
  );
  Widget _body() {
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
    final rows = _controller.data!.rows;
    if (rows.isEmpty) {
      return Center(
        child: Text(
          _controller.search.trim().isEmpty
              ? 'Chưa có dịch vụ.'
              : 'Không tìm thấy dịch vụ.',
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, bounds) {
        if (bounds.maxWidth < 600) {
          return Column(
            children: [
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, i) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(rows[i].name),
                      subtitle: Text(rows[i].description),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(money(rows[i].price)),
                          _actions(rows[i]),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              FinanceTotalsStrip(
                totals: {'Tổng giá niêm yết': _report.totals['Giá tiền']},
              ),
            ],
          );
        }
        return ScrollableDataTable(
          fixedHeader: true,
          footerRow: DataRow(
            cells: [
              DataCell(const Text('Tổng giá niêm yết')),
              DataCell.empty,
              DataCell(Text(money(_report.totals['Giá tiền']))),
              DataCell.empty,
            ],
          ),
          fitWidth: true,
          columnWidths: const [240, 400, 160, 160],
          columns: const [
            DataColumn(label: Text('TÊN DỊCH VỤ')),
            DataColumn(label: Text('MÔ TẢ')),
            DataColumn(label: Text('GIÁ TIỀN')),
            DataColumn(label: Text('')),
          ],
          rowCount: rows.length,
          rowBuilder: (index) {
            final item = rows[index];
            return DataRow(
              cells: [
                DataCell(Text(item.name)),
                DataCell(
                  Text(
                    item.description.trim().isEmpty ? '—' : item.description,
                  ),
                ),
                DataCell(Text(money(item.price))),
                DataCell(_actions(item)),
              ],
            );
          },
        );
      },
    );
  }

  Widget _addToOrder(ServiceItem item) => IconButton(
    tooltip: 'Thêm dịch vụ vào đơn bán hàng',
    icon: const Icon(Icons.add_shopping_cart),
    onPressed: () {
      CartController.shared.addService(item);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã thêm dịch vụ vào đơn bán hàng')),
      );
    },
  );
}
