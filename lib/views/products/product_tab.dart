import '../maintenance/record_recovery_button.dart';
import '../../models/products/product_list_report.dart';
import '../../models/reports/report_models.dart';
import '../finance/finance_list_widgets.dart';
import '../../models/products/product_details.dart';
import 'product_details_screen.dart';
import 'dart:async';
import '../../controllers/cart_controller.dart';
import 'package:flutter/material.dart';
import '../../models/dashboard/dashboard_module.dart';
import '../../controllers/product_list_controller.dart';
import '../../models/repositories/inventory_repository.dart';
import '../../models/repositories/directory_repository.dart';
import '../../services/mongo_inventory_repository.dart';
import '../../core/formatters/inventory_formatters.dart';
import '../widgets/scrollable_data_table.dart';
import '../../models/goods_receipt/goods_receipt_models.dart';
import '../goods_receipt/goods_receipt_screen.dart';

/// Product category list with search and goods receipt entry.
class ProductTab extends StatefulWidget {
  const ProductTab({
    super.key,
    required this.module,
    this.repository,
    this.directoryRepositoryFactory,
    this.exportReport,
  });
  final DashboardModule module;
  final InventoryRepository? repository;
  final Future<bool> Function(String, ReportSection, DateTime)? exportReport;
  final DirectoryRepository Function()? directoryRepositoryFactory;

  @override
  State<ProductTab> createState() => _ProductTabState();
}

