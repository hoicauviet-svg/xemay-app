import 'dart:async';
import 'package:flutter/material.dart';
import '../../controllers/customer_controller.dart';
import '../../models/customers/customer_models.dart';
import '../../models/repositories/customer_repository.dart';
import '../../services/mongo_customer_repository.dart';
import '../widgets/scrollable_data_table.dart';
import 'customer_editor_popup.dart';
import 'customer_details_screen.dart';

class CustomerTab extends StatefulWidget {
  const CustomerTab({super.key, this.repository});
  final CustomerRepository? repository;
  @override
  State<CustomerTab> createState() => _CustomerTabState();
}

class _CustomerTabState extends State<CustomerTab>
    with AutomaticKeepAliveClientMixin {
  late final CustomerController _controller;
  bool _deleting = false;
  TabController? _tabs;
  bool _active = true;
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    _controller = CustomerController(
      widget.repository ?? MongoCustomerRepository(),
    );
    unawaited(_controller.load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tabs = DefaultTabController.maybeOf(context);
    if (_tabs != tabs) {
      _tabs?.removeListener(_tabChanged);
      _tabs = tabs;
      _active = tabs == null || tabs.index == 0;
      tabs?.addListener(_tabChanged);
    }
  }

  void _tabChanged() {
    final active = _tabs?.index == 0;
    if (active && !_active) unawaited(_controller.load());
    _active = active;
  }

  @override
  void dispose() {
    _tabs?.removeListener(_tabChanged);
    _controller.dispose();
    super.dispose();
  }

  void _openCustomer(Map<String, dynamic> row) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CustomerDetailsScreen(
          customerId: row['IdKH'] as int,
          repository: _controller.repository,
        ),
      ),
    );
  }

  Future<void> _add() async {
    final saved = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CustomerEditorPopup(onCreate: _controller.create),
    );
    if (saved != null && mounted) {
      _controller.page = 0;
      await _controller.load();
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa khách hàng'),
        content: Text(
          'Xóa khách hàng "${row['TenKhachHang']}" (#${row['IdKH']}) khỏi danh sách?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await _controller.delete(row);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã xóa khách hàng')));
        await _controller.load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is CustomerException
                  ? e.message
                  : 'Không xóa được khách hàng. Vui lòng thử lại.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _filter() async {
    var phone = _controller.phoneFilter;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Lọc khách hàng'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: phone,
                  decoration: const InputDecoration(labelText: 'Số điện thoại'),
                  items: [
                    for (final e in {
                      'all': 'Tất cả',
                      'with_phone': 'Có số điện thoại',
                      'without_phone': 'Chưa có số điện thoại',
                    }.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => phone = v!,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _controller.filterChanged('all');
              },
              child: const Text('Đặt lại'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _controller.filterChanged(phone);
              },
              child: const Text('Áp dụng'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final saved = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CustomerEditorPopup(
        initial: {...row, 'DiaChiHienThi': _controller.address(row)},
        onCreate: (draft) =>
            _controller.repository.update(row['IdKH'] as int, draft),
      ),
    );
    if (saved != null && mounted) {
      await _controller.load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cập nhật khách hàng thành công')),
        );
      }
    }
  }

  Widget _actions(Map<String, dynamic> row) => IconButtonTheme(
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
          tooltip: 'Cập nhật khách hàng',
          icon: const Icon(Icons.edit_outlined),
          onPressed: _deleting ? null : () => _edit(row),
        ),
        _deleteButton(row),
      ],
    ),
  );

  Widget _deleteButton(Map<String, dynamic> row) => IconButton(
    tooltip: 'Xóa khách hàng',
    icon: const Icon(Icons.delete_outline, color: Color(0xFFB44141)),
    onPressed: _deleting ? null : () => _delete(row),
  );
  String _value(dynamic v) =>
      v == null || v.toString().trim().isEmpty ? '—' : v.toString();
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListenableBuilder(
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
                      onChanged: _controller.searchChanged,
                      textAlignVertical: TextAlignVertical.center,
                      decoration: InputDecoration(
                        hintText: 'Tìm mã, tên, điện thoại, địa chỉ…',
                        prefixIcon: const Icon(Icons.search),
                        contentPadding: EdgeInsets.zero,
                        suffixIcon: IconButton(
                          tooltip: 'Lọc khách hàng',
                          onPressed: _controller.loading ? null : _filter,
                          icon: Icon(
                            Icons.filter_list,
                            color: _controller.phoneFilter != 'all'
                                ? const Color(0xFF176455)
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filled(
                  tooltip: 'Thêm khách hàng mới',
                  onPressed: _controller.loading || _controller.error != null
                      ? null
                      : _add,
                  icon: const Icon(Icons.person_add_alt_1),
                  style: IconButton.styleFrom(
                    fixedSize: const Size.square(48),
                    minimumSize: const Size.square(48),
                    maximumSize: const Size.square(48),
                    visualDensity: VisualDensity.standard,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(child: _body()),
            if (!_controller.loading && _controller.error == null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_controller.data?.total ?? 0} khách hàng',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Trang khách hàng trước',
                      onPressed: _controller.page > 0
                          ? () => _controller.goToPage(_controller.page - 1)
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text('${_controller.page + 1} / ${_controller.pageCount}'),
                    IconButton(
                      tooltip: 'Trang khách hàng sau',
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
  }

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
      return const Center(child: Text('Không có khách hàng phù hợp.'));
    }
    return LayoutBuilder(
      builder: (context, bounds) {
        if (bounds.maxWidth < 900) {
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (context, i) {
              final row = rows[i];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_value(row['TenKhachHang'])),
                subtitle: Text(
                  '#${row['IdKH']} · ${_value(row['SoDienThoai'])}\n${_value(_controller.address(row))}',
                ),
                isThreeLine: true,
                onTap: () => _openCustomer(row),
                trailing: _actions(row),
              );
            },
          );
        }
        return ScrollableDataTable(
          fixedHeader: true,
          fitWidth: true,
          columnWidths: const [90, 200, 150, 145, 125, 115, 150, 240, 180],
          columns: const [
            DataColumn(label: Text('MÃ KH')),
            DataColumn(label: Text('TÊN KHÁCH HÀNG')),
            DataColumn(label: Text('SỐ ĐIỆN THOẠI')),
            DataColumn(label: Text('CCCD')),
            DataColumn(label: Text('CMND')),
            DataColumn(label: Text('NGÀY CẤP')),
            DataColumn(label: Text('NƠI CẤP')),
            DataColumn(label: Text('ĐỊA CHỈ')),
            DataColumn(label: Text('')),
          ],
          rows: [
            for (final row in rows)
              DataRow(
                onSelectChanged: (_) => _openCustomer(row),
                cells: [
                  DataCell(Text('#${row['IdKH']}')),
                  DataCell(Text(_value(row['TenKhachHang']))),
                  DataCell(Text(_value(row['SoDienThoai']))),
                  DataCell(Text(_value(row['SoCCCD']))),
                  DataCell(Text(_value(row['SoCMND']))),
                  DataCell(Text(CustomerDraft.formatIssueDate(row['NgayCap']))),
                  DataCell(Text(_value(row['NoiCap']))),
                  DataCell(Text(_value(_controller.address(row)))),
                  DataCell(_actions(row)),
                ],
              ),
          ],
        );
      },
    );
  }
}
