import '../../models/repositories/batch_repository.dart';
import '../../models/goods_receipt/goods_receipt_models.dart';
import '../../services/mongo_batch_repository.dart';
import '../batches/batch_details_screen.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../controllers/partner_details_controller.dart';
import '../../core/formatters/inventory_formatters.dart';
import '../../models/repositories/partner_repository.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/form_section.dart';
import '../widgets/scrollable_data_table.dart';

class PartnerDetailsScreen extends StatefulWidget {
  const PartnerDetailsScreen({
    super.key,
    required this.partnerId,
    required this.repository,
    this.batchRepositoryFactory,
  });
  final String partnerId;
  final PartnerRepository repository;
  final BatchRepository Function()? batchRepositoryFactory;
  @override
  State<PartnerDetailsScreen> createState() => _PartnerDetailsScreenState();
}

class _PartnerDetailsScreenState extends State<PartnerDetailsScreen> {
  late final PartnerDetailsController _controller;
  @override
  void initState() {
    super.initState();
    _controller = PartnerDetailsController(widget.repository, widget.partnerId);
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _value(dynamic v) =>
      v == null || v.toString().trim().isEmpty ? '—' : v.toString();
  String _date(dynamic v) =>
      v is DateTime ? DateFormat('dd/MM/yyyy').format(v) : _value(v);
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppTopBar(
          title:
              'Đối tác · ${_controller.partner?['TenDoiTac'] ?? widget.partnerId}',
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Thông tin'),
              Tab(text: 'Đơn nhập hàng'),
            ],
          ),
        ),
        body: _controller.loading
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
            : TabBarView(
                children: [
                  _information(),
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
                                  '${_controller.orders!.total} đơn nhập',
                                ),
                              ),
                              IconButton(
                                tooltip: 'Trang đơn nhập trước',
                                onPressed: _controller.page > 0
                                    ? () => _controller.goToPage(
                                        _controller.page - 1,
                                      )
                                    : null,
                                icon: const Icon(Icons.chevron_left),
                              ),
                              Text(
                                '${_controller.page + 1} / ${_controller.pageCount}',
                              ),
                              IconButton(
                                tooltip: 'Trang đơn nhập sau',
                                onPressed:
                                    _controller.page + 1 < _controller.pageCount
                                    ? () => _controller.goToPage(
                                        _controller.page + 1,
                                      )
                                    : null,
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    ),
  );
  Widget _information() {
    final partner = _controller.partner!;
    final fields = {
      'Mã đối tác': partner['_id'],
      'Tên đối tác': partner['TenDoiTac'],
      'Số điện thoại': partner['SoDienThoai'],
      'Mã số thuế': partner['MaSoThue'],
      'Người đại diện': partner['NguoiDaiDien'],
      'Ghi chú': partner['GhiChu'],
      'Địa chỉ chi tiết': partner['DiaChi'],
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: FormSection(
        title: 'Thông tin đối tác',
        children: [
          ResponsiveFormFields(
            fields: [
              for (final entry in fields.entries)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.key,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6E7D83),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      _value(entry.value),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  bool _openingOrder = false;
  Future<void> _openOrder(Map<String, dynamic> row) async {
    if (_openingOrder) return;
    _openingOrder = true;
    final repository =
        widget.batchRepositoryFactory?.call() ?? MongoBatchRepository();
    try {
      await repository.connect();
      final batch = await repository.findById(
        (row['IdNhapHang'] ?? row['MaDonHang']) as int,
      );
      if (!mounted) return;
      if (batch == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Không tìm thấy lô hàng. Vui lòng tải lại danh sách.',
            ),
          ),
        );
        return;
      }
      final type = switch (row['LoaiSanPham']) {
        'xe_cu' => ReceiptProductType.usedVehicle,
        'phu_tung' => ReceiptProductType.part,
        _ => ReceiptProductType.newVehicle,
      };
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => BatchDetailsScreen(
            batch: batch,
            type: type,
            repository: repository,
            directoryRepository: widget.repository,
          ),
        ),
      );
      if (mounted) await _controller.load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chưa mở được chi tiết lô hàng. Vui lòng thử lại.'),
          ),
        );
      }
    } finally {
      _openingOrder = false;
      await repository.close();
    }
  }

  Widget _orders() {
    final rows = _controller.orders!.rows;
    if (rows.isEmpty) {
      return const Center(child: Text('Đối tác chưa có đơn nhập hàng.'));
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