class _ProductTabState extends State<ProductTab>
    with AutomaticKeepAliveClientMixin {
  static const _toolbarHeight = 48.0;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  late final ProductListController _list;

  @override
  void initState() {
    super.initState();
    _list = ProductListController(
      widget.repository ?? MongoInventoryRepository(),
      widget.module,
    );
    unawaited(_list.load());
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _list.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _openEntry() async {
    final directory = widget.directoryRepositoryFactory?.call();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => GoodsReceiptScreen(
          directoryRepository: directory,
          type: switch (widget.module) {
            DashboardModule.newVehicles => ReceiptProductType.newVehicle,
            DashboardModule.usedVehicles => ReceiptProductType.usedVehicle,
            DashboardModule.parts => ReceiptProductType.part,
            _ => throw StateError('Mục này không hỗ trợ nhập hàng'),
          },
        ),
      ),
    );
    if (directory != null) await directory.close();
    if (mounted) await _list.load();
  }

  Future<void> _openProduct(Map<String, dynamic> row) async {
    final vehicle = widget.module != DashboardModule.parts;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ProductDetailsScreen(
          product: ProductReference(
            id: (row[vehicle ? 'IdXe' : 'IdSanPham'] as num).toInt(),
            vehicle: vehicle,
          ),
        ),
      ),
    );
    if (mounted) await _list.load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListenableBuilder(
      listenable: _list,
      builder: (context, _) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5EAED)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _toolbar(),
            const SizedBox(height: 16),
            Expanded(child: _content()),
          ],
        ),
      ),
    );
  }

  ReportSection get _report => ProductListReport.products(
    _list.data?.rows ?? [],
    vehicle: widget.module != DashboardModule.parts,
    search: _list.search,
    availability: _list.availability,
  );
  Widget _toolbar() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: ListenableBuilder(
          listenable: _searchFocus,
          builder: (context, _) => Container(
            key: ValueKey('product-search-${widget.module.name}'),
            height: _toolbarHeight,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _searchFocus.hasFocus
                    ? const Color(0xFF176455)
                    : const Color(0xFFE0E7E9),
              ),
            ),
            child: TextField(
              controller: _search,
              focusNode: _searchFocus,
              textAlignVertical: TextAlignVertical.center,
              onChanged: _list.searchChanged,
              decoration: InputDecoration(
                hintText: widget.module.searchHint,
                prefixIcon: const Icon(Icons.search, size: 20),
                prefixIconConstraints: const BoxConstraints.tightFor(
                  width: _toolbarHeight,
                  height: _toolbarHeight - 2,
                ),
                suffixIcon: PopupMenuButton<String>(
                  tooltip: 'Lọc sản phẩm',
                  icon: const Icon(Icons.filter_list),
                  initialValue: _list.availability,
                  onSelected: _list.setAvailability,
                  itemBuilder: (_) => [
                    for (final entry in {
                      'available': 'Chưa bán / còn hàng',
                      'sold': 'Đã bán / hết hàng',
                      'all': 'Tất cả',
                    }.entries)
                      CheckedPopupMenuItem(
                        value: entry.key,
                        checked: _list.availability == entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                ),
                contentPadding: const EdgeInsets.only(right: 0),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ),
      ),
      const SizedBox(width: 12),
      SizedBox(
        width: _toolbarHeight,
        height: _toolbarHeight,
        child: IconButton.filled(
          key: ValueKey('product-add-${widget.module.name}'),
          tooltip: widget.module.entryTitle,
          onPressed: _openEntry,
          icon: const Icon(Icons.add),
          style: IconButton.styleFrom(
            fixedSize: const Size.square(_toolbarHeight),
            minimumSize: const Size.square(_toolbarHeight),
            maximumSize: const Size.square(_toolbarHeight),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: const Color(0xFF176455),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
      RecordRecoveryButton(onChanged: _list.load),
      if (_list.data != null && !_list.loading && _list.error == null) ...[
        const SizedBox(width: 12),
        SizedBox(
          height: 48,
          child: FinanceExcelButton(
            key: ValueKey('product-export-${widget.module.name}'),
            title: widget.module.label,
            section: _report,
            loadedAt: _list.loadedAt ?? DateTime.now(),
            exporter: widget.exportReport,
          ),
        ),
      ],
    ],
  );

  Widget _content() {
    if (_list.loading) return const Center(child: CircularProgressIndicator());
    if (_list.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_list.error!, textAlign: TextAlign.center),
            TextButton(onPressed: _list.load, child: const Text('Thử lại')),
          ],
        ),
      );
    }
    final rows = _list.data!.rows;
    if (rows.isEmpty) {
      return Center(
        child: Text(
          _search.text.trim().isNotEmpty
              ? 'Không tìm thấy sản phẩm.'
              : widget.module == DashboardModule.parts
              ? 'Chưa có phụ tùng.'
              : 'Chưa có xe trong danh sách.',
        ),
      );
    }
    final vehicle = widget.module != DashboardModule.parts;
    return LayoutBuilder(
      builder: (context, bounds) {
        if (bounds.maxWidth < 700) {
          return Column(
            children: [
              Expanded(
                child: ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 24),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return InkWell(
                      onTap: () => _openProduct(row),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${row[vehicle ? 'TenXe' : 'TenSanPham'] ?? ''}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text('#${row[vehicle ? 'IdXe' : 'IdSanPham']}'),
                                if (vehicle) _vehicleIdentity(row),
                                if (vehicle)
                                  Text('Giá nhập: ${money(row['GiaNhap'])}'),
                                Text(
                                  'Chi phí: ${money(row['TongChiPhi'] ?? 0)}',
                                ),
                                if (!vehicle)
                                  Text('Đơn vị: ${_value(row['DonViTinh'])}'),
                                Text(
                                  'Tồn kho: ${row['SoLuongTon'] ?? 'Chưa ghi nhận'}',
                                ),
                                Text(
                                  '${vehicle ? 'Giá bán' : 'Giá tham khảo'}: ${money(row[vehicle ? 'GiaBan' : 'GiaBanThamKhao'])}',
                                ),
                              ],
                            ),
                          ),
                          _cartCell(row, vehicle).child,
                        ],
                      ),
                    );
                  },
                ),
              ),
              FinanceTotalsStrip(
                totals: _report.totals,
                quantityLabels: const {'Tồn kho'},
              ),
            ],
          );
        }
        return ScrollableDataTable(
          fixedHeader: true,
          footerRow: DataRow(
            cells: vehicle
                ? [
                    DataCell(const Text('Tổng')),
                    DataCell.empty,
                    DataCell.empty,
                    for (final key in ['Giá nhập', 'Chi phí', 'Giá bán'])
                      DataCell(
                        Text(
                          _report.totals[key] == null
                              ? ''
                              : money(_report.totals[key]),
                        ),
                      ),
                    DataCell(
                      Text(
                        _report.totals['Tồn kho'] == null
                            ? ''
                            : quantity(_report.totals['Tồn kho']!),
                      ),
                    ),
                    DataCell.empty,
                  ]
                : [
                    DataCell(const Text('Tổng')),
                    DataCell.empty,
                    DataCell.empty,
                    DataCell(
                      Text(
                        _report.totals['Tồn kho'] == null
                            ? ''
                            : quantity(_report.totals['Tồn kho']!),
                      ),
                    ),
                    DataCell.empty,
                    DataCell(
                      Text(
                        _report.totals['Chi phí'] == null
                            ? ''
                            : money(_report.totals['Chi phí']),
                      ),
                    ),
                    DataCell.empty,
                  ],
          ),
          fitWidth: true,
          rowHeight: vehicle ? 102 : 64,
          columnWidths: vehicle
              ? const [70, 160, 210, 120, 120, 120, 70, 56]
              : const [140, 240, 100, 120, 150, 130, 64],
          columns: vehicle
              ? const [
                  DataColumn(label: Text('MÃ XE')),
                  DataColumn(label: Text('TÊN XE')),
                  DataColumn(label: Text('THÔNG TIN')),
                  DataColumn(label: Text('GIÁ NHẬP')),
                  DataColumn(label: Text('CHI PHÍ')),
                  DataColumn(label: Text('GIÁ BÁN')),
                  DataColumn(label: Text('TỒN KHO')),
                  DataColumn(label: Text('')),
                ]
              : const [
                  DataColumn(label: Text('MÃ SẢN PHẨM')),
                  DataColumn(label: Text('TÊN PHỤ TÙNG')),
                  DataColumn(label: Text('ĐƠN VỊ')),
                  DataColumn(label: Text('TỒN KHO')),
                  DataColumn(label: Text('GIÁ THAM KHẢO')),
                  DataColumn(label: Text('CHI PHÍ')),
                  DataColumn(label: Text('')),
                ],
          rowCount: rows.length,
          rowBuilder: (index) {
            final row = rows[index];
            return DataRow(
              onSelectChanged: (_) => _openProduct(row),
              cells: vehicle
                  ? [
                      DataCell(Text('#${row['IdXe']}')),
                      DataCell(Text('${row['TenXe'] ?? ''}')),
                      DataCell(_vehicleIdentity(row)),
                      DataCell(Text(money(row['GiaNhap']))),
                      DataCell(Text(money(row['TongChiPhi'] ?? 0))),
                      DataCell(Text(money(row['GiaBan']))),
                      DataCell(
                        Text(row['SoLuongTon']?.toString() ?? 'Chưa ghi nhận'),
                      ),
                      _cartCell(row, true),
                    ]
                  : [
                      DataCell(Text('${row['MaSanPham'] ?? row['IdSanPham']}')),
                      DataCell(Text('${row['TenSanPham'] ?? ''}')),
                      DataCell(Text(_value(row['DonViTinh']))),
                      DataCell(
                        Text(
                          row['SoLuongTon'] == null
                              ? 'Chưa ghi nhận'
                              : row['SoLuongTon'] is num
                              ? quantity(row['SoLuongTon'] as num)
                              : '${row['SoLuongTon']}',
                        ),
                      ),
                      DataCell(Text(money(row['GiaBanThamKhao']))),
                      DataCell(Text(money(row['TongChiPhi'] ?? 0))),
                      _cartCell(row, false),
                    ],
            );
          },
        );
      },
    );
  }

  Widget _vehicleIdentity(Map<String, dynamic> row) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final entry in {
        'Số khung': row['SoKhung'],
        'Số máy': row['SoMay'],
        'Biển số': row['BienSo'],
        'Màu sơn': row['MauSon'],
      }.entries)
        Tooltip(
          message: '${entry.key}: ${_value(entry.value)}',
          child: Text(
            '${entry.key}: ${_value(entry.value)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, height: 1.5),
          ),
        ),
    ],
  );

  DataCell _cartCell(Map<String, dynamic> row, bool vehicle) => DataCell(
    onTap: () {},
    IconButtonTheme(
      data: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(32),
          fixedSize: const Size.square(32),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Thêm vào đơn bán hàng',
            icon: const Icon(Icons.add_shopping_cart),
            onPressed: row['SoLuongTon'] is num && row['SoLuongTon'] > 0
                ? () {
                    final added = CartController.shared.add(
                      row,
                      vehicle: vehicle,
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          added
                              ? 'Đã thêm vào đơn bán hàng'
                              : 'Sản phẩm đã có trong đơn hoặc đã đủ số lượng tồn',
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                : null,
          ),
        ],
      ),
    ),
  );
  String _value(dynamic value) =>
      value == null || value.toString().trim().isEmpty ? '—' : value.toString();
}
