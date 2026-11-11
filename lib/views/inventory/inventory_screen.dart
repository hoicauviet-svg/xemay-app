import 'package:flutter/material.dart';
import '../../controllers/inventory_controller.dart';
import '../../models/inventory/inventory_models.dart';
import '../../core/formatters/inventory_formatters.dart';

const _ink = Color(0xFF1D3036),
    _muted = Color(0xFF6E7D83),
    _green = Color(0xFF176455);

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key, required this.controller});
  final InventoryController controller;
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _scaffold = GlobalKey<ScaffoldState>();
  final _search = TextEditingController();
  InventoryController get _controller => widget.controller;
  InventorySection get _view => _controller.section;
  InventorySummary? get _summary => _controller.summary;
  InventoryPage? get _data => _controller.data;
  String get _condition => _controller.condition;
  String? get _error => _controller.error;
  bool get _loading => _controller.loading;
  bool get _connected => _controller.connected;
  int get _page => _controller.page;

  Future<void> _load({bool refreshSummary = false}) =>
      _controller.load(refreshSummary: refreshSummary);

  void _navigate(InventorySection section) {
    _scaffold.currentState?.closeDrawer();
    _search.clear();
    _controller.selectSection(section);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => LayoutBuilder(
      builder: (context, bounds) {
        final wide = bounds.maxWidth >= 1050;
        return Scaffold(
          key: _scaffold,
          appBar: wide ? null : AppBar(title: const Text('Xe Máy Toàn Hợp')),
          drawer: wide ? null : Drawer(child: _navigation()),
          body: Row(
            children: [
              if (wide) SizedBox(width: 260, child: _navigation()),
              Expanded(
                child: Column(
                  children: [
                    if (wide) _topBar(),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.all(wide ? 28 : 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _view == InventorySection.products
                                  ? 'Danh mục sản phẩm'
                                  : viewName(_view),
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                color: _ink,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(switch (_view) {
                              InventorySection.products =>
                                'Danh mục chung cho xe và phụ tùng của cửa hàng.',
                              InventorySection.vehicles =>
                                'Quản lý từng chiếc xe, tình trạng và thông tin nhận diện.',
                              InventorySection.parts =>
                                'Mỗi mã phụ tùng được quản lý theo số lượng và đơn vị tính.',
                            }, style: const TextStyle(color: _muted)),
                            const SizedBox(height: 22),
                            if (_summary != null && bounds.maxHeight > 650) ...[
                              _stats(),
                              const SizedBox(height: 22),
                            ],
                            _toolbar(),
                            const SizedBox(height: 16),
                            Expanded(child: _content()),
                            if (_data != null && _error == null && !_loading)
                              _pagination(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _navigation() => Material(
    color: Colors.white,
    child: Container(
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0xFFE5EAED))),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 28, 16, 30),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _green,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.two_wheeler, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Xe Máy Toàn Hợp',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            height: 1.2,
                            color: _ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(left: 24, bottom: 12),
              child: Text(
                'QUẢN LÝ HÀNG HÓA',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.4,
                  color: _muted,
                ),
              ),
            ),
            for (final v in InventorySection.values)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 3,
                ),
                child: ListTile(
                  selected: _view == v,
                  selectedTileColor: const Color(0xFFEAF3EF),
                  selectedColor: _green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  leading: Icon(switch (v) {
                    InventorySection.products => Icons.inventory_2_outlined,
                    InventorySection.vehicles => Icons.two_wheeler_outlined,
                    InventorySection.parts => Icons.build_outlined,
                  }),
                  title: Text(
                    viewName(v),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () => _navigate(v),
                ),
              ),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.desktop_windows_outlined,
                        size: 16,
                        color: _muted,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Dữ liệu trên máy',
                          style: TextStyle(fontSize: 12, color: _muted),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Làm việc không cần Internet',
                    style: TextStyle(fontSize: 11, color: _muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _topBar() => Container(
    height: 64,
    padding: const EdgeInsets.symmetric(horizontal: 28),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: Color(0xFFE5EAED))),
    ),
    child: Row(
      children: [
        const Text(
          'Không gian làm việc',
          style: TextStyle(color: _muted, fontSize: 13),
        ),
        const Spacer(),
        Icon(
          _connected
              ? Icons.check_circle_outline
              : Icons.radio_button_unchecked,
          size: 16,
          color: _connected ? _green : _muted,
        ),
        const SizedBox(width: 7),
        Text(
          _connected ? 'Đã kết nối dữ liệu' : 'Đang chờ kết nối',
          style: const TextStyle(fontSize: 12, color: _muted),
        ),
        const SizedBox(width: 24),
        const CircleAvatar(
          radius: 16,
          backgroundColor: Color(0xFFEDF1F2),
          child: Icon(Icons.person_outline, size: 19, color: _ink),
        ),
      ],
    ),
  );

  Widget _stats() => LayoutBuilder(
    builder: (context, bounds) {
      final stats = [
        ('Danh mục sản phẩm', _summary!.products, Icons.category_outlined),
        ('Tổng số chiếc xe', _summary!.vehicles, Icons.two_wheeler_outlined),
        ('Mã phụ tùng', _summary!.parts, Icons.build_outlined),
      ];
      return Wrap(
        spacing: 14,
        runSpacing: 12,
        children: [
          for (final s in stats)
            Container(
              width: (bounds.maxWidth - 28) / 3,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5EAED)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.$1,
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          quantity(s.$2),
                          style: const TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w700,
                            color: _ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (bounds.maxWidth > 700)
                    Icon(s.$3, color: _green, size: 28),
                ],
              ),
            ),
        ],
      );
    },
  );

  Widget _toolbar() => Wrap(
    spacing: 12,
    runSpacing: 10,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 330),
        child: TextField(
          controller: _search,
          decoration: InputDecoration(
            hintText: _view == InventorySection.vehicles
                ? 'Tìm theo tên hoặc mã xe…'
                : 'Tìm tên hoặc mã sản phẩm…',
            prefixIcon: const Icon(Icons.search, size: 20),
            isDense: true,
          ),
          onChanged: _controller.searchChanged,
        ),
      ),
      if (_view == InventorySection.vehicles)
        DropdownButton<String>(
          value: _condition,
          underline: const SizedBox.shrink(),
          items: const [
            DropdownMenuItem(value: '', child: Text('Tất cả tình trạng')),
            DropdownMenuItem(value: 'moi', child: Text('Xe mới')),
            DropdownMenuItem(value: 'cu', child: Text('Xe cũ')),
            DropdownMenuItem(
              value: 'chua_xac_dinh',
              child: Text('Chưa phân loại'),
            ),
          ],
          onChanged: (value) => _controller.setCondition(value ?? ''),
        ),
      OutlinedButton.icon(
        onPressed: _loading ? null : () => _load(refreshSummary: true),
        icon: const Icon(Icons.refresh, size: 18),
        label: const Text('Làm mới'),
      ),
    ],
  );

  Widget _content() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _empty(
        Icons.cloud_off_outlined,
        'Chưa mở được dữ liệu',
        _error!,
        action: FilledButton(
          onPressed: () => _load(refreshSummary: true),
          child: const Text('Thử kết nối lại'),
        ),
      );
    }
    if (_data == null || _data!.rows.isEmpty) {
      return _empty(
        _view == InventorySection.parts
            ? Icons.build_outlined
            : Icons.search_off_outlined,
        _search.text.isEmpty && _view == InventorySection.parts
            ? 'Chưa có phụ tùng'
            : 'Không có kết quả',
        _search.text.isEmpty && _view == InventorySection.parts
            ? 'Kho đã sẵn sàng. Chức năng nhập phụ tùng sẽ được bổ sung ở bước tiếp theo.'
            : 'Thử thay đổi từ khóa hoặc bộ lọc để tìm lại.',
      );
    }
    final vehicle = _view == InventorySection.vehicles;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5EAED)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: LayoutBuilder(
          builder: (context, bounds) => SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: bounds.maxWidth),
                child: DataTable(
                  showCheckboxColumn: false,
                  horizontalMargin: 20,
                  columnSpacing: 28,
                  dataRowMinHeight: 60,
                  dataRowMaxHeight: 66,
                  columns: [
                    const DataColumn(label: Text('MÃ')),
                    DataColumn(label: Text(vehicle ? 'TÊN XE' : 'SẢN PHẨM')),
                    DataColumn(
                      label: Text(vehicle ? 'TÌNH TRẠNG' : 'LOẠI HÀNG'),
                    ),
                    DataColumn(label: Text(vehicle ? 'GIÁ NHẬP' : 'ĐƠN VỊ')),
                    DataColumn(
                      label: Text(vehicle ? 'GIÁ BÁN ĐÃ GHI' : 'QUẢN LÝ'),
                    ),
                    const DataColumn(label: Text('')),
                  ],
                  rows: _data!.rows
                      .map(
                        (row) => DataRow(
                          onSelectChanged: (_) => _showDetails(row),
                          cells: [
                            DataCell(
                              Text(
                                vehicle
                                    ? '#${row['IdXe']}'
                                    : '${row['MaSanPham'] ?? row['IdSanPham']}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: _muted,
                                ),
                              ),
                            ),
                            DataCell(
                              SizedBox(
                                width: 220,
                                child: Text(
                                  '${row[vehicle ? 'TenXe' : 'TenSanPham'] ?? ''}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: _ink,
                                  ),
                                ),
                              ),
                            ),
                            DataCell(
                              _badge(
                                vehicle
                                    ? conditionName(row['TinhTrangXe'])
                                    : row['LoaiSanPham'] == 'xe'
                                    ? 'Xe'
                                    : 'Phụ tùng',
                              ),
                            ),
                            DataCell(
                              Text(
                                vehicle
                                    ? money(row['GiaNhap'])
                                    : '${row['DonViTinh'] ?? '—'}',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            DataCell(
                              Text(
                                vehicle
                                    ? money(row['GiaBan'])
                                    : row['QuanLyTonKho'] == 'tung_chiec'
                                    ? 'Từng chiếc'
                                    : 'Số lượng',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: _muted,
                                ),
                              ),
                            ),
                            const DataCell(
                              Icon(
                                Icons.chevron_right,
                                size: 20,
                                color: _muted,
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFEDF4F0),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(label, style: const TextStyle(color: _green, fontSize: 12)),
  );

  Widget _empty(IconData icon, String title, String text, {Widget? action}) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: _muted),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 450),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _muted),
                ),
              ),
              if (action != null) ...[const SizedBox(height: 20), action],
            ],
          ),
        ),
      );

  Widget _pagination() => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            _data!.total == 0
                ? '0 bản ghi'
                : '${_page * _controller.pageSize + 1}–${_page * _controller.pageSize + _data!.rows.length} / ${quantity(_data!.total)} bản ghi',
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
        ),
        IconButton(
          tooltip: 'Trang trước',
          onPressed: _controller.hasPreviousPage
              ? _controller.previousPage
              : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Text('${_page + 1}', style: const TextStyle(fontSize: 12)),
        IconButton(
          tooltip: 'Trang sau',
          onPressed: _controller.hasNextPage ? _controller.nextPage : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    ),
  );

  Future<void> _showDetails(Map<String, dynamic> row) async {
    final view = _view;
    final future = _controller.details(view, row);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '${row[view == InventorySection.vehicles ? 'TenXe' : 'TenSanPham']}',
        ),
        content: SizedBox(
          width: 540,
          child: FutureBuilder<Map<String, dynamic>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text(
                  'Chưa tải được chi tiết. Hãy đóng và thử lại.',
                );
              }
              if (!snapshot.hasData) {
                return const SizedBox(
                  height: 100,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final d = snapshot.data!;
              final fields = <(String, String)>[
                ('Mã sản phẩm', '${d['IdSanPham']}'),
                if (view == InventorySection.vehicles) ...[
                  ('Mã chiếc xe', '${d['IdXe']}'),
                  ('Tình trạng', conditionName(d['TinhTrangXe'])),
                  ('Số khung', '${d['SoKhung'] ?? 'Chưa ghi nhận'}'),
                  ('Số máy', '${d['SoMay'] ?? 'Chưa ghi nhận'}'),
                  ('Biển số', '${d['BienSo'] ?? 'Chưa ghi nhận'}'),
                  ('Giá nhập', money(d['GiaNhap'])),
                  ('Giá bán đã ghi', money(d['GiaBan'])),
                ] else ...[
                  ('Loại hàng', d['LoaiSanPham'] == 'xe' ? 'Xe' : 'Phụ tùng'),
                  ('Đơn vị', '${d['DonViTinh'] ?? '—'}'),
                  if (d.containsKey('SoChiecLienKet'))
                    ('Số chiếc xe liên kết', '${d['SoChiecLienKet']}'),
                  if (d['LoaiSanPham'] == 'phu_tung')
                    (
                      'Tồn kho',
                      d['DaKiemKe'] == true
                          ? '${d['SoLuongTon']}'
                          : 'Chưa ghi nhận tồn',
                    ),
                ],
              ];
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final f in fields)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 150,
                              child: Text(
                                f.$1,
                                style: const TextStyle(color: _muted),
                              ),
                            ),
                            Expanded(child: SelectableText(f.$2)),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }
}
