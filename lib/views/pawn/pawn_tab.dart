import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../controllers/pawn_controller.dart';
import '../../core/formatters/inventory_formatters.dart';
import '../../models/repositories/customer_repository.dart';
import '../../models/repositories/pawn_repository.dart';
import '../../services/mongo_customer_repository.dart';
import '../../services/mongo_pawn_repository.dart';
import 'pawn_details_screen.dart';
import '../printing/pawn_contract_screen.dart';
import '../widgets/scrollable_data_table.dart';
import 'pawn_editor_popup.dart';

class PawnTab extends StatefulWidget {
  const PawnTab({
    super.key,
    this.repository,
    this.customers,
    this.customerId,
    this.readOnly = false,
  });
  final int? customerId;
  final bool readOnly;
  final PawnRepository? repository;
  final CustomerRepository? customers;
  @override
  State<PawnTab> createState() => _PawnTabState();
}

class _PawnTabState extends State<PawnTab> {
  late final PawnController _controller;
  late final CustomerRepository _customers;
  final _search = TextEditingController();
  Timer? _debounce;
  @override
  void initState() {
    super.initState();
    _controller = PawnController(
      widget.repository ?? MongoPawnRepository(),
      customerId: widget.customerId,
    );
    _customers = widget.customers ?? MongoCustomerRepository();
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _controller.dispose();
    unawaited(_controller.repository.close());
    unawaited(_customers.close());
    super.dispose();
  }

  String _value(dynamic v) => v == null ? '' : '$v';
  String _money(dynamic v) => v == null ? '' : money(v);
  String _date(dynamic v) =>
      v is DateTime ? DateFormat('dd/MM/yyyy').format(v) : '';
  String _rate(Map<String, dynamic> r) => r['LaiSuat'] == null
      ? ''
      : '${quantity(r['LaiSuat'] as num)} ${r['NgayPhanTram'] == true
            ? 'đ/triệu/ngày'
            : r['NgayPhanTram'] == false
            ? '%/tháng'
            : ''}';
  String _status(dynamic flag) => flag == true
      ? 'Đã chuộc / tất toán'
      : flag == false
      ? 'Đang cầm'
      : '';
  Future<void> _printContract(int id) async {
    try {
      final details = await _controller.repository.details(id);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => PawnContractScreen(details: details)),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Phiếu đã lưu. Không tải được hợp đồng để in; hãy mở lại từ chi tiết phiếu.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _add() async {
    var printAfterSave = false;
    final id = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PawnEditorPopup(
        repository: _controller.repository,
        customers: _customers,
        onPrintRequested: () => printAfterSave = true,
      ),
    );
    if (id != null && mounted) {
      _controller.page = 0;
      _search.clear();
      _controller.search = '';
      await _controller.load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã lưu phiếu cầm đồ #$id'),
            action: SnackBarAction(
              label: 'In hợp đồng',
              onPressed: () => _printContract(id),
            ),
          ),
        );
      }
      if (mounted && printAfterSave) await _printContract(id);
    }
  }

  Future<void> _details(Map<String, dynamic> row) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PawnDetailsScreen(
          id: (row['IdCamDo'] as num).toInt(),
          repository: _controller.repository,
        ),
      ),
    );
    if (mounted) await _controller.load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => Container(
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
                child: SizedBox(
                  height: 48,
                  child: TextField(
                    key: const ValueKey('pawn-search'),
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Tìm mã cầm đồ, khách hàng, tài sản…',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: PopupMenuButton<String>(
                        key: const ValueKey('pawn-status-filter'),
                        tooltip: 'Lọc trạng thái cầm đồ',
                        icon: const Icon(Icons.filter_list),
                        initialValue: _controller.status,
                        onSelected: (value) {
                          _debounce?.cancel();
                          _controller.search = _search.text;
                          _controller.setStatus(value);
                        },
                        itemBuilder: (_) => [
                          for (final option
                              in PawnController.statusLabels.entries)
                            CheckedPopupMenuItem<String>(
                              value: option.key,
                              checked: _controller.status == option.key,
                              child: Text(option.value),
                            ),
                        ],
                      ),
                    ),
                    onChanged: (v) {
                      _debounce?.cancel();
                      _debounce = Timer(
                        const Duration(milliseconds: 300),
                        () => _controller.changeSearch(v),
                      );
                    },
                  ),
                ),
              ),
              if (!widget.readOnly) ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton.filled(
                    key: const ValueKey('pawn-add'),
                    tooltip: 'Thêm phiếu cầm đồ',
                    onPressed: _add,
                    icon: const Icon(Icons.add),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Expanded(child: _content()),
          if (_controller.data != null &&
              !_controller.loading &&
              _controller.error == null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${_controller.data!.total} phiếu cầm đồ'),
                  ),
                  IconButton(
                    tooltip: 'Trang trước',
                    onPressed: _controller.page > 0
                        ? () => _controller.goToPage(_controller.page - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('${_controller.page + 1} / ${_controller.pageCount}'),
                  IconButton(
                    tooltip: 'Trang sau',
                    onPressed: _controller.page + 1 < _controller.pageCount
                        ? () => _controller.goToPage(_controller.page + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
  Widget _content() {
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
    final rows = _controller.data?.rows ?? [];
    if (rows.isEmpty) {
      return const Center(child: Text('Chưa có phiếu cầm đồ phù hợp.'));
    }
    return LayoutBuilder(
      builder: (context, bounds) {
        if (bounds.maxWidth < 700) {
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (context, index) {
              final r = rows[index];
              return ListTile(
                onTap: () => _details(r),
                title: Text('#${r['IdCamDo']} · ${_value(r['TenKhachHang'])}'),
                subtitle: Text(
                  '${_value(r['TaiSanTheChap'])}\n${_money(r['SoTienVay'])} · ${_rate(r)}\nNgày vay: ${_date(r['NgayVay'])}\nNgày hạn: ${_date(r['NgayHan'])}\n${_status(r['TrangThai'])}',
                ),
              );
            },
          );
        }
        return ScrollableDataTable(
          fixedHeader: true,
          fitWidth: true,
          rowHeight: 80,
          columnWidths: const [76, 170, 220, 140, 110, 220, 150],
          columns: const [
            DataColumn(label: Text('MÃ')),
            DataColumn(label: Text('KHÁCH HÀNG')),
            DataColumn(label: Text('TÀI SẢN THẾ CHẤP')),
            DataColumn(label: Text('SỐ TIỀN VAY')),
            DataColumn(label: Text('LÃI SUẤT')),
            DataColumn(label: Text('NGÀY THÁNG')),
            DataColumn(label: Text('TRẠNG THÁI')),
          ],
          rows: [
            for (final r in rows)
              DataRow(
                onSelectChanged: (_) => _details(r),
                cells: [
                  DataCell(Text('#${r['IdCamDo']}')),
                  DataCell(
                    Text(
                      _value(r['TenKhachHang']),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DataCell(
                    Text(
                      _value(r['TaiSanTheChap']),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DataCell(Text(_money(r['SoTienVay']))),
                  DataCell(Text(_rate(r))),
                  DataCell(
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ngày vay: ${_date(r['NgayVay'])}',
                          style: const TextStyle(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Ngày hạn: ${_date(r['NgayHan'])}',
                          style: const TextStyle(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  DataCell(
                    Text(
                      _status(r['TrangThai']),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}
