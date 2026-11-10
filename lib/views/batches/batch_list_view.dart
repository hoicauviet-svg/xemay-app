import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../controllers/batch_list_controller.dart';
import '../../core/formatters/inventory_formatters.dart';
import '../../models/goods_receipt/goods_receipt_models.dart';
import '../../models/repositories/batch_repository.dart';
import '../../models/repositories/directory_repository.dart';
import '../widgets/scrollable_data_table.dart';
import 'batch_details_screen.dart';

class BatchListView extends StatefulWidget {
  const BatchListView({
    super.key,
    required this.type,
    required this.repository,
    this.directoryRepository,
    required this.onCreate,
    this.onCreateSingle,
  });
  final ReceiptProductType type;
  final BatchRepository repository;
  final DirectoryRepository? directoryRepository;
  final Future<void> Function() onCreate;
  final Future<void> Function()? onCreateSingle;
  @override
  State<BatchListView> createState() => _BatchListViewState();
}

class _BatchListViewState extends State<BatchListView> {
  late final BatchListController _controller;
  final _search = TextEditingController();
  @override
  void initState() {
    super.initState();
    _controller = BatchListController(widget.repository, widget.type);
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    await widget.onCreate();
    if (mounted) await _controller.load();
  }

  Future<void> _createSingle() async {
    await widget.onCreateSingle!();
    if (mounted) await _controller.load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, bounds) => Row(
              children: [
                Expanded(
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFE0E7E9)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: TextField(
                      controller: _search,
                      textAlignVertical: TextAlignVertical.center,
                      onChanged: _controller.searchChanged,
                      decoration: const InputDecoration(
                        hintText: 'Tìm mã lô, vận chuyển, đối tác…',
                        prefixIcon: Icon(Icons.search, size: 20),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.only(right: 12),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Làm mới lô hàng',
                  onPressed: _controller.loading ? null : _controller.load,
                  icon: const Icon(Icons.refresh),
                ),
                const SizedBox(width: 8),
                widget.onCreateSingle == null
                    ? SizedBox(
                        height: 48,
                        child: bounds.maxWidth >= 650
                            ? FilledButton.icon(
                                onPressed: _create,
                                icon: const Icon(Icons.add),
                                label: const Text('Nhập lô hàng'),
                              )
                            : IconButton.filled(
                                tooltip: 'Nhập lô hàng',
                                onPressed: _create,
                                icon: const Icon(Icons.add),
                              ),
                      )
                    : PopupMenuButton<ReceiptMode>(
                        tooltip: 'Nhập hàng',
                        offset: const Offset(0, 52),
                        onSelected: (mode) => unawaited(
                          mode == ReceiptMode.single
                              ? _createSingle()
                              : _create(),
                        ),
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: ReceiptMode.single,
                            child: Text('Nhập lẻ'),
                          ),
                          PopupMenuItem(
                            value: ReceiptMode.batch,
                            child: Text('Nhập lô'),
                          ),
                        ],
                        child: const SizedBox(
                          key: ValueKey('receipt-add'),
                          width: 48,
                          height: 48,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Color(0xFF176455),
                              borderRadius: BorderRadius.all(
                                Radius.circular(10),
                              ),
                            ),
                            child: Center(
                              child: Icon(Icons.add, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
              ],
            ),
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
                    child: Text(
                      '${quantity(_controller.data!.total)} lô hàng',
                      style: const TextStyle(
                        color: Color(0xFF6E7D83),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Trang lô trước',
                    onPressed: _controller.hasPrevious
                        ? _controller.previousPage
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('${_controller.page + 1}'),
                  IconButton(
                    tooltip: 'Trang lô sau',
                    onPressed: _controller.hasNext
                        ? _controller.nextPage
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
            Text(_controller.error!, textAlign: TextAlign.center),
            TextButton(
              onPressed: _controller.load,
              child: const Text('Thử lại'),
            ),
          ],
        ),
      );
    }
    final page = _controller.data!;
    if (page.batches.isEmpty) {
      return Center(
        child: Text(
          _search.text.trim().isEmpty
              ? 'Chưa có lô hàng.'
              : 'Không tìm thấy lô hàng.',
        ),
      );
    }
    return ScrollableDataTable(
      fixedHeader: true,
      fitWidth: true,
      columnWidths: const [90, 130, 200, 260, 110, 140, 140],
      columns: const [
        DataColumn(label: Text('MÃ LÔ')),
        DataColumn(label: Text('NGÀY NHẬP')),
        DataColumn(label: Text('VẬN CHUYỂN')),
        DataColumn(label: Text('ĐỐI TÁC / NHÀ CUNG CẤP')),
        DataColumn(label: Text('SỐ LƯỢNG')),
        DataColumn(label: Text('TỔNG TIỀN')),
        DataColumn(label: Text('CÒN NỢ')),
      ],
      rows: [
        for (final batch in page.batches)
          DataRow(
            onSelectChanged: (_) async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (context) => BatchDetailsScreen(
                    batch: batch,
                    type: widget.type,
                    repository: widget.repository,
                    directoryRepository: widget.directoryRepository,
                  ),
                ),
              );
              if (mounted) await _controller.load();
            },
            cells: [
              DataCell(Text('#${batch.id}')),
              DataCell(
                Text(
                  batch.date == null
                      ? '—'
                      : DateFormat('dd/MM/yyyy').format(batch.date!),
                ),
              ),
              DataCell(
                Text(batch.deliveredBy.isEmpty ? '—' : batch.deliveredBy),
              ),
              DataCell(Text(batch.origin.isEmpty ? '—' : batch.origin)),
              DataCell(
                Text(batch.quantity == null ? '—' : quantity(batch.quantity!)),
              ),
              DataCell(Text(money(batch.total))),
              DataCell(Text(money(batch.remaining))),
            ],
          ),
      ],
    );
  }
}
